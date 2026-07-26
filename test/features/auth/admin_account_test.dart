import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

class _MockLocalStorage extends Mock implements LocalStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockApiClient apiClient;
  late _MockDio dio;
  late _MockLocalStorage storage;
  late AuthRepository authRepository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    apiClient = _MockApiClient();
    dio = _MockDio();
    storage = _MockLocalStorage();
    when(() => apiClient.dio).thenReturn(dio);
    when(() => apiClient.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        )).thenAnswer((_) async {});
    when(() =>
            storage.setCacheValue(any(), any(), scoped: any(named: 'scoped')))
        .thenAnswer((_) async {});
    authRepository = AuthRepository(
      apiClient,
      storage: storage,
    );
  });

  test('admin login fails closed when the backend rejects credentials',
      () async {
    when(
      () => dio.post(
        any(),
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/auth/login'),
          statusCode: 401,
          data: const {'detail': 'Credenciais invalidas'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      authRepository.login(
        loginId: 'admin',
        password: 'qualquer-senha',
      ),
      throwsA(isA<Exception>()),
    );

    verifyNever(
      () => apiClient.saveTokens(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    );
  });
}
