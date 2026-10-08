import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/stats/presentation/stats_screen.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';

class FixedStats extends UserStatsNotifier {
  FixedStats(this.stats);
  final UserStats stats;
  @override
  Future<UserStats> build() async => stats;
}

void main() {
  for (final total in [0, 2]) {
    testWidgets('feedback não inventa queda com $total resultados',
        (tester) async {
      await tester.pumpWidget(ProviderScope(overrides: [
        userStatsNotifierProvider.overrideWith(
            () => FixedStats(UserStats(totalQuizzes: total, taxaAcerto: 0))),
      ], child: const MaterialApp(home: StatsScreen())));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sua taxa caiu'), findsNothing);
      expect(
          find.textContaining(total == 0
              ? 'Ainda não há resultados sincronizados'
              : 'Revise os fundamentos'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
