import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/auth_state.dart';

class _AuthNotifier extends AsyncNotifier<AuthState> {
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
    final authRepository = ref.watch(authRepositoryProvider);
    final session = await authRepository.restorePersistedSession();

    if (session.mode != AuthSessionMode.jwt) {
      return AuthState.unauthenticated();
    }

    try {
      final data = await authRepository.getMe();
      return _stateFromUser(data);
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? 0;
      if (statusCode == 401 || statusCode == 403) {
        await authRepository.clearSession();
        return AuthState.unauthenticated();
      }

      final cached = await authRepository.getCachedUser();
      if (cached != null) {
        return _stateFromUser(cached);
      }

      return AuthState.unauthenticated();
    } catch (_) {
      final cached = await authRepository.getCachedUser();
      if (cached != null) {
        return _stateFromUser(cached);
      }

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
    );
  }

  Future<void> login({
    required String loginId,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final data = await ref.read(authRepositoryProvider).login(
            loginId: loginId,
            password: password,
          );
      return _stateFromUser(
          (data['user'] as Map<String, dynamic>?) ?? const {});
    });
  }

  Future<void> register({
    required String name,
    required String loginId,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final data = await ref.read(authRepositoryProvider).register(
            name: name,
            loginId: loginId,
            email: email,
            password: password,
          );
      return _stateFromUser(
          (data['user'] as Map<String, dynamic>?) ?? const {});
    });
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

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = AsyncData(AuthState.unauthenticated());
  }
}

final authBootstrapTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 8),
);

final authStateProvider =
    AsyncNotifierProvider<_AuthNotifier, AuthState>(_AuthNotifier.new);

final authStateNotifierProvider = authStateProvider;
