import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/observability/app_observability.dart';
import '../../../core/storage/local_storage.dart';
import '../../../shared/application/account_scoped_preferences.dart';

import '../../../shared/application/account_local_state_resetter.dart';

const _userCacheKey = 'auth_user_cache';
const _sessionModeCacheKey = 'auth_session_mode';
const _sessionRememberCacheKey = 'auth_session_remember';

class BiometricRefreshSessionExpired implements Exception {
  const BiometricRefreshSessionExpired();

  @override
  String toString() =>
      'Sua sessao por digital expirou. Entre com sua senha novamente.';
}

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

class LoginIdAvailabilityResult {
  const LoginIdAvailabilityResult({
    required this.loginId,
    required this.available,
    required this.isCurrent,
  });

  final String loginId;
  final bool available;
  final bool isCurrent;
}

class AuthRepository {
  AuthRepository(
    this._client, {
    LocalStorage? storage,
    AppObservability? observability,
    AccountLocalStateResetter? accountStateResetter,
    Duration authTimeout = const Duration(seconds: 15),
  })  : _storage = storage ?? LocalStorage.instance,
        _observability = observability ?? AppObservability.instance,
        _accountStateResetter =
            accountStateResetter ?? AccountLocalStateResetter(),
        _authTimeout = authTimeout;

  final ApiClient _client;
  final LocalStorage _storage;
  final AppObservability _observability;
  final AccountLocalStateResetter _accountStateResetter;
  final Duration _authTimeout;

  Future<Map<String, dynamic>> login({
    required String loginId,
    required String password,
    bool rememberSession = true,
  }) async {
    final normalizedLoginId = loginId.trim().toLowerCase();

    await _storage.setCacheValue(
      _sessionRememberCacheKey,
      rememberSession ? 'true' : 'false',
      scoped: false,
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
      ).timeout(
        _authTimeout,
        onTimeout: () => throw buildRemoteServiceException(
          DioException(
            requestOptions: RequestOptions(path: ApiEndpoints.login),
            type: DioExceptionType.connectionTimeout,
          ),
          fallback:
              'Nao foi possivel concluir o login agora. Tente novamente em instantes.',
          connectivityFallback:
              'Nao foi possivel conectar ao servidor a tempo.',
        ),
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('resposta inesperada de /auth/login');
      }
      final normalized = _normalizeAuthResponse(raw);
      await _persistJwtSession(normalized);
      _observability.trackEvent('auth.login_succeeded');
      return normalized;
    } on DioException catch (error, stackTrace) {
      _observability.reportError(
        'auth.login_failed',
        error,
        stackTrace,
      );
      throw buildRemoteServiceException(
        error,
        fallback:
            'Nao foi possivel concluir o login agora. Tente novamente em instantes.',
        connectivityFallback: 'Nao foi possivel conectar ao servidor a tempo.',
        exposeAuthenticationDetail: true,
      );
    } catch (error, stackTrace) {
      _observability.reportError(
        'auth.login_failed',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> loginWithRefreshToken(
    String refreshToken,
  ) async {
    final token = refreshToken.trim();
    if (token.isEmpty) {
      throw const FormatException('Token de renovacao ausente');
    }
    try {
      final response = await _client.dio
          .post(
            ApiEndpoints.refreshToken,
            options: Options(
              headers: {'Authorization': 'Bearer $token'},
              extra: {'skipAuth': true},
            ),
          )
          .timeout(_authTimeout);
      final raw = response.data;
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('resposta inesperada de /auth/refresh');
      }
      final accessToken = raw['access_token']?.toString().trim() ?? '';
      if (accessToken.isEmpty) {
        throw const FormatException('resposta de auth sem access_token valido');
      }
      final nextRefreshToken = raw['refresh_token']?.toString().trim() ?? token;
      await _client.saveTokens(
        accessToken: accessToken,
        refreshToken: nextRefreshToken,
      );
      await _writeSessionMode(AuthSessionMode.jwt);
      final user = await getMe();
      return {
        'access_token': accessToken,
        'refresh_token': nextRefreshToken,
        'user': user,
      };
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        throw const BiometricRefreshSessionExpired();
      }
      throw buildRemoteServiceException(
        error,
        fallback:
            'Sua sessao por digital expirou. Entre com sua senha novamente.',
        connectivityFallback:
            'Nao foi possivel conectar ao servidor para entrar com a digital.',
      );
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

      // Cache só mantém uso offline; 401/403 sempre encerram a confiança.
      final cachedFallback = isOffline ? await getCachedUser() : null;
      if (cachedFallback != null) {
        _observability.trackEvent(
          'auth.me_cache_fallback',
          level: AppEventLevel.warning,
        );
        return cachedFallback;
      }

      rethrow;
    } catch (e) {
      _debugLog('[AuthRepository.getMe] falhou: $e');
      rethrow;
    }
  }

  Future<PersistedAuthSession> restorePersistedSession() async {
    final rawMode =
        await _storage.getCacheValue(_sessionModeCacheKey, scoped: false);
    final mode = _parseSessionMode(rawMode);
    final rememberSession =
        await _storage.getCacheValue(_sessionRememberCacheKey, scoped: false);
    if (rememberSession == 'false') {
      await clearSession();
      return const PersistedAuthSession.none();
    }
    final cachedUser = await getCachedUser();
    final token = await _client.getAccessToken();

    if (cachedUser != null) {
      final userId = cachedUser['id']?.toString() ??
          cachedUser['user_id']?.toString() ??
          cachedUser['login_id']?.toString();
      if (userId != null && userId.isNotEmpty) {
        AccountScopedPreferences.instance.setActiveAccountId(userId);
        _storage.setActiveAccountId(userId);
      }
    }

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
    return _decodeCachedUser(
        await _storage.getCacheValue(_userCacheKey, scoped: false));
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

  Future<LoginIdAvailabilityResult> checkLoginIdAvailability({
    required String loginId,
  }) async {
    try {
      final response = await _client.dio.get(
        ApiEndpoints.userLoginIdAvailability,
        queryParameters: {
          'login_id': loginId.trim(),
        },
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) {
        throw const FormatException(
          'resposta inesperada de /user/login-id/availability',
        );
      }
      return LoginIdAvailabilityResult(
        loginId: raw['login_id']?.toString() ?? loginId.trim(),
        available: raw['available'] as bool? ?? false,
        isCurrent: raw['is_current'] as bool? ?? false,
      );
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel verificar esse ID agora.',
        connectivityFallback:
            'Nao foi possivel conectar ao servidor para verificar esse ID.',
      );
    }
  }

  Future<Map<String, dynamic>> updateLoginId({
    required String loginId,
    required String currentPassword,
  }) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.userUpdateLoginId,
        data: {
          'login_id': loginId.trim(),
          'current_password': currentPassword,
        },
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) {
        throw const FormatException(
          'resposta inesperada de /user/profile/login-id',
        );
      }
      final cached = await getCachedUser();
      if (cached != null) {
        final updated = Map<String, dynamic>.from(cached);
        updated['login_id'] = raw['login_id'] ?? loginId.trim();
        await _cacheUser(updated);
      }
      return raw;
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel atualizar o ID da conta agora.',
        connectivityFallback:
            'Nao foi possivel conectar ao servidor para atualizar o ID.',
      );
    }
  }

  Future<void> deleteAccount({
    required String currentPassword,
    required String confirmationText,
  }) async {
    try {
      await _client.dio.delete(
        ApiEndpoints.userDeleteAccount,
        data: {
          'current_password': currentPassword,
          'confirmation_text': confirmationText.trim(),
        },
      );
      await _accountStateResetter.clearAccountState();
      await clearSession();
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel excluir sua conta agora.',
        connectivityFallback:
            'Nao foi possivel conectar ao servidor para excluir sua conta.',
      );
    }
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
      _storage.deleteCacheValue(_userCacheKey, scoped: false),
      _storage.deleteCacheValue('auth_user', scoped: false),
      _storage.deleteCacheValue(_sessionModeCacheKey, scoped: false),
    ]);
  }

  Future<String?> getRefreshToken() => _client.getRefreshToken();

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
    final newUserId = user['id']?.toString() ??
        user['user_id']?.toString() ??
        user['login_id']?.toString();

    if (newUserId != null && newUserId.isNotEmpty) {
      AccountScopedPreferences.instance.setActiveAccountId(newUserId);
      _storage.setActiveAccountId(newUserId);
    }
    await _storage.setCacheValue(_userCacheKey, jsonEncode(user),
        scoped: false);
    await _storage.setCacheValue('auth_user', jsonEncode(user), scoped: false);
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
    await _storage.setCacheValue(_sessionModeCacheKey, value, scoped: false);
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
    final loginId = (source['login_id'] as String? ?? '').trim();
    final rawRole = (source['role'] as String? ?? 'user').trim().toLowerCase();
    final isAdmin = rawRole == 'admin';
    final role = isAdmin ? 'admin' : rawRole;
    final isPremium = isAdmin ||
        source['is_premium'] == true ||
        source['premium_active'] == true ||
        source['plan_type'] == 'premium' ||
        source['plan_type'] == 'vip_plus';

    return {
      'id': source['id']?.toString() ?? source['user_id']?.toString() ?? '',
      'name': source['name'] as String? ?? 'Usuario',
      'login_id': loginId,
      'email':
          source['email'] as String? ?? source['email_id'] as String? ?? '',
      'avatar_url': source['avatar_url'] as String?,
      'plan_type': isPremium
          ? 'premium'
          : (source['plan_type'] as String? ??
              source['plan_code'] as String? ??
              'free'),
      'premium_active': isPremium,
      'is_premium': isPremium,
      'xp': (source['xp'] as num?)?.toInt() ?? 0,
      'level': source['level'],
      'streak_days': (source['streak_days'] as num?)?.toInt() ?? 0,
      'role': role,
      'is_admin': isAdmin,
    };
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    observability: ref.watch(appObservabilityProvider),
  ),
);
