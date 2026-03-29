import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/shared/widgets/app_button.dart';

void main() {
  testWidgets('AppButton renders label and triggers callback', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppButton(
            label: 'Entrar',
            onPressed: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Entrar'), findsOneWidget);

    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('AppButton expõe semântica de botão acessível', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Gerar quiz',
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(AppButton)),
        matchesSemantics(
          label: 'Gerar quiz',
          hint: 'Pressione Enter ou Espaco para ativar',
          hasTapAction: true,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('AppButton aceita ativação por teclado', (tester) async {
    var pressed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppButton(
            label: 'Entrar',
            onPressed: () => pressed++,
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(pressed, 1);
  });
}
