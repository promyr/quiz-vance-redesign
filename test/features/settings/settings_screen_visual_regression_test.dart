import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exibe cada provedor apenas uma vez', (tester) async {
    SharedPreferences.setMockInitialValues({'ai_provider': 'gemini'});
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gemini (Google)'), findsOneWidget);
    expect(find.text('Groq (Ultrarrápido)'), findsOneWidget);
    expect(find.text('OpenAI'), findsNothing);
    expect(find.text('Chave de API pessoal (opcional)'), findsNothing);
  });
}
