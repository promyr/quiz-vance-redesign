import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/observability/app_observability.dart';
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

class _MockLocalStorage extends Mock implements LocalStorage {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;
  late _MockLocalStorage storage;
  late AuthRepository repository;

  setUp(() {
    apiClient = _MockApiClient();
    dio = _MockDio();
    storage = _MockLocalStorage();
    repository = AuthRepository(apiClient, storage: storage);

    when(() => storage.setCacheValue(any(), any())).thenAnswer((_) async {});
    when(() => storage.deleteCacheValue(any())).thenAnswer((_) async => 1);
    when(() => apiClient.clearTokens()).thenAnswer((_) async {});
    when(() => apiClient.dio).thenReturn(dio);
  });

  test('restorePersistedSession descarta sessao jwt sem token', () async {
    when(() => storage.getCacheValue(any())).thenAnswer((invocation) async {
      final key = invocation.positionalArguments.first as String;
      if (key == 'auth_session_mode') {
        return 'jwt';
      }
      return null;
    });
    when(() => apiClient.getAccessToken()).thenAnswer((_) async => null);

    final session = await repository.restorePersistedSession();

    expect(session.mode, equals(AuthSessionMode.none));
    verify(() => apiClient.clearTokens()).called(1);
    verifyNever(() => storage.setCacheValue('auth_session_mode', 'jwt'));
  });

  test('getCachedUser retorna usuario salvo na chave atual', () async {
    when(() => storage.getCacheValue(any())).thenAnswer((invocation) async {
      final key = invocation.positionalArguments.first as String;
      if (key == 'auth_user_cache') {
        return jsonEncode({
          'id': 'user-1',
          'login_id': 'belchior',
          'email': 'belchior@quizvance.app',
          'name': 'Belchior',
        });
      }
      return null;
    });

    final user = await repository.getCachedUser();

    expect(user?['id'], equals('user-1'));
    verifyNever(() => storage.setCacheValue(any(), any()));
  });

  test('restorePersistedSession promove token valido para modo jwt', () async {
    when(() => storage.getCacheValue(any())).thenAnswer((invocation) async {
      final key = invocation.positionalArguments.first as String;
      if (key == 'auth_session_mode') {
        return 'none';
      }
      return null;
    });
    when(() => apiClient.getAccessToken())
        .thenAnswer((_) async => 'jwt-token-real');

    final session = await repository.restorePersistedSession();

    expect(session.mode, equals(AuthSessionMode.jwt));
    verify(() => storage.setCacheValue('auth_session_mode', 'jwt')).called(1);
    verifyNever(() => apiClient.clearTokens());
  });

  test('login falha quando backend nao retorna access_token valido', () async {
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/auth/login'),
        data: {
          'user_id': 7,
          'name': 'Belchior',
          'email_id': 'belchior@quizvance.app',
        },
      ),
    );

    await expectLater(
      repository.login(loginId: 'belchior', password: '123456'),
      throwsA(isA<FormatException>()),
    );
    verify(() => apiClient.clearTokens()).called(1);
    verifyNever(
      () => apiClient.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    );
  });

  test('login nao mantem credenciais na observabilidade ao falhar', () async {
    final observability = AppObservability();
    repository = AuthRepository(
      apiClient,
      storage: storage,
      observability: observability,
    );
    final requestOptions = RequestOptions(
      path: '/auth/login',
      data: const <String, Object?>{
        'login_id': 'belchior@example.com',
        'password': 'senha-supersecreta',
      },
      headers: const <String, Object?>{
        'Authorization': 'Bearer jwt-supersecreto',
      },
    );
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: requestOptions,
        message: 'password=senha-supersecreta token=jwt-supersecreto',
      ),
    );

    await expectLater(
      repository.login(
        loginId: 'belchior@example.com',
        password: 'senha-supersecreta',
      ),
      throwsA(isA<DioException>()),
    );

    final event = observability.recentEvents.last;
    final serialized = '${event.error} ${event.attributes}';
    expect(serialized, isNot(contains('senha-supersecreta')));
    expect(serialized, isNot(contains('jwt-supersecreto')));
    expect(event.error, equals('DioException'));
  });
}
