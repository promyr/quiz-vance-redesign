import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';
import 'package:quiz_vance_flutter/features/auth/application/login_biometric_auth_coordinator.dart';
import 'package:quiz_vance_flutter/features/auth/data/login_biometric_vault.dart';
import 'package:quiz_vance_flutter/features/auth/domain/auth_state.dart';
import 'package:quiz_vance_flutter/app/router.dart';
import 'package:quiz_vance_flutter/shared/providers/auth_provider.dart';
import 'package:quiz_vance_flutter/shared/providers/gamification_provider.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockLoginBiometricCoordinator extends Mock
    implements LoginBiometricAuthCoordinator {}

class _FakeUserStatsNotifier extends UserStatsNotifier {
  @override
  Future<UserStats> build() async => const UserStats();
}

class _FakeGamificationNotifier extends GamificationNotifier {
  @override
  Future<GamificationState> build() async => const GamificationState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  late _MockAuthRepository authRepository;
  late _MockLoginBiometricCoordinator biometricCoordinator;

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => authRepository),
        loginBiometricAuthCoordinatorProvider
            .overrideWith((ref) => biometricCoordinator),
        userStatsNotifierProvider.overrideWith(_FakeUserStatsNotifier.new),
        userStatsProvider.overrideWith((ref) async => <String, dynamic>{}),
        gamificationProvider.overrideWith(_FakeGamificationNotifier.new),
        onboardingGateProvider.overrideWith((ref) async => false),
      ],
    );
  }

  setUp(() {
    authRepository = _MockAuthRepository();
    biometricCoordinator = _MockLoginBiometricCoordinator();
    when(() => biometricCoordinator.canUnlock()).thenAnswer((_) async => false);
    when(() => biometricCoordinator.clear()).thenAnswer((_) async {});
    when(
      () => biometricCoordinator.enroll(
        refreshToken: any(named: 'refreshToken'),
        loginId: any(named: 'loginId'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => biometricCoordinator.updateSession(
        refreshToken: any(named: 'refreshToken'),
        loginId: any(named: 'loginId'),
      ),
    ).thenAnswer((_) async {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test('mantem sessao com usuario em cache quando getMe falha temporariamente',
      () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession(mode: AuthSessionMode.jwt),
    );
    when(() => authRepository.getMe()).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/auth/me'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/me'),
          statusCode: 500,
        ),
      ),
    );
    when(() => authRepository.getCachedUser()).thenAnswer(
      (_) async => {
        'id': 'user-1',
        'login_id': 'user.login',
        'email': 'user@test.com',
        'name': 'User Test',
      },
    );

    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(authStateProvider.notifier).confirmSavedSession();
    final state = container.read(authStateProvider).value!;

    expect(state.isAuthenticated, isTrue);
    expect(state.userId, equals('user-1'));
    expect(state.name, equals('User Test'));
    verifyNever(() => authRepository.clearSession());
  });

  test('atualiza papel administrativo no bootstrap mesmo com usuario em cache',
      () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession(
        mode: AuthSessionMode.jwt,
        user: {
          'id': 'user-1',
          'login_id': 'promyr',
          'name': 'Belchior',
          'role': 'user',
        },
      ),
    );
    when(() => authRepository.getMe()).thenAnswer(
      (_) async => {
        'id': 'user-1',
        'login_id': 'promyr',
        'name': 'Belchior',
        'role': 'admin',
      },
    );

    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(authStateProvider.notifier).confirmSavedSession();
    final state = container.read(authStateProvider).value!;

    expect(state.isAdmin, isTrue);
    verify(() => authRepository.getMe()).called(1);
  });

  test('limpa sessao apenas em 401/403 real', () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession(mode: AuthSessionMode.jwt),
    );
    when(() => authRepository.clearSession()).thenAnswer((_) async {});
    when(() => authRepository.getMe()).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/auth/me'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/me'),
          statusCode: 401,
        ),
      ),
    );

    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(authStateProvider.notifier).confirmSavedSession();
    final state = container.read(authStateProvider).value!;

    expect(state.isAuthenticated, isFalse);
    expect(state.userId, isNull);
    verify(() => authRepository.clearSession()).called(1);
  });

  test(
      'retorna desautenticado quando nao ha cache e getMe falha com erro inesperado',
      () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession(mode: AuthSessionMode.jwt),
    );
    when(() => authRepository.getMe())
        .thenThrow(const FormatException('payload invalido'));
    when(() => authRepository.getCachedUser()).thenAnswer((_) async => null);

    final container = makeContainer();
    addTearDown(container.dispose);

    final state = await container.read(authStateProvider.future);

    expect(state.isAuthenticated, isFalse);
    verifyNever(() => authRepository.clearSession());
  });

  test(
      'retorna desautenticado quando getMe falha offline e nao existe cache local',
      () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession(mode: AuthSessionMode.jwt),
    );
    when(() => authRepository.getMe()).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/auth/me'),
        type: DioExceptionType.connectionError,
      ),
    );
    when(() => authRepository.getCachedUser()).thenAnswer((_) async => null);

    final container = makeContainer();
    addTearDown(container.dispose);

    final state = await container.read(authStateProvider.future);

    expect(state.isAuthenticated, isFalse);
    expect(state.userId, isNull);
    expect(state.loginId, isNull);
    verifyNever(() => authRepository.clearSession());
  });

  test('bootstrap ignora sessao inexistente', () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession.none(),
    );

    final container = makeContainer();
    addTearDown(container.dispose);

    final state = await container.read(authStateProvider.future);

    expect(state.isAuthenticated, isFalse);
    expect(state.userId, isNull);
    verifyNever(() => authRepository.getMe());
    verifyNever(() => authRepository.clearSession());
  });

  test('login atualiza o estado sem reativar loading global', () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession.none(),
    );
    when(
      () => authRepository.login(
        loginId: any(named: 'loginId'),
        password: any(named: 'password'),
      ),
    ).thenAnswer(
      (_) async => {
        'user': {
          'id': 'user-99',
          'login_id': 'belchior',
          'email': 'belchior@test.com',
          'name': 'Belchior',
        },
        'refresh_token': 'refresh-token',
      },
    );

    final container = makeContainer();
    addTearDown(container.dispose);

    final initialState = await container.read(authStateProvider.future);
    expect(initialState.isAuthenticated, isFalse);

    final observed = <AsyncValue<AuthState>>[];
    final subscription = container.listen<AsyncValue<AuthState>>(
      authStateProvider,
      (_, next) => observed.add(next),
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(authStateProvider.notifier).login(
          loginId: 'belchior',
          password: '123456',
        );

    final finalState = container.read(authStateProvider).valueOrNull;
    expect(finalState?.isAuthenticated, isTrue);
    expect(finalState?.loginId, equals('belchior'));
    expect(observed.where((state) => state.isLoading), isEmpty);
    verifyNever(() => biometricCoordinator.canUnlock());
    verifyNever(
      () => biometricCoordinator.enroll(
        refreshToken: any(named: 'refreshToken'),
        loginId: any(named: 'loginId'),
      ),
    );
  });

  test('login por senha conclui sem iniciar cadastro biometrico', () async {
    when(
      () => authRepository.login(
        loginId: any(named: 'loginId'),
        password: any(named: 'password'),
      ),
    ).thenAnswer(
      (_) async => {
        'refresh_token': 'refresh-token',
        'user': {
          'id': 'user-99',
          'login_id': 'belchior',
          'name': 'Belchior',
          'role': 'admin',
        },
      },
    );
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    await container
        .read(authStateProvider.notifier)
        .login(loginId: 'belchior', password: '123456')
        .timeout(const Duration(seconds: 1));

    final authenticatedState = container.read(authStateProvider).valueOrNull;
    expect(authenticatedState?.isAuthenticated, isTrue);
    expect(authenticatedState?.loginId, 'belchior');
    verifyNever(() => biometricCoordinator.canUnlock());
    verifyNever(
      () => biometricCoordinator.enroll(
        refreshToken: any(named: 'refreshToken'),
        loginId: any(named: 'loginId'),
      ),
    );
  });

  test('login por senha nao reabre biometria quando cofre ja existe', () async {
    when(() => biometricCoordinator.canUnlock()).thenAnswer((_) async => true);
    when(
      () => authRepository.login(
        loginId: any(named: 'loginId'),
        password: any(named: 'password'),
      ),
    ).thenAnswer(
      (_) async => {
        'refresh_token': 'refresh-token',
        'user': {
          'id': 'user-99',
          'login_id': 'belchior',
          'name': 'Belchior',
          'role': 'admin',
        },
      },
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    await container.read(authStateProvider.notifier).login(
          loginId: 'belchior',
          password: '123456',
        );

    expect(
        container.read(authStateProvider).valueOrNull?.isAuthenticated, isTrue);
    verifyNever(() => biometricCoordinator.canUnlock());
    verifyNever(
      () => biometricCoordinator.enroll(
        refreshToken: any(named: 'refreshToken'),
        loginId: any(named: 'loginId'),
      ),
    );
  });

  test('login por senha nao abre prompt biometrico durante troca para Home',
      () async {
    when(() => biometricCoordinator.canUnlock()).thenAnswer((_) async => false);
    when(
      () => authRepository.login(
        loginId: any(named: 'loginId'),
        password: any(named: 'password'),
      ),
    ).thenAnswer(
      (_) async => {
        'refresh_token': 'refresh-token',
        'user': {
          'id': 'user-99',
          'login_id': 'belchior',
          'name': 'Belchior',
          'role': 'admin',
        },
      },
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);

    await container.read(authStateProvider.notifier).login(
          loginId: 'belchior',
          password: '123456',
        );

    expect(
        container.read(authStateProvider).valueOrNull?.isAuthenticated, isTrue);
    verifyNever(
      () => biometricCoordinator.enroll(
        refreshToken: any(named: 'refreshToken'),
        loginId: any(named: 'loginId'),
      ),
    );
  });

  test('transicao de autenticacao preserva a instancia do roteador', () async {
    when(
      () => authRepository.login(
        loginId: any(named: 'loginId'),
        password: any(named: 'password'),
      ),
    ).thenAnswer(
      (_) async => {
        'refresh_token': 'refresh-token',
        'user': {
          'id': 'user-99',
          'login_id': 'belchior',
          'name': 'Belchior',
          'role': 'admin',
        },
      },
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(authStateProvider.future);
    final routerBeforeLogin = container.read(routerProvider);

    await container.read(authStateProvider.notifier).login(
          loginId: 'belchior',
          password: '123456',
        );
    final routerAfterLogin = container.read(routerProvider);

    expect(identical(routerBeforeLogin, routerAfterLogin), isTrue);
  });

  test('login por digital renova a sessao sem solicitar senha', () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession.none(),
    );
    when(() => biometricCoordinator.unlock()).thenAnswer(
      (_) async => const LoginBiometricSession(
        refreshToken: 'protected-refresh',
        loginId: 'promyr',
      ),
    );
    when(() => authRepository.loginWithRefreshToken('protected-refresh'))
        .thenAnswer(
      (_) async => {
        'refresh_token': 'renewed-refresh',
        'user': {
          'id': '7',
          'login_id': 'promyr',
          'name': 'Belchior',
          'role': 'admin',
        },
      },
    );

    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(authStateProvider.notifier)
        .loginWithBiometrics(loginId: 'promyr');

    final state = container.read(authStateProvider).valueOrNull;
    expect(state?.isAuthenticated, isTrue);
    expect(state?.isAdmin, isTrue);
    verify(
      () => biometricCoordinator.updateSession(
        refreshToken: 'renewed-refresh',
        loginId: 'promyr',
      ),
    ).called(1);
    verifyNever(
      () => biometricCoordinator.enroll(
        refreshToken: any(named: 'refreshToken'),
        loginId: any(named: 'loginId'),
      ),
    );
    verifyNever(
      () => authRepository.login(
        loginId: any(named: 'loginId'),
        password: any(named: 'password'),
      ),
    );
  });

  test('login por digital indisponivel nao tenta cadastrar durante o unlock',
      () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession.none(),
    );
    when(() => biometricCoordinator.unlock()).thenThrow(
      const LoginBiometricUnavailable(),
    );

    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(authStateProvider.notifier).loginWithBiometrics(
          loginId: 'promyr',
        );

    expect(container.read(authStateProvider).hasError, isTrue);
    verifyNever(
      () => biometricCoordinator.enroll(
        refreshToken: any(named: 'refreshToken'),
        loginId: any(named: 'loginId'),
      ),
    );
    verifyNever(
      () => authRepository.loginWithRefreshToken(any()),
    );
  });

  test('sessao biometrica expirada limpa apenas o cofre biometrico', () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession.none(),
    );
    when(() => biometricCoordinator.unlock()).thenAnswer(
      (_) async => const LoginBiometricSession(
        refreshToken: 'expired-refresh',
        loginId: 'promyr',
      ),
    );
    when(() => authRepository.loginWithRefreshToken('expired-refresh'))
        .thenThrow(const BiometricRefreshSessionExpired());

    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(authStateProvider.notifier)
        .loginWithBiometrics(loginId: 'promyr');

    expect(container.read(authStateProvider).hasError, isTrue);
    verify(() => biometricCoordinator.clear()).called(1);
    verifyNever(() => authRepository.clearSession());
  });

  test('cofre biometrico invalido e limpo sem apagar a conta lembrada',
      () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession.none(),
    );
    when(() => biometricCoordinator.unlock()).thenThrow(
      const LoginBiometricCredentialInvalid(),
    );

    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(authStateProvider.notifier)
        .loginWithBiometrics(loginId: 'promyr');

    expect(container.read(authStateProvider).hasError, isTrue);
    verify(() => biometricCoordinator.clear()).called(1);
    verifyNever(() => authRepository.clearSession());
    verifyNever(
      () => authRepository.loginWithRefreshToken(any()),
    );
  });

  test('falha ao atualizar cofre nao desfaz login biometrico ja renovado',
      () async {
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession.none(),
    );
    when(() => biometricCoordinator.unlock()).thenAnswer(
      (_) async => const LoginBiometricSession(
        refreshToken: 'protected-refresh',
        loginId: 'promyr',
      ),
    );
    when(() => authRepository.loginWithRefreshToken('protected-refresh'))
        .thenAnswer(
      (_) async => {
        'refresh_token': 'renewed-refresh',
        'user': {
          'id': '7',
          'login_id': 'promyr',
          'name': 'Belchior',
          'role': 'admin',
        },
      },
    );
    when(
      () => biometricCoordinator.updateSession(
        refreshToken: 'renewed-refresh',
        loginId: 'promyr',
      ),
    ).thenThrow(const LoginBiometricCredentialInvalid());

    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(authStateProvider.notifier)
        .loginWithBiometrics(loginId: 'promyr');

    expect(
        container.read(authStateProvider).valueOrNull?.isAuthenticated, isTrue);
    verify(() => biometricCoordinator.clear()).called(1);
  });

  test('desiste do bootstrap preso apos timeout e segue desautenticado',
      () async {
    final completer = Completer<PersistedAuthSession>();
    when(() => authRepository.restorePersistedSession())
        .thenAnswer((_) => completer.future);

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => authRepository),
        authBootstrapTimeoutProvider.overrideWith((ref) {
          return const Duration(milliseconds: 10);
        }),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(authStateProvider.future);

    expect(state.isAuthenticated, isFalse);
    verifyNever(() => authRepository.getMe());
    verifyNever(() => authRepository.clearSession());
  });
}
