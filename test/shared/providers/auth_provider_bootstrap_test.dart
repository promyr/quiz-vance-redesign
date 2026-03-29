import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';
import 'package:quiz_vance_flutter/shared/providers/auth_provider.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository authRepository;

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => authRepository),
      ],
    );
  }

  setUp(() {
    authRepository = _MockAuthRepository();
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

    final state = await container.read(authStateProvider.future);

    expect(state.isAuthenticated, isTrue);
    expect(state.userId, equals('user-1'));
    expect(state.name, equals('User Test'));
    verifyNever(() => authRepository.clearSession());
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

    final state = await container.read(authStateProvider.future);

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
