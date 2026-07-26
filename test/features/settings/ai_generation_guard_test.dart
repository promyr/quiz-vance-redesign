import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;
  late _MockSecureStorage storage;
  late AiGenerationGuard guard;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountScopedPreferences.instance.setActiveAccountId(null);

    apiClient = _MockApiClient();
    dio = _MockDio();
    storage = _MockSecureStorage();
    guard = AiGenerationGuard(apiClient, storage: storage);

    when(() => apiClient.dio).thenReturn(dio);
    when(() => storage.read(key: any(named: 'key'))).thenAnswer((invocation) {
      final key = invocation.namedArguments[#key] as String;
      return switch (key) {
        'api_key_gemini' => Future.value('gem-key'),
        'api_key_openai' => Future.value('openai-key'),
        'api_key_groq' => Future.value('groq-key'),
        _ => Future.value(''),
      };
    });
  });

  test(
      'ensureReadyForGeneration proceeds with selected provider using server keys when local key is absent',
      () async {
    SharedPreferences.setMockInitialValues({
      'ai_provider': 'groq',
    });

    when(() => storage.read(key: 'api_key_groq'))
        .thenAnswer((_) => Future.value(''));

    final provider = await guard.ensureReadyForGeneration();

    expect(provider, equals('groq'));

    verifyNever(
      () => dio.post(
        ApiEndpoints.userAiConfig,
        data: any(named: 'data'),
      ),
    );
  });

  test('ensureReadyForGeneration syncs pending config with all providers',
      () async {
    SharedPreferences.setMockInitialValues({
      'ai_provider': 'openai',
      'ai_config_sync_pending': true,
    });

    when(
      () => dio.post(
        ApiEndpoints.userAiConfig,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.userAiConfig),
        data: const {'ok': true},
      ),
    );

    final provider = await guard.ensureReadyForGeneration();

    expect(provider, 'openai');

    final captured = verify(
      () => dio.post(
        ApiEndpoints.userAiConfig,
        data: captureAny(named: 'data'),
      ),
    ).captured.single as Map<String, dynamic>;

    expect(captured['provider'], 'openai');
    expect(captured['model'], 'gpt-4o-mini');
    expect(captured['api_key_gemini'], 'gem-key');
    expect(captured['api_key_openai'], 'openai-key');
    expect(captured['api_key_groq'], 'groq-key');

    expect(
      await AccountScopedPreferences.instance.getBool('ai_config_sync_pending'),
      isFalse,
    );
    expect(
      await AccountScopedPreferences.instance
          .getString('ai_config_synced_provider'),
      'openai',
    );
  });

  test(
      'ensureReadyForGeneration resyncs current key even when provider was already synced',
      () async {
    SharedPreferences.setMockInitialValues({
      'ai_provider': 'gemini',
      'ai_config_sync_pending': false,
      'ai_config_synced_provider': 'gemini',
    });

    when(
      () => dio.post(
        ApiEndpoints.userAiConfig,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.userAiConfig),
        data: const {'ok': true},
      ),
    );

    final provider = await guard.ensureReadyForGeneration();

    expect(provider, 'gemini');
    final captured = verify(
      () => dio.post(
        ApiEndpoints.userAiConfig,
        data: captureAny(named: 'data'),
      ),
    ).captured.single as Map<String, dynamic>;
    expect(captured['api_key_gemini'], 'gem-key');
  });
}
