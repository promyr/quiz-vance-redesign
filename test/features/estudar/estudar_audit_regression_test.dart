import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/estudar/presentation/estudar_screen.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';

class _Stats extends UserStatsNotifier {
  @override
  Future<UserStats> build() async =>
      const UserStats(quizRestante: 5, quizLimite: 5, isPremium: false);
}

Future<void> _show(WidgetTester tester, {double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        userStatsNotifierProvider.overrideWith(_Stats.new),
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
  testWidgets('cards retirados não aparecem entre os modos', (tester) async {
    await _show(tester);
    for (var i = 0; i < 6; i++) {
      expect(find.textContaining('Flashcards'), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();
    }
  });
}
