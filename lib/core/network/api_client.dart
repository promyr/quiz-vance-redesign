import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import 'api_endpoints.dart';
import 'api_request_policy.dart';

const _tokenKey = 'auth_token';
const _refreshTokenKey = 'refresh_token';
const _authRetryKey = 'auth_retry_count';
const _networkRetryKey = 'network_retry_count';

/// Dio configurado com interceptor JWT automatico + refresh em 401.
class ApiClient {
  ApiClient() {
    final baseOptions = BaseOptions(
      baseUrl: AppConfig.backendUrl,
      connectTimeout: AppConfig.connectTimeout,
      sendTimeout: AppConfig.sendTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'X-App-Version': AppConfig.appVersion,
        'X-Client-App': AppConfig.clientAppId,
        'X-Ranking-Namespace': AppConfig.rankingNamespace,
      },
    );
    _dio = Dio(baseOptions);
    _refreshDio = Dio(baseOptions);
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  late final Dio _dio;
  late final Dio _refreshDio;
  final _storage = const FlutterSecureStorage();
  Future<bool>? _refreshFuture;
  final _sessionExpiredController = StreamController<void>.broadcast();
  static int _requestSequence = 0;

  Dio get dio => _dio;
  Stream<void> get sessionExpired => _sessionExpiredController.stream;

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers['X-App-Version'] = AppConfig.appVersion;
    options.headers['X-Client-App'] = AppConfig.clientAppId;
    options.headers['X-Ranking-Namespace'] = AppConfig.rankingNamespace;
    options.headers.putIfAbsent('X-Request-ID', _nextRequestId);
    if (isLongRunningApiPath(options.path)) {
      options.receiveTimeout = AppConfig.generationTimeout;
    }
    final token = await _storage.read(key: _tokenKey);
    final skipAuth =
        options.extra['skipAuth'] == true || isPublicApiPath(options.path);
    if (!skipAuth && token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    final retryCount = (request.extra[_authRetryKey] as int?) ?? 0;
    final isUnauthorized = err.response?.statusCode == 401;

    if (isUnauthorized && !isPublicApiPath(request.path) && retryCount == 0) {
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        final token = await _storage.read(key: _tokenKey);
        final retryRequest = _cloneRequestOptions(
          request,
          headers: {
            ...request.headers,
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          extra: {
            ...request.extra,
            _authRetryKey: retryCount + 1,
          },
        );
        final response = await _dio.fetch(retryRequest);
        return handler.resolve(response);
      }
      await clearTokens();
      _sessionExpiredController.add(null);
    }

    final networkRetryCount = (request.extra[_networkRetryKey] as int?) ?? 0;
    final isTransient = isRetryableStatus(err.response?.statusCode) ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout;
    if (!isUnauthorized &&
        isTransient &&
        isIdempotentMethod(request.method) &&
        networkRetryCount < 2) {
      await Future<void>.delayed(
        Duration(milliseconds: 250 * (1 << networkRetryCount)),
      );
      final retryRequest = _cloneRequestOptions(
        request,
        extra: {
          ...request.extra,
          _networkRetryKey: networkRetryCount + 1,
        },
      );
      final response = await _dio.fetch(retryRequest);
      return handler.resolve(response);
    }

    return handler.next(err);
  }

  Future<bool> _tryRefreshToken() async {
    final inFlightRefresh = _refreshFuture;
    if (inFlightRefresh != null) return inFlightRefresh;

    final refreshFuture = _performTokenRefresh();
    _refreshFuture = refreshFuture;

    try {
      return await refreshFuture;
    } finally {
      if (identical(_refreshFuture, refreshFuture)) {
        _refreshFuture = null;
      }
    }
  }

  Future<bool> _performTokenRefresh() async {
    try {
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      final accessToken = await _storage.read(key: _tokenKey);
      final tokenToRefresh = refreshToken ?? accessToken;
      if (tokenToRefresh == null || tokenToRefresh.isEmpty) return false;

      final response = await _refreshDio.post(
        ApiEndpoints.refreshToken,
        options: Options(
          headers: {'Authorization': 'Bearer $tokenToRefresh'},
          extra: {'skipAuth': true},
        ),
      );

      final data = response.data as Map<String, dynamic>?;
      final newToken = data?['access_token'] as String?;
      if (newToken == null || newToken.isEmpty) return false;

      await saveTokens(
        accessToken: newToken,
        refreshToken: data?['refresh_token'] as String? ?? tokenToRefresh,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  RequestOptions _cloneRequestOptions(
    RequestOptions request, {
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
  }) {
    return RequestOptions(
      path: request.path,
      method: request.method,
      baseUrl: request.baseUrl,
      data: request.data,
      queryParameters: Map<String, dynamic>.from(request.queryParameters),
      headers: headers ?? Map<String, dynamic>.from(request.headers),
      extra: extra ?? Map<String, dynamic>.from(request.extra),
      connectTimeout: request.connectTimeout,
      sendTimeout: request.sendTimeout,
      receiveTimeout: request.receiveTimeout,
      responseType: request.responseType,
      contentType: request.contentType,
      validateStatus: request.validateStatus,
      receiveDataWhenStatusError: request.receiveDataWhenStatusError,
      followRedirects: request.followRedirects,
      maxRedirects: request.maxRedirects,
      requestEncoder: request.requestEncoder,
      responseDecoder: request.responseDecoder,
      listFormat: request.listFormat,
      cancelToken: request.cancelToken,
    );
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _tokenKey, value: accessToken),
      _storage.write(
        key: _refreshTokenKey,
        value: refreshToken.isEmpty ? accessToken : refreshToken,
      ),
    ]);
  }

  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }

  Future<String?> getAccessToken() => _storage.read(key: _tokenKey);

  void dispose() {
    _sessionExpiredController.close();
    _dio.close(force: true);
    _refreshDio.close(force: true);
  }

  static String _nextRequestId() {
    _requestSequence++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_requestSequence';
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.dispose);
  return client;
});
