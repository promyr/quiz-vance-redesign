import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';
import 'package:quiz_vance_flutter/features/stats/presentation/stats_screen.dart';
import 'package:quiz_vance_flutter/features/conquistas/presentation/conquistas_screen.dart';
import 'package:quiz_vance_flutter/features/history/presentation/activity_history_screen.dart';
import 'package:quiz_vance_flutter/features/history/data/history_repository.dart';
import 'package:quiz_vance_flutter/features/history/domain/activity_entry.dart';

class Stats extends UserStatsNotifier {
  @override
  Future<UserStats> build() async => const UserStats(
      xp: 123456,
      level: 129,
      streak: 123,
      totalQuizzes: 12345,
      todayQuizzes: 99,
      todayCorrect: 88,
      todayXp: 999,
      levelLabel: 'Mestre dos estudos avançados');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!File(r'C:\Windows\Fonts\segoeui.ttf').existsSync()) {
      return;
    }
    final font = FontLoader('VisualTestFont');
    font.addFont(File(r'C:\Windows\Fonts\segoeui.ttf')
        .readAsBytes()
        .then(ByteData.sublistView));
    await font.load();
    if (!File(
            r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf')
        .existsSync()) {
      return;
    }
    final icons = FontLoader('MaterialIcons');
    icons.addFont(File(
            r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf')
        .readAsBytes()
        .then(ByteData.sublistView));
    await icons.load();
  });
  for (final screen in <String, Widget>{
    'estatisticas': const StatsScreen(),
    'conquistas': const ConquistasScreen(),
    'historico': const ActivityHistoryScreen()
  }.entries) {
    for (final width in [280.0, 360.0, 800.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('${screen.key} width=$width scale=$scale', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(ProviderScope(
              overrides: [
                userStatsNotifierProvider.overrideWith(Stats.new),
                activityHistoryProvider.overrideWith((ref) async => [
                      ActivityEntry(
                          eventId: 'q',
                          total: 100,
                          correct: 88,
                          xpEarned: 440,
                          accuracy: 88,
                          createdAt: DateTime(2026, 10, 7))
                    ]),
              ],
              child: MaterialApp(
                  theme: ThemeData(fontFamily: 'VisualTestFont'),
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: screen.value)));
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          await tester.pump();
          expect(tester.takeException(), isNull);
          final scrolls = find.byType(Scrollable);
          if (scrolls.evaluate().isNotEmpty) {
            await tester.drag(scrolls.first, const Offset(0, -700));
            await tester.pump(const Duration(seconds: 1));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
