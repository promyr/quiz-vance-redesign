import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cliente nao oferece configuracao de chave pessoal de IA', () {
    final settingsSources = <String>[
      'lib/features/settings/data/ai_generation_guard.dart',
      'lib/features/settings/domain/ai_provider_catalog.dart',
      'lib/features/settings/providers/settings_provider.dart',
      'lib/features/settings/presentation/settings_screen.dart',
    ].map(File.new).map((file) => file.readAsStringSync()).join('\n');

    expect(settingsSources, isNot(contains('ApiKeysScreen')));
    expect(settingsSources, isNot(contains('api_key_gemini')));
    expect(settingsSources, isNot(contains('api_key_groq')));
    expect(settingsSources, isNot(contains('FlutterSecureStorage')));
  });
}
