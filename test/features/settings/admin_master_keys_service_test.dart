import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/settings/data/admin_master_keys_service.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

MasterApiKeyEntry _entry(String id, int priority) => MasterApiKeyEntry(
      id: id,
      provider: 'gemini',
      maskedKey: '••••',
      label: id,
      priority: priority,
      isActive: true,
      healthStatus: 'healthy',
    );

void main() {
  late _MockApiClient client;
  late _MockDio dio;
  late _MockSecureStorage storage;
  late AdminMasterKeysService service;

  setUp(() {
    client = _MockApiClient();
    dio = _MockDio();
    storage = _MockSecureStorage();
    when(() => client.dio).thenReturn(dio);
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
    service = AdminMasterKeysService(client: client, storage: storage);
  });

  test('loads only masked key metadata from the admin API', () async {
    when(() => dio.get(ApiEndpoints.adminAiKeys)).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: ApiEndpoints.adminAiKeys),
        data: {
          'keys': [
            {
              'id': '7',
              'provider': 'gemini',
              'label': 'Principal',
              'masked_key': '••••••••1234',
              'priority': 10,
              'is_active': true,
              'health_status': 'healthy',
            },
          ],
        },
      ),
    );

    final keys = await service.getAllKeys();

    expect(keys, hasLength(1));
    expect(keys.single.maskedKey, '••••••••1234');
    expect(keys.single.healthStatus, 'healthy');
  });

  test('sends a new secret once and does not include the existing pool',
      () async {
    when(
      () => dio.post(
        ApiEndpoints.adminAiKeys,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: ApiEndpoints.adminAiKeys),
        statusCode: 201,
        data: const {
          'id': '8',
          'provider': 'groq',
          'label': 'Reserva',
          'masked_key': '••••••••abcd',
          'priority': 100,
          'is_active': true,
          'health_status': 'unknown',
        },
      ),
    );

    await service.addKey(
      provider: 'groq',
      apiKey: 'gsk-super-secret-abcd',
      label: 'Reserva',
      adminPassword: 'admin-password',
    );

    final verification = verify(
      () => dio.post(
        ApiEndpoints.adminAiKeys,
        data: captureAny(named: 'data'),
        options: captureAny(named: 'options'),
      ),
    );
    final payload = verification.captured.first as Map<String, dynamic>;
    final options = verification.captured.last as Options;
    expect(payload['api_key'], 'gsk-super-secret-abcd');
    expect(payload.containsKey('master_keys'), isFalse);
    expect(options.headers?['X-Admin-Password'], 'admin-password');
    expect(payload.containsValue('admin-password'), isFalse);
  });

  test('migrates the legacy local pool once and deletes its plaintext copy',
      () async {
    when(() => storage.read(key: 'admin_master_keys_pool')).thenAnswer(
      (_) async => jsonEncode([
        {
          'id': 'legacy',
          'provider': 'gemini',
          'api_key': 'AIza-legacy-secret-4321',
          'label': 'Legada',
          'is_active': true,
        },
      ]),
    );
    when(
      () => dio.post(
        ApiEndpoints.adminAiKeys,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: ApiEndpoints.adminAiKeys),
        statusCode: 201,
      ),
    );

    await service.migrateLegacyLocalPoolIfNeeded(
      adminPassword: 'admin-password',
    );

    final payload = verify(
      () => dio.post(
        ApiEndpoints.adminAiKeys,
        data: captureAny(named: 'data'),
        options: any(named: 'options'),
      ),
    ).captured.single as Map<String, dynamic>;
    expect(payload['api_key'], 'AIza-legacy-secret-4321');
    verify(() => storage.delete(key: 'admin_master_keys_pool')).called(1);
  });

  test('reorder rolls back priorities already changed after partial failure',
      () async {
    when(
      () => dio.patch(
        ApiEndpoints.adminAiKey('first'),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<void>(
        requestOptions: RequestOptions(path: ApiEndpoints.adminAiKey('first')),
      ),
    );
    when(
      () => dio.patch(
        ApiEndpoints.adminAiKey('second'),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.adminAiKey('second')),
      ),
    );

    await expectLater(
      service.reorderKeys(
        [_entry('first', 90), _entry('second', 10)],
        adminPassword: 'admin-password',
      ),
      throwsA(isA<DioException>()),
    );

    final firstCalls = verify(
      () => dio.patch(
        ApiEndpoints.adminAiKey('first'),
        data: captureAny(named: 'data'),
        options: any(named: 'options'),
      ),
    ).captured.cast<Map<String, dynamic>>();
    expect(firstCalls.map((data) => data['priority']), [10, 90]);
  });
}
