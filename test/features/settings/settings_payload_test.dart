import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/settings/providers/settings_provider.dart';

void main() {
  group('buildAiConfigPayload', () {
    test('omite chaves vazias do payload remoto', () {
      final payload = buildAiConfigPayload(
        provider: 'groq',
        geminiKey: '   ',
        groqKey: 'gsk-groq',
      );

      expect(payload['provider'], equals('groq'));
      expect(payload['model'], equals('llama-3.3-70b-versatile'));
      expect(payload.containsKey('api_key_gemini'), isFalse);
      expect(payload['api_key_groq'], equals('gsk-groq'));
    });

    test('mantem somente os campos preenchidos', () {
      final payload = buildAiConfigPayload(
        provider: 'gemini',
        geminiKey: 'gem-key',
      );

      expect(
        payload,
        equals({
          'provider': 'gemini',
          'model': 'gemini-3.5-flash',
          'api_key_gemini': 'gem-key',
        }),
      );
    });

    test('resolve modelo padrão compatível para groq', () {
      final payload = buildAiConfigPayload(
        provider: 'groq',
        groqKey: 'gsk-test',
      );

      expect(payload['model'], equals('llama-3.3-70b-versatile'));
    });

    test('sincroniza chave OpenAI com modelo compatível', () {
      final payload = buildAiConfigPayload(
        provider: 'openai',
        openaiKey: 'sk-openai-test',
      );

      expect(payload['model'], equals('gpt-4o-mini'));
      expect(payload['api_key_openai'], equals('sk-openai-test'));
    });
  });
}
