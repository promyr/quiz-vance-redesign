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
    // No boot (abertura do app), o app direciona para a Tela de Login por padrao,
    // permitindo ao usuario escolher se deseja continuar na conta salva ou trocar de conta.
    return AuthState.unauthenticated();
  }

  Future<void> confirmSavedSession() async {
    final nextState = await AsyncValue.guard(() async {
      final repository = ref.read(authRepositoryProvider);
      try {
        final session = await repository.restorePersistedSession();
        if (session.user != null) {
          // O papel efetivo deve vir do backend; o cache só é fallback offline.
          final meUser = await repository.getMe();
          return authStateFromUser(meUser);
        }

        if (session.mode == AuthSessionMode.jwt) {
          final meUser = await repository.getMe();
          return authStateFromUser(meUser);
        }

        return AuthState.unauthenticated();
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status == 401 || status == 403) {
          await repository.clearSession();
          return AuthState.unauthenticated();
        }
        final cachedUser = await repository.getCachedUser();
        return cachedUser == null
            ? AuthState.unauthenticated()
            : authStateFromUser(cachedUser);
      } catch (_) {
        final cachedUser = await repository.getCachedUser();
        if (cachedUser != null) return authStateFromUser(cachedUser);
        return AuthState.unauthenticated();
      }
    });
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
    // Remover um atalho existente e seguro antes da autenticacao quando o
    // usuario desmarca "Lembrar meu login". Essa operacao nao abre prompt e
    // tem limite de tempo para nunca bloquear o login indefinidamente.
    if (!rememberSession) {
      try {
        await ref
            .read(loginBiometricAuthCoordinatorProvider)
            .clear()
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // O cofre biometrico e opcional. Uma falha local nao impede o login.
      }
    }

    final nextState = await AsyncValue.guard(() async {
      final repository = ref.read(authRepositoryProvider);
      final loginData = rememberSession
          ? await repository.login(loginId: loginId, password: password)
          : await repository.login(
              loginId: loginId,
              password: password,
              rememberSession: false,
            );

      if (enrollBiometrics) {
        final refreshToken =
            loginData['refresh_token']?.toString().trim() ?? '';
        final user = (loginData['user'] as Map<String, dynamic>?) ?? const {};
        final effectiveLoginId =
            user['login_id']?.toString().trim() ?? loginId.trim();
        if (refreshToken.isNotEmpty) {
          try {
            final biometrics =
                ref.read(loginBiometricAuthCoordinatorProvider);
            if (await biometrics.canAuthenticate()) {
              await biometrics.enroll(
                refreshToken: refreshToken,
                loginId: effectiveLoginId,
              );
            }
          } catch (_) {
            // Falha ou cancelamento da leitura da digital nao impede o login com senha.
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

  Future<void> loginWithBiometrics({String? loginId}) async {
    final nextState = await AsyncValue.guard(() async {
      final biometrics = ref.read(loginBiometricAuthCoordinatorProvider);
      try {
        final session = await biometrics.unlock();
        final data = await ref
            .read(authRepositoryProvider)
            .loginWithRefreshToken(session.refreshToken);
        final refreshedToken = data['refresh_token']?.toString().trim() ?? '';
        final user = (data['user'] as Map<String, dynamic>?) ?? const {};
        final refreshedLoginId =
            user['login_id']?.toString().trim() ?? session.loginId;
        try {
          await biometrics.updateSession(
            refreshToken: refreshedToken,
            loginId: refreshedLoginId,
          );
        } on LoginBiometricException {
          // O servidor ja renovou a sessao. Desativa somente o atalho local
          // para nao desfazer um login valido por falha do cofre do aparelho.
          await biometrics.clear();
        }
        return authStateFromUser(user);
      } on BiometricRefreshSessionExpired {
        await biometrics.clear();
        rethrow;
      } on LoginBiometricCredentialInvalid {
        await biometrics.clear();
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
    _invalidateAccountProviders();
    state = AsyncData(AuthState.unauthenticated());
  }

  Future<void> logout({bool clearBiometrics = false}) async {
    await ref.read(authRepositoryProvider).logout();
    if (clearBiometrics) {
      await ref.read(loginBiometricAuthCoordinatorProvider).clear();
    }
    _invalidateAccountProviders();
    state = AsyncData(AuthState.unauthenticated());
  }
}

final authBootstrapTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 8),
);

final authStateProvider =
    AsyncNotifierProvider<_AuthNotifier, AuthState>(_AuthNotifier.new);

final authStateNotifierProvider = authStateProvider;
