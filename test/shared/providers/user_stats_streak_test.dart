import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';

String _dateOnly(DateTime value) => value.toIso8601String().substring(0, 10);

void main() {
  group('UserStats streak expiration', () {
    test('zera a sequencia quando a ultima atividade foi ontem', () {
      final lastActivity =
          _dateOnly(DateTime.now().subtract(const Duration(days: 1)));

      final stats = UserStats.fromJson({
        'streak_days': 6,
        'last_activity_day': lastActivity,
      });

      expect(stats.streak, 0);
    });

    test('mantem a sequencia quando houve atividade hoje', () {
      final lastActivity = _dateOnly(DateTime.now());

      final stats = UserStats.fromJson({
        'streak_days': 6,
        'last_activity_day': lastActivity,
      });

      expect(stats.streak, 6);
    });
  });
}
