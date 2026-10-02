import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AccountScopedPreferences.instance.setActiveAccountId(null);
  });

  test('usa Gemini por padrao com chaves mantidas somente no servidor',
      () async {
    final provider = await AiGenerationGuard().ensureReadyForGeneration();

    expect(provider, 'gemini');
  });

  test('respeita o provedor salvo pelo usuario', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ai_provider': 'groq',
    });

    final provider = await AiGenerationGuard().ensureReadyForGeneration();

    expect(provider, 'groq');
  });

  test('normaliza override e rejeita valores obsoletos com fallback seguro',
      () async {
    final guard = AiGenerationGuard();

    expect(
      await guard.ensureReadyForGeneration(overrideProvider: ' GROQ '),
      'groq',
    );
    expect(
      await guard.ensureReadyForGeneration(overrideProvider: 'openai'),
      'gemini',
    );
  });
}
