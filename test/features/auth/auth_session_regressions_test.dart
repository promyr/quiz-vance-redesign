import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/auth/application/login_biometric_auth_coordinator.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';
import 'package:quiz_vance_flutter/features/auth/data/login_biometric_vault.dart';
import 'package:quiz_vance_flutter/shared/providers/auth_provider.dart';

class _Repository extends Mock implements AuthRepository {}

class _Biometrics extends Mock implements LoginBiometricAuthCoordinator {}

void main() {
  late _Repository repository;
  late _Biometrics biometrics;
  late ProviderContainer container;
  const user = {'id': 'b', 'login_id': 'belchior', 'name': 'Belchior'};

  setUp(() {
    repository = _Repository();
    biometrics = _Biometrics();
    when(() => repository.restorePersistedSession())
        .thenAnswer((_) async => const PersistedAuthSession.none());
    when(() => repository.getCachedUser()).thenAnswer((_) async => null);
    when(() => repository.clearSession()).thenAnswer((_) async {});
    when(() => repository.logout()).thenAnswer((_) async {});
    when(() => biometrics.clear()).thenAnswer((_) async {});
    when(() => biometrics.canAuthenticate()).thenAnswer((_) async => true);
    when(() => biometrics.enroll(
          refreshToken: any(named: 'refreshToken'),
          loginId: any(named: 'loginId'),
        )).thenAnswer((_) async {});
    when(() => biometrics.updateSession(
          refreshToken: any(named: 'refreshToken'),
          loginId: any(named: 'loginId'),
        )).thenAnswer((_) async {});
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      loginBiometricAuthCoordinatorProvider.overrideWithValue(biometrics),
    ]);
  });
  tearDown(() => container.dispose());

  test('non-remembered password login cannot enroll a refresh credential',
      () async {
    when(() => repository.login(
            loginId: 'belchior', password: 'password', rememberSession: false))
        .thenAnswer(
            (_) async => {'user': user, 'refresh_token': 'new-refresh'});
    await container.read(authStateProvider.future);
    await container.read(authStateProvider.notifier).login(
          loginId: 'belchior',
          password: 'password',
          rememberSession: false,
          enrollBiometrics: true,
        );
    expect(container.read(authStateProvider).value?.isAuthenticated, isTrue);
    verifyNever(() => biometrics.enroll(
          refreshToken: any(named: 'refreshToken'),
          loginId: any(named: 'loginId'),
        ));
    verify(() => biometrics.clear()).called(1);
  });

  test('biometric unlock rejects a vault owned by a different account',
      () async {
    when(() => biometrics.unlock()).thenAnswer((_) async =>
        const LoginBiometricSession(
            refreshToken: 'a-refresh', loginId: 'alice'));
    when(() => repository.loginWithRefreshToken('a-refresh'))
        .thenAnswer((_) async => {
              'user': {'id': 'a', 'login_id': 'alice'},
              'refresh_token': 'a-next',
            });
    await container.read(authStateProvider.future);
    await container
        .read(authStateProvider.notifier)
        .loginWithBiometrics(loginId: 'belchior');
    expect(container.read(authStateProvider).hasError, isTrue);
    verifyNever(() => repository.loginWithRefreshToken(any()));
    verify(() => biometrics.clear()).called(1);
  });

  test('valid remembered session resumes automatically on cold start',
      () async {
    when(() => repository.restorePersistedSession()).thenAnswer((_) async =>
        const PersistedAuthSession(mode: AuthSessionMode.jwt, user: user));
    when(() => repository.getMe()).thenAnswer((_) async => user);
    final state = await container.read(authStateProvider.future);
    expect(state.isAuthenticated, isTrue);
    expect(state.loginId, 'belchior');
    verify(() => repository.getMe()).called(1);
  });

  test('real logout clears the revoked biometric shortcut', () async {
    await container.read(authStateProvider.future);
    await container.read(authStateProvider.notifier).logout();
    verify(() => biometrics.clear()).called(1);
    expect(container.read(authStateProvider).value?.isAuthenticated, isFalse);
  });

  test('cancelled enrollment for account B removes account A vault', () async {
    when(() => repository.login(loginId: 'belchior', password: 'password'))
        .thenAnswer(
            (_) async => {'user': user, 'refresh_token': 'new-refresh'});
    when(() =>
            biometrics.enroll(refreshToken: 'new-refresh', loginId: 'belchior'))
        .thenThrow(const LoginBiometricCancelled());
    await container.read(authStateProvider.future);
    await container.read(authStateProvider.notifier).login(
          loginId: 'belchior',
          password: 'password',
          enrollBiometrics: true,
        );
    expect(container.read(authStateProvider).value?.loginId, 'belchior');
    verify(() => biometrics.clear()).called(greaterThanOrEqualTo(1));
  });
}
