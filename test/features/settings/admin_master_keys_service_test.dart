import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/settings/data/admin_master_keys_service.dart';
import 'package:quiz_vance_flutter/features/settings/domain/admin_authorization.dart';

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
      authorization: AdminAuthorization.password('admin-password'),
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

  test('reorders all keys with one atomic authorized request', () async {
    when(
      () => dio.post(
        ApiEndpoints.adminAiKeysReorder,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<void>(
        requestOptions: RequestOptions(path: ApiEndpoints.adminAiKeysReorder),
      ),
    );

    await service.reorderKeys(
      [_entry('1', 90), _entry('2', 10)],
      authorization: AdminAuthorization.biometric('one-use-token'),
    );

    final captured = verify(
      () => dio.post(
        ApiEndpoints.adminAiKeysReorder,
        data: captureAny(named: 'data'),
        options: captureAny(named: 'options'),
      ),
    ).captured;
    expect(captured.first, {
      'keys': [
        {'id': 1, 'priority': 10},
        {'id': 2, 'priority': 20},
      ],
    });
    final options = captured.last as Options;
    expect(options.headers, {'X-Admin-Step-Up': 'one-use-token'});
  });

  group('ApiKeyTestResult sanitization', () {
    test('maps invalid credentials without exposing provider details', () {
      final result = ApiKeyTestResult.fromJson(const {
        'is_valid': false,
        'message': 'secret=AIza-provider-detail',
        'latency_ms': 21,
        'error_code': 'invalid_key',
        'provider_status': 401,
      });

      expect(result.safeErrorCode, 'invalid_key');
      expect(result.safeMessage, 'Chave inválida ou expirada.');
      expect(result.safeDiagnostic, 'Código: invalid_key · HTTP 401');
      expect(result.safeMessage, isNot(contains('AIza')));
    });

    test('distinguishes permission, cooldown, outage and oversized request',
        () {
      final cases = <Map<String, Object>>[
        {
          'code': 'permission_denied',
          'status': 403,
          'message': 'Chave sem permissão para este provedor.',
        },
        {
          'code': 'rate_limited',
          'status': 429,
          'message': 'Limite temporário atingido. Aguarde o cooldown.',
        },
        {
          'code': 'provider_unavailable',
          'status': 503,
          'message': 'Provedor temporariamente indisponível.',
        },
        {
          'code': 'payload_too_large',
          'status': 413,
          'message':
              'A requisição excedeu o limite do provedor; a chave não foi recusada.',
        },
      ];

      for (final item in cases) {
        final result = ApiKeyTestResult.fromJson({
          'is_valid': false,
          'message': 'raw provider response',
          'latency_ms': 1,
          'error_code': item['code'],
          'provider_status': item['status'],
        });

        expect(result.safeErrorCode,
            item['code'] == 'rate_limited' ? 'rate_limit' : item['code']);
        expect(result.safeMessage, item['message']);
      }
    });

    test('infers a safe code from HTTP status and rejects unsafe code text',
        () {
      final result = ApiKeyTestResult.fromJson(const {
        'is_valid': false,
        'message': 'upstream leaked detail',
        'latency_ms': 2,
        'error_code': 'invalid_key<script>secret</script>',
        'provider_status': 503,
      });

      expect(result.safeErrorCode, 'provider_unavailable');
      expect(result.safeMessage, 'Provedor temporariamente indisponível.');
      expect(result.safeDiagnostic, 'Código: provider_unavailable · HTTP 503');
      expect(result.safeDiagnostic, isNot(contains('script')));
    });
  });
}
