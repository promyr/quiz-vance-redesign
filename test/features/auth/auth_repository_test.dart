import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';
import 'package:quiz_vance_flutter/shared/application/account_local_state_resetter.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

class _MockLocalStorage extends Mock implements LocalStorage {}

class _MockAccountLocalStateResetter extends Mock
    implements AccountLocalStateResetter {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;
  late _MockLocalStorage storage;
  late _MockAccountLocalStateResetter accountStateResetter;
  late AuthRepository repository;

  setUp(() {
    apiClient = _MockApiClient();
    dio = _MockDio();
    storage = _MockLocalStorage();
    accountStateResetter = _MockAccountLocalStateResetter();
    AccountScopedPreferences.instance.setActiveAccountId(null);
    repository = AuthRepository(
      apiClient,
      storage: storage,
      accountStateResetter: accountStateResetter,
    );

    when(
      () => storage.setCacheValue(
        any(),
        any(),
        scoped: any(named: 'scoped'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => storage.deleteCacheValue(
        any(),
        scoped: any(named: 'scoped'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => storage.getCacheValue(
        any(),
        scoped: any(named: 'scoped'),
      ),
    ).thenAnswer((_) async => null);
    when(() => storage.setActiveAccountId(any())).thenReturn(null);
    when(() => apiClient.clearTokens()).thenAnswer((_) async {});
    when(() => apiClient.dio).thenReturn(dio);
    when(() => accountStateResetter.clearAccountState())
        .thenAnswer((_) async {});
  });

  test('restorePersistedSession descarta sessao jwt sem token', () async {
    when(
      () => storage.getCacheValue(
        any(),
        scoped: any(named: 'scoped'),
      ),
    ).thenAnswer((invocation) async {
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
    verify(() => storage.deleteCacheValue('auth_user_cache', scoped: false)).called(1);
    verify(() => storage.deleteCacheValue('auth_session_mode', scoped: false)).called(1);
  });

  test('getCachedUser retorna usuario salvo na chave atual', () async {
    when(
      () => storage.getCacheValue(
        any(),
        scoped: any(named: 'scoped'),
      ),
    ).thenAnswer((invocation) async {
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
    verifyNever(
      () => storage.setCacheValue(
        any(),
        any(),
        scoped: any(named: 'scoped'),
      ),
    );
  });

  test('restorePersistedSession promove token valido para modo jwt', () async {
    when(
      () => storage.getCacheValue(
        any(),
        scoped: any(named: 'scoped'),
      ),
    ).thenAnswer((invocation) async {
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
    verify(
      () => storage.setCacheValue(
        'auth_session_mode',
        'jwt',
        scoped: false,
      ),
    ).called(1);
    verifyNever(() => apiClient.clearTokens());
  });

  test('restorePersistedSession descarta token quando login nao foi lembrado',
      () async {
    when(
      () => storage.getCacheValue(
        any(),
        scoped: any(named: 'scoped'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.positionalArguments.first as String;
      if (key == 'auth_session_mode') return 'none';
      return null;
    });
    when(() => apiClient.getAccessToken())
        .thenAnswer((_) async => null);

    final session = await repository.restorePersistedSession();

    expect(session.mode, AuthSessionMode.none);
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

  test('login traduz erro remoto do backend para mensagem amigavel', () async {
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        response: Response<Map<String, dynamic>>(
          requestOptions: RequestOptions(path: '/auth/login'),
          statusCode: 426,
          data: {
            'detail': 'Atualize o aplicativo para continuar.',
          },
        ),
      ),
    );

    await expectLater(
      repository.login(loginId: 'belchior', password: '123456'),
      throwsA(
        isA<RemoteServiceException>().having(
          (error) => error.message,
          'message',
          'Atualize o aplicativo para continuar.',
        ),
      ),
    );
  });

  test('login encerra tentativa travada com timeout amigavel', () async {
    repository = AuthRepository(
      apiClient,
      storage: storage,
      accountStateResetter: accountStateResetter,
      authTimeout: const Duration(milliseconds: 1),
    );

    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) => Completer<Response<Map<String, dynamic>>>().future);

    await expectLater(
      repository.login(loginId: 'belchior', password: '123456'),
      throwsA(
        isA<RemoteServiceException>().having(
          (error) => error.message,
          'message',
          'Nao foi possivel conectar ao servidor a tempo.',
        ),
      ),
    );
  });

  test('checkLoginIdAvailability retorna disponibilidade normalizada',
      () async {
    when(
      () => dio.get(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/user/login-id/availability'),
        data: {
          'login_id': 'belchior.vance',
          'available': true,
          'is_current': false,
        },
      ),
    );

    final result = await repository.checkLoginIdAvailability(
      loginId: 'Belchior.Vance',
    );

    expect(result.loginId, equals('belchior.vance'));
    expect(result.available, isTrue);
    expect(result.isCurrent, isFalse);
  });

  test('updateLoginId persiste novo login_id no cache local', () async {
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/user/profile/login-id'),
        data: {
          'ok': true,
          'login_id': 'novo.id',
        },
      ),
    );
    when(() => storage.getCacheValue('auth_user_cache', scoped: true))
        .thenAnswer((_) async => jsonEncode({
              'id': 'user-1',
              'name': 'Belchior',
              'login_id': 'belchior',
            }));
    when(() => storage.getCacheValue('auth_user_cache', scoped: false))
        .thenAnswer((_) async => jsonEncode({
              'id': 'user-1',
              'name': 'Belchior',
              'login_id': 'belchior',
            }));
    when(() => storage.getCacheValue('auth_user_cache'))
        .thenAnswer((_) async => jsonEncode({
              'id': 'user-1',
              'name': 'Belchior',
              'login_id': 'belchior',
            }));

    final result = await repository.updateLoginId(loginId: 'novo.id');

    expect(result['login_id'], equals('novo.id'));
    final captured = verify(
      () => storage.setCacheValue(
        'auth_user_cache',
        captureAny(),
        scoped: any(named: 'scoped'),
      ),
    ).captured.single as String;
    expect(captured, contains('"login_id":"novo.id"'));
  });

  test('deleteAccount limpa estado local da conta apos sucesso remoto',
      () async {
    when(
      () => dio.delete(
        any(),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/user/account'),
        data: {'ok': true},
      ),
    );

    await repository.deleteAccount(
      currentPassword: '123456',
      confirmationText: 'EXCLUIR',
    );

    verify(() => accountStateResetter.clearAccountState()).called(1);
    verify(() => apiClient.clearTokens()).called(1);
    verify(() => storage.deleteCacheValue('auth_user_cache', scoped: any(named: 'scoped')))
        .called(1);
    verify(() => storage.deleteCacheValue('auth_session_mode', scoped: any(named: 'scoped')))
        .called(1);
  });

  test('logout encerra sessao sem purgar cache local da conta', () async {
    when(
      () => storage.getCacheValue(
        any(),
        scoped: any(named: 'scoped'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.positionalArguments.first as String;
      if (key == 'auth_session_mode') {
        return 'jwt';
      }
      return null;
    });
    when(() => apiClient.getAccessToken()).thenAnswer((_) async => 'jwt-token');
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/auth/logout'),
        data: {'ok': true},
      ),
    );

    await repository.logout();

    verify(() => apiClient.clearTokens()).called(1);
    verifyNever(() => accountStateResetter.clearAccountState());
  });

  test('login com outro usuario troca escopo sem purgar cache de outras contas',
      () async {
    when(
      () => apiClient.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        requestOptions: RequestOptions(path: '/auth/login'),
        data: {
          'access_token': 'novo-token',
          'refresh_token': 'novo-refresh',
          'user': {
            'id': 'user-novo',
            'name': 'Conta Nova',
            'login_id': 'conta.nova',
            'email': 'nova@quizvance.app',
          },
        },
      ),
    );

    await repository.login(loginId: 'conta.nova', password: '123456');

    verifyNever(() => accountStateResetter.clearAccountState());
    expect(AccountScopedPreferences.instance.activeAccountId, equals('user-novo'));
    verify(
      () => apiClient.saveTokens(
        accessToken: 'novo-token',
        refreshToken: 'novo-refresh',
      ),
    ).called(1);
  });
}
