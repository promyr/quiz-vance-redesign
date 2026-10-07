import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/estudar/presentation/estudar_screen.dart';
import 'package:quiz_vance_flutter/features/flashcard/data/flashcard_repository.dart';
import 'package:quiz_vance_flutter/features/flashcard/domain/flashcard_model.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';

class _Stats extends UserStatsNotifier {
  @override
  Future<UserStats> build() async =>
      const UserStats(quizRestante: 5, quizLimite: 5, isPremium: false);
}

Future<void> _show(WidgetTester tester,
    {double scale = 1, List<Flashcard> cards = const []}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        userStatsNotifierProvider.overrideWith(_Stats.new),
        reviewFlashcardsProvider.overrideWith((ref) async => cards),
      ],
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: const EstudarScreen())));
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.5, 2.0]) {
    testWidgets('modos não cortam conteúdo a 320dp fonte $scale',
        (tester) async {
      await _show(tester, scale: scale);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('deck vazio não anuncia doze pendências fictícias',
      (tester) async {
    await _show(tester);
    await tester.scrollUntilVisible(find.text('Flashcards'), 250);
    expect(find.text('12 pendentes'), findsNothing);
    expect(find.text('Nenhum salvo'), findsOneWidget);
  });
  testWidgets('contagem inclui vencidos e exclui cartões futuros',
      (tester) async {
    final today = DateTime.now();
    await _show(tester, cards: [
      Flashcard(
          id: 1,
          front: 'Um',
          back: 'A',
          dueDate: DateTime(2020),
          createdAt: today),
      Flashcard(
          id: 2,
          front: 'Dois',
          back: 'B',
          dueDate: DateTime(2999),
          createdAt: today),
    ]);
    await tester.scrollUntilVisible(find.text('Flashcards'), 250);
    expect(find.text('1 pendente'), findsOneWidget);
  });
}
