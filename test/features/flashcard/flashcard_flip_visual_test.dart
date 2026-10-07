import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/flashcard/data/flashcard_repository.dart';
import 'package:quiz_vance_flutter/features/flashcard/domain/flashcard_model.dart';
import 'package:quiz_vance_flutter/features/flashcard/presentation/flashcard_screen.dart';

void main() {
  testWidgets('resposta inteira mantém orientação legível após virar cartão',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      reviewFlashcardsProvider.overrideWith((ref) async => [
            Flashcard(
                id: 1,
                front: 'Pergunta teste',
                back: 'Resposta teste',
                dueDate: DateTime(2020),
                createdAt: DateTime(2020))
          ]),
    ], child: const MaterialApp(home: FlashcardScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pergunta teste'));
    await tester.pumpAndSettle();
    for (final text in ['Resposta', 'RESPOSTA', 'Resposta teste']) {
      final transform =
          tester.renderObject(find.text(text)).getTransformTo(null);
      expect(transform.entry(0, 0), greaterThan(0),
          reason: '$text está espelhado');
    }
    expect(tester.takeException(), isNull);
  });
}
