import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/conquistas/presentation/conquistas_screen.dart';
import 'package:quiz_vance_flutter/features/conquistas/domain/achievement_catalog.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';
import 'package:quiz_vance_flutter/shared/providers/gamification_provider.dart';

class FixedStats extends UserStatsNotifier {
  FixedStats(this.stats);
  final UserStats stats;
  @override
  Future<UserStats> build() async => stats;
}

class FixedGamification extends GamificationNotifier {
  @override
  Future<GamificationState> build() async => GamificationState(
      unlockedAchievements: [achievementDisplayName(achievementCatalog.first)]);
}

void main() {
  for (final remoteUnlocked in [false, true]) {
    testWidgets(
        'conquista local pendente aparece uma vez, remoto $remoteUnlocked',
        (tester) async {
      final container = ProviderContainer(overrides: [
        userStatsNotifierProvider.overrideWith(() => FixedStats(UserStats(
            achievements: remoteUnlocked ? ['primeira_questao'] : []))),
        gamificationProvider.overrideWith(FixedGamification.new),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ConquistasScreen())));
      await tester.pumpAndSettle();
      expect(find.text('1/10 desbloqueadas'), findsOneWidget);
      expect(find.text('50 XP em conquistas'), findsOneWidget);
      expect(container.read(userStatsNotifierProvider).requireValue.xp, 0);
      expect(
          container.read(userStatsNotifierProvider).requireValue.totalQuizzes,
          0);
      expect(tester.takeException(), isNull);
    });
  }
}
