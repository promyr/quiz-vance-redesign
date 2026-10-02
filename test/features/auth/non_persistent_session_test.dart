import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';

class _LocalStorage extends Mock implements LocalStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unchecked remember keeps tokens only in the current client', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final storage = _LocalStorage();
    when(() =>
            storage.setCacheValue(any(), any(), scoped: any(named: 'scoped')))
        .thenAnswer((_) async {});
    when(() => storage.setActiveAccountId(any())).thenReturn(null);
    final client = ApiClient();
    client.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, statusCode: 200, data: {
        'access_token': 'test-access',
        'refresh_token': 'test-refresh',
        'user': {'id': 1, 'login_id': 'student', 'name': 'Student'},
      }));
    }));
    final repository = AuthRepository(client, storage: storage);
    await repository.login(
        loginId: 'student', password: 'password', rememberSession: false);
    expect(await client.getAccessToken(), 'test-access');
    expect(await client.getRefreshToken(), 'test-refresh');
    expect(await ApiClient().getAccessToken(), isNull);
    expect(await ApiClient().getRefreshToken(), isNull);
    await client.clearTokens();
    expect(await client.getAccessToken(), isNull);
  });
}
