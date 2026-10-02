import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_state_mapper.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/application/login_biometric_auth_coordinator.dart';
import '../../features/auth/data/login_biometric_vault.dart';
import '../../features/auth/domain/auth_state.dart';

import 'account_session_epoch_provider.dart';

class _AuthNotifier extends AsyncNotifier<AuthState> {
  void _invalidateAccountProviders() => markAccountSessionChanged(ref);

  @override
  Future<AuthState> build() async {
    final timeout = ref.watch(authBootstrapTimeoutProvider);
    try {
      return await _restoreAuthState().timeout(timeout);
    } on TimeoutException {
      return AuthState.unauthenticated();
    }
  }

  Future<AuthState> _restoreAuthState() async {
    final repository = ref.read(authRepositoryProvider);
    try {
      final session = await repository.restorePersistedSession();
      if (session.mode != AuthSessionMode.jwt) {
        return AuthState.unauthenticated();
      }
      return authStateFromUser(await repository.getMe());
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        await repository.clearSession();
        await _clearBiometricsSafely();
        return AuthState.unauthenticated();
      }
      // A transient outage must not revoke an already persisted session.
      final cached = await repository.getCachedUser();
      if (cached != null) return authStateFromUser(cached);
      return AuthState.unauthenticated();
    } catch (_) {
      return AuthState.unauthenticated();
    }
  }

  Future<void> confirmSavedSession() async {
    if (state.isLoading) {
      await future;
      return;
    }
    final nextState = await AsyncValue.guard(_restoreAuthState);
    state = nextState;
    if (nextState.hasValue && nextState.value!.isAuthenticated) {
      _invalidateAccountProviders();
    }
  }

  Future<void> login({
    required String loginId,
    required String password,
    bool rememberSession = true,
    bool enrollBiometrics = false,
  }) async {
    final nextState = await AsyncValue.guard(() async {
      final repository = ref.read(authRepositoryProvider);
      final loginData = rememberSession
          ? await repository.login(loginId: loginId, password: password)
          : await repository.login(
              loginId: loginId,
              password: password,
              rememberSession: false,
            );

      // A nova sessao nunca herda o cofre de outra conta. Se o cadastro for
      // cancelado, a senha continua funcionando sem deixar um atalho antigo.
      await _clearBiometricsSafely();
      if (rememberSession && enrollBiometrics) {
        final refreshToken =
            loginData['refresh_token']?.toString().trim() ?? '';
        final user = (loginData['user'] as Map<String, dynamic>?) ?? const {};
        final effectiveLoginId =
            user['login_id']?.toString().trim() ?? loginId.trim();
        if (refreshToken.isNotEmpty) {
          try {
            final biometrics = ref.read(loginBiometricAuthCoordinatorProvider);
            if (await biometrics.canAuthenticate()) {
              await biometrics.enroll(
                refreshToken: refreshToken,
                loginId: effectiveLoginId,
              );
            }
          } catch (_) {
            await _clearBiometricsSafely();
          }
        }
      }

      return authStateFromUser(
        (loginData['user'] as Map<String, dynamic>?) ?? const {},
      );
    });

    state = nextState;
    if (nextState.hasValue && nextState.value!.isAuthenticated) {
      _invalidateAccountProviders();
    }
  }

  Future<void> loginWithBiometrics({required String loginId}) async {
    final nextState = await AsyncValue.guard(() async {
      final biometrics = ref.read(loginBiometricAuthCoordinatorProvider);
      try {
        final session = await biometrics.unlock();
        final expectedLoginId = loginId.trim().toLowerCase();
        if (expectedLoginId.isEmpty ||
            session.loginId.trim().toLowerCase() != expectedLoginId) {
          throw const LoginBiometricCredentialInvalid();
        }
        final data = await ref
            .read(authRepositoryProvider)
            .loginWithRefreshToken(session.refreshToken);
        final refreshedToken = data['refresh_token']?.toString().trim() ?? '';
        final user = (data['user'] as Map<String, dynamic>?) ?? const {};
        final refreshedLoginId =
            user['login_id']?.toString().trim() ?? session.loginId;
        if (refreshedLoginId.toLowerCase() != expectedLoginId) {
          await ref.read(authRepositoryProvider).clearSession();
          throw const LoginBiometricCredentialInvalid();
        }
        try {
          await biometrics.updateSession(
            refreshToken: refreshedToken,
            loginId: refreshedLoginId,
          );
        } on LoginBiometricException {
          // O servidor ja renovou a sessao. Desativa somente o atalho local
          // para nao desfazer um login valido por falha do cofre do aparelho.
          await _clearBiometricsSafely();
        }
        return authStateFromUser(user);
      } on BiometricRefreshSessionExpired {
        await _clearBiometricsSafely();
        rethrow;
      } on LoginBiometricCredentialInvalid {
        await _clearBiometricsSafely();
        rethrow;
      }
    });
    state = nextState;
    if (nextState.hasValue && nextState.value!.isAuthenticated) {
      _invalidateAccountProviders();
    }
  }

  Future<void> register({
    required String name,
    required String loginId,
    required String email,
    required String password,
  }) async {
    final nextState = await AsyncValue.guard(() async {
      final data = await ref.read(authRepositoryProvider).register(
            name: name,
            loginId: loginId,
            email: email,
            password: password,
          );
      return authStateFromUser(
          (data['user'] as Map<String, dynamic>?) ?? const {});
    });
    state = nextState;
    if (nextState.hasValue && nextState.value!.isAuthenticated) {
      _invalidateAccountProviders();
    }
  }

  Future<void> updateProfile({String? name, String? avatarUrl}) async {
    final current = state.valueOrNull;
    if (current == null || !current.isAuthenticated) return;
    final data = await ref.read(authRepositoryProvider).updateProfile(
          name: name,
          avatarUrl: avatarUrl,
        );
    state = AsyncData(current.copyWith(
      name: data.containsKey('name') ? data['name'] as String? : current.name,
      avatarUrl: data.containsKey('avatar_url')
          ? data['avatar_url'] as String?
          : current.avatarUrl,
    ));
  }

  Future<LoginIdAvailabilityResult> checkLoginIdAvailability(
    String loginId,
  ) {
    return ref.read(authRepositoryProvider).checkLoginIdAvailability(
          loginId: loginId,
        );
  }

  Future<void> updateLoginId({
    required String loginId,
    required String currentPassword,
  }) async {
    final current = state.valueOrNull;
    if (current == null || !current.isAuthenticated) return;
    final data = await ref.read(authRepositoryProvider).updateLoginId(
          loginId: loginId,
          currentPassword: currentPassword,
        );
    if (!data.containsKey('login_id')) {
      throw const FormatException('Resposta sem o novo ID da conta');
    }
    await ref.read(authRepositoryProvider).clearSession();
    await _clearBiometricsSafely();
    _invalidateAccountProviders();
    state = AsyncData(AuthState.unauthenticated());
  }

  Future<void> deleteAccount({
    required String currentPassword,
    required String confirmationText,
  }) async {
    await ref.read(authRepositoryProvider).deleteAccount(
          currentPassword: currentPassword,
          confirmationText: confirmationText,
        );
    await _clearBiometricsSafely();
    _invalidateAccountProviders();
    state = AsyncData(AuthState.unauthenticated());
  }

  Future<void> logout() async {
    try {
      await ref.read(authRepositoryProvider).logout();
    } finally {
      await _clearBiometricsSafely();
      _invalidateAccountProviders();
      state = AsyncData(AuthState.unauthenticated());
    }
  }

  Future<void> _clearBiometricsSafely() async {
    try {
      await ref.read(loginBiometricAuthCoordinatorProvider).clear();
    } catch (_) {
      // Falha local nao deve bloquear senha/logout. O desbloqueio ainda
      // verifica a identidade e o servidor verifica a validade da sessao.
    }
  }
}

final authBootstrapTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 8),
);

final authStateProvider =
    AsyncNotifierProvider<_AuthNotifier, AuthState>(_AuthNotifier.new);

final authStateNotifierProvider = authStateProvider;
