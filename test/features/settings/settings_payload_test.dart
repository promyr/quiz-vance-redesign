import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/settings/providers/settings_provider.dart';

void main() {
  group('buildAiConfigPayload', () {
    test('omite chaves vazias do payload remoto', () {
      final payload = buildAiConfigPayload(
        provider: 'openai',
        geminiKey: '   ',
        openaiKey: 'sk-openai',
        groqKey: '',
      );

      expect(payload['provider'], equals('openai'));
      expect(payload['model'], equals('gpt-4o-mini'));
      expect(payload.containsKey('api_key_gemini'), isFalse);
      expect(payload['api_key_openai'], equals('sk-openai'));
      expect(payload.containsKey('api_key_groq'), isFalse);
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
          'model': 'gemini-2.0-flash',
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
  });
}
