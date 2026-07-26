import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/auth_state.dart';

import 'gamification_provider.dart';
import 'user_provider.dart';

class _AuthNotifier extends AsyncNotifier<AuthState> {
  void _invalidateAccountProviders() {
    ref.invalidate(userStatsNotifierProvider);
    ref.invalidate(userStatsProvider);
    ref.invalidate(gamificationProvider);
  }

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
      if (session.user != null) {
        return _stateFromUser(session.user!);
      }

      if (session.mode == AuthSessionMode.jwt) {
        final meUser = await repository.getMe();
        return _stateFromUser(meUser);
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
          : _stateFromUser(cachedUser);
    } catch (_) {
      final cachedUser = await repository.getCachedUser();
      if (cachedUser != null) return _stateFromUser(cachedUser);
      return AuthState.unauthenticated();
    }
  }

  AuthState _stateFromUser(Map<String, dynamic> data) {
    return AuthState(
      isAuthenticated: true,
      userId: data['id']?.toString(),
      loginId: data['login_id'] as String?,
      email: data['email'] as String?,
      name: data['name'] as String?,
      avatarUrl: data['avatar_url'] as String?,
      role: data['role'] as String? ?? 'user',
    );
  }

  Future<void> login({
    required String loginId,
    required String password,
    bool rememberSession = true,
  }) async {
    final nextState = await AsyncValue.guard(() async {
      final repository = ref.read(authRepositoryProvider);
      final data = rememberSession
          ? await repository.login(loginId: loginId, password: password)
          : await repository.login(
              loginId: loginId,
              password: password,
              rememberSession: false,
            );
      return _stateFromUser(
          (data['user'] as Map<String, dynamic>?) ?? const {});
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
      return _stateFromUser(
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

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
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
