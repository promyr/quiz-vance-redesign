import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/shared/providers/gamification_provider.dart';

bool _shouldIncrementStreak({
  required String? lastStreakDate,
  required String today,
}) {
  return lastStreakDate != today;
}

int _calculateLevel(int xp) => (xp ~/ 100) + 1;

void main() {
  group('Streak deduplicacao por data', () {
    test('primeiro quiz do dia incrementa streak', () {
      expect(
        _shouldIncrementStreak(lastStreakDate: null, today: '2026-03-20'),
        isTrue,
      );
    });

    test('segundo quiz do mesmo dia nao incrementa streak', () {
      expect(
        _shouldIncrementStreak(
          lastStreakDate: '2026-03-20',
          today: '2026-03-20',
        ),
        isFalse,
      );
    });

    test('quiz no dia seguinte incrementa streak', () {
      expect(
        _shouldIncrementStreak(
          lastStreakDate: '2026-03-20',
          today: '2026-03-21',
        ),
        isTrue,
      );
    });

    test('quiz apos varios dias sem jogar incrementa streak', () {
      expect(
        _shouldIncrementStreak(
          lastStreakDate: '2026-03-01',
          today: '2026-03-20',
        ),
        isTrue,
      );
    });

    test('data de hoje em formato ISO substring(0,10) e consistente', () {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      expect(today, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('varios quizzes no mesmo dia geram apenas um incremento', () {
      const today = '2026-03-20';
      String? lastStreakDate;
      var streakIncrements = 0;

      for (var i = 0; i < 5; i++) {
        if (_shouldIncrementStreak(
          lastStreakDate: lastStreakDate,
          today: today,
        )) {
          streakIncrements++;
          lastStreakDate = today;
        }
      }

      expect(streakIncrements, equals(1));
    });

    test('quizzes em dias consecutivos incrementam uma vez por dia', () {
      final days = ['2026-03-18', '2026-03-19', '2026-03-20'];
      String? lastStreakDate;
      var totalIncrements = 0;

      for (final day in days) {
        for (var quiz = 0; quiz < 3; quiz++) {
          if (_shouldIncrementStreak(
            lastStreakDate: lastStreakDate,
            today: day,
          )) {
            totalIncrements++;
            lastStreakDate = day;
          }
        }
      }

      expect(totalIncrements, equals(3));
    });
  });

  group('_calculateLevel', () {
    test('XP 0 gera nivel 1', () => expect(_calculateLevel(0), equals(1)));
    test('XP 99 gera nivel 1', () => expect(_calculateLevel(99), equals(1)));
    test('XP 100 gera nivel 2', () => expect(_calculateLevel(100), equals(2)));
    test('XP 199 gera nivel 2', () => expect(_calculateLevel(199), equals(2)));
    test('XP 200 gera nivel 3', () => expect(_calculateLevel(200), equals(3)));
    test('XP 500 gera nivel 6', () => expect(_calculateLevel(500), equals(6)));
    test('XP 1000 gera nivel 11',
        () => expect(_calculateLevel(1000), equals(11)));
    test('XP 9999 gera nivel 100',
        () => expect(_calculateLevel(9999), equals(100)));
  });

  group('GamificationState.xpProgress', () {
    test('sempre fica entre 0.0 e 1.0', () {
      for (final xp in [0, 50, 99, 100, 150, 200, 999, 10000]) {
        final level = _calculateLevel(xp);
        final state = GamificationState(totalXp: xp, level: level);

        expect(
          state.xpProgress,
          inInclusiveRange(0.0, 1.0),
          reason: 'xp=$xp level=$level xpProgress=${state.xpProgress}',
        );
      }
    });

    test('xpProgress vale 0 no inicio do nivel', () {
      final state = GamificationState(totalXp: 100, level: 2);
      expect(state.xpProgress, equals(0.0));
    });

    test('xpProgress vale 0.5 no meio do nivel', () {
      final state = GamificationState(totalXp: 150, level: 2);
      expect(state.xpProgress, closeTo(0.5, 0.001));
    });

    test('xpProgress fica clampado em 1.0 no topo do nivel', () {
      final state = GamificationState(totalXp: 250, level: 2);
      expect(state.xpProgress, equals(1.0));
    });
  });

  group('GamificationState.copyWith', () {
    test('limpa flags transientes via copyWith', () {
      const state = GamificationState(
        justLeveledUp: true,
        justUnlockedAchievement: true,
        newAchievement: 'Primeiro Quiz',
      );

      final cleared = state.copyWith(
        justLeveledUp: false,
        justUnlockedAchievement: false,
      );

      expect(cleared.justLeveledUp, isFalse);
      expect(cleared.justUnlockedAchievement, isFalse);
      expect(cleared.newAchievement, equals('Primeiro Quiz'));
    });

    test('adiciona conquista a lista existente', () {
      const state = GamificationState(
        unlockedAchievements: ['Conquista A'],
      );

      final updated = state.copyWith(
        unlockedAchievements: [...state.unlockedAchievements, 'Conquista B'],
        justUnlockedAchievement: true,
        newAchievement: 'Conquista B',
      );

      expect(updated.unlockedAchievements, hasLength(2));
      expect(updated.unlockedAchievements, contains('Conquista B'));
      expect(updated.justUnlockedAchievement, isTrue);
      expect(updated.newAchievement, equals('Conquista B'));
    });

    test('incremento de streak atualiza longestStreak', () {
      const state = GamificationState(streak: 5, longestStreak: 5);

      final newStreak = state.streak + 1;
      final newLongest =
          newStreak > state.longestStreak ? newStreak : state.longestStreak;

      final updated = state.copyWith(
        streak: newStreak,
        longestStreak: newLongest,
      );

      expect(updated.streak, equals(6));
      expect(updated.longestStreak, equals(6));
    });

    test('longestStreak nao decresce quando streak e resetado', () {
      const state = GamificationState(streak: 10, longestStreak: 10);
      final updated = state.copyWith(streak: 0);

      expect(updated.streak, equals(0));
      expect(updated.longestStreak, equals(10));
    });

    test('campo totalQuizzes incrementa corretamente', () {
      const state = GamificationState(totalQuizzes: 9);
      final updated = state.copyWith(totalQuizzes: state.totalQuizzes + 1);
      expect(updated.totalQuizzes, equals(10));
    });
  });

  group('GamificationState valores default', () {
    test('estado inicial sem argumentos permanece seguro', () {
      const state = GamificationState();

      expect(state.totalXp, equals(0));
      expect(state.level, equals(1));
      expect(state.streak, equals(0));
      expect(state.longestStreak, equals(0));
      expect(state.totalQuizzes, equals(0));
      expect(state.unlockedAchievements, isEmpty);
      expect(state.justLeveledUp, isFalse);
      expect(state.justUnlockedAchievement, isFalse);
      expect(state.newAchievement, isNull);
      expect(state.xpProgress, equals(0.0));
    });
  });
}
