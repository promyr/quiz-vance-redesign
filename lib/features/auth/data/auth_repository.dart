import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/observability/app_observability.dart';
import '../../../core/storage/local_storage.dart';

const _userCacheKey = 'auth_user_cache';
const _sessionModeCacheKey = 'auth_session_mode';

enum AuthSessionMode {
  none,
  jwt,
}

class PersistedAuthSession {
  const PersistedAuthSession({
    required this.mode,
    this.user,
  });

  const PersistedAuthSession.none() : this(mode: AuthSessionMode.none);

  final AuthSessionMode mode;
  final Map<String, dynamic>? user;
}

class AuthRepository {
  AuthRepository(
    this._client, {
    LocalStorage? storage,
    AppObservability? observability,
  })  : _storage = storage ?? LocalStorage.instance,
        _observability = observability ?? AppObservability.instance;

  final ApiClient _client;
  final LocalStorage _storage;
  final AppObservability _observability;

  Future<Map<String, dynamic>> login({
    required String loginId,
    required String password,
  }) async {
    final normalizedLoginId = loginId.trim();
    _observability.trackEvent(
      'auth.login_requested',
      attributes: <String, Object?>{
        'login_kind': normalizedLoginId.contains('@') ? 'email' : 'login_id',
      },
    );
    try {
      final response = await _client.dio.post(
        ApiEndpoints.login,
        data: {
          'login_id': normalizedLoginId,
          'id': normalizedLoginId,
          if (normalizedLoginId.contains('@')) 'email': normalizedLoginId,
          if (normalizedLoginId.contains('@')) 'email_id': normalizedLoginId,
          'password': password,
        },
      );
      final normalized =
          _normalizeAuthResponse(response.data as Map<String, dynamic>);
      await _persistJwtSession(normalized);
      _observability.trackEvent('auth.login_succeeded');
      return normalized;
    } catch (error, stackTrace) {
      _observability.reportError(
        'auth.login_failed',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String loginId,
    required String email,
    required String password,
  }) async {
    final normalizedLoginId = loginId.trim();
    _observability.trackEvent('auth.register_requested');
    try {
      final response = await _client.dio.post(
        ApiEndpoints.register,
        data: {
          'name': name,
          'login_id': normalizedLoginId,
          'id': normalizedLoginId,
          'email': email,
          'email_id': email,
          'password': password,
        },
      );
      final normalized =
          _normalizeAuthResponse(response.data as Map<String, dynamic>);
      await _persistJwtSession(normalized);
      _observability.trackEvent('auth.register_succeeded');
      return normalized;
    } catch (error, stackTrace) {
      _observability.reportError(
        'auth.register_failed',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.me);
      final raw = response.data;
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('resposta inesperada de /auth/me');
      }
      final user = _extractUser(raw);
      await _cacheUser(user);
      _observability.trackEvent('auth.me_succeeded');
      return user;
    } on DioException catch (e) {
      _debugLog(
        '[AuthRepository.getMe] falhou com DioException '
        '(${e.type.name}, status=${e.response?.statusCode ?? 0})',
      );
      final isOffline = e.response == null &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.unknown);

      if (!isOffline) {
        rethrow;
      }

      final cached = await getCachedUser();
      if (cached != null) {
        _observability.trackEvent(
          'auth.me_cache_fallback',
          level: AppEventLevel.warning,
        );
        return cached;
      }
      rethrow;
    } catch (e) {
      _debugLog('[AuthRepository.getMe] falhou: $e');
      rethrow;
    }
  }

  Future<PersistedAuthSession> restorePersistedSession() async {
    final rawMode = await _storage.getCacheValue(_sessionModeCacheKey);
    final mode = _parseSessionMode(rawMode);
    final cachedUser = await getCachedUser();
    final token = await _client.getAccessToken();

    if (mode == AuthSessionMode.jwt) {
      if (token == null || token.isEmpty) {
        await clearSession();
        return const PersistedAuthSession.none();
      }
      return PersistedAuthSession(mode: AuthSessionMode.jwt, user: cachedUser);
    }

    if (token != null && token.isNotEmpty) {
      await _writeSessionMode(AuthSessionMode.jwt);
      return PersistedAuthSession(mode: AuthSessionMode.jwt, user: cachedUser);
    }

    return const PersistedAuthSession.none();
  }

  Future<Map<String, dynamic>?> getCachedUser() async {
    return _decodeCachedUser(await _storage.getCacheValue(_userCacheKey));
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? avatarUrl,
  }) async {
    final response = await _client.dio.post(
      ApiEndpoints.userUpdateProfile,
      data: {
        if (name != null) 'name': name.trim(),
        if (avatarUrl != null) 'avatar_url': avatarUrl.trim(),
      },
    );
    final raw = response.data;
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
          'resposta inesperada de /user/profile/update');
    }
    return raw;
  }

  Future<void> logout() async {
    final session = await restorePersistedSession();
    try {
      if (session.mode == AuthSessionMode.jwt) {
        await _client.dio.post(ApiEndpoints.logout);
      }
      _observability.trackEvent('auth.logout_requested');
    } on DioException {
      // Logout remoto best-effort.
    } finally {
      await clearSession();
      _observability.trackEvent('auth.logout_completed');
    }
  }

  Future<String> requestPasswordReset({required String identifier}) async {
    final response = await _client.dio.post(
      ApiEndpoints.passwordResetRequest,
      data: {'identifier': identifier.trim()},
    );
    final raw = response.data;
    if (raw is Map<String, dynamic>) {
      return raw['message'] as String? ??
          'Se a conta existir, enviaremos um codigo para o e-mail cadastrado.';
    }
    return 'Se a conta existir, enviaremos um codigo para o e-mail cadastrado.';
  }

  Future<String> confirmPasswordReset({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    final response = await _client.dio.post(
      ApiEndpoints.passwordResetConfirm,
      data: {
        'identifier': identifier.trim(),
        'code': code.trim(),
        'new_password': newPassword,
      },
    );
    final raw = response.data;
    if (raw is Map<String, dynamic>) {
      return raw['message'] as String? ?? 'Senha atualizada com sucesso.';
    }
    return 'Senha atualizada com sucesso.';
  }

  Future<void> clearSession() async {
    await Future.wait([
      _client.clearTokens(),
      _storage.deleteCacheValue(_userCacheKey),
      _storage.deleteCacheValue(_sessionModeCacheKey),
    ]);
  }

  Future<void> _persistJwtSession(Map<String, dynamic> normalized) async {
    final accessToken = (normalized['access_token'] as String? ?? '').trim();
    if (accessToken.isEmpty) {
      await clearSession();
      throw const FormatException('resposta de auth sem access_token valido');
    }

    final refreshToken =
        (normalized['refresh_token'] as String? ?? accessToken).trim();
    await _client.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    await _cacheUser((normalized['user'] as Map<String, dynamic>?) ?? const {});
    await _writeSessionMode(AuthSessionMode.jwt);
  }

  Future<void> _cacheUser(Map<String, dynamic> user) async {
    if (user.isEmpty) return;
    await _storage.setCacheValue(_userCacheKey, jsonEncode(user));
  }

  AuthSessionMode _parseSessionMode(String? raw) {
    switch (raw) {
      case 'jwt':
        return AuthSessionMode.jwt;
      default:
        return AuthSessionMode.none;
    }
  }

  Future<void> _writeSessionMode(AuthSessionMode mode) async {
    final value = switch (mode) {
      AuthSessionMode.none => 'none',
      AuthSessionMode.jwt => 'jwt',
    };
    await _storage.setCacheValue(_sessionModeCacheKey, value);
  }

  Map<String, dynamic>? _decodeCachedUser(String? raw) {
    if (raw == null || raw == '{}' || raw.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  Map<String, dynamic> _normalizeAuthResponse(Map<String, dynamic> raw) {
    final accessToken = (raw['access_token'] as String?) ?? '';
    final refreshToken = (raw['refresh_token'] as String?) ?? accessToken;
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'user': _extractUser(raw),
    };
  }

  Map<String, dynamic> _extractUser(Map<String, dynamic> raw) {
    final nested = raw['user'];
    final source = nested is Map<String, dynamic> ? nested : raw;
    return {
      'id': source['id']?.toString() ?? source['user_id']?.toString() ?? '',
      'name': source['name'] as String? ?? 'Usuario',
      'login_id': source['login_id'] as String? ?? '',
      'email':
          source['email'] as String? ?? source['email_id'] as String? ?? '',
      'avatar_url': source['avatar_url'] as String?,
      'plan_type': source['plan_type'] as String? ??
          source['plan_code'] as String? ??
          'free',
      'premium_active': source['premium_active'] as bool? ?? false,
      'xp': (source['xp'] as num?)?.toInt() ?? 0,
      'level': source['level'],
      'streak_days': (source['streak_days'] as num?)?.toInt() ?? 0,
    };
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    observability: ref.watch(appObservabilityProvider),
  ),
);
