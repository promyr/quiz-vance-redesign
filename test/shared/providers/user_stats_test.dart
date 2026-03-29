import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';

void main() {
  group('UserStats', () {
    test('creates with default values', () {
      const stats = UserStats();

      expect(stats.xp, equals(0));
      expect(stats.level, equals(1));
      expect(stats.streak, equals(0));
      expect(stats.totalQuizzes, equals(0));
      expect(stats.flashcardsToday, equals(0));
      expect(stats.xpToNextLevel, equals(100));
      expect(stats.achievements, isEmpty);
    });

    test('fromJson parses all fields correctly', () {
      final json = {
        'xp': 250,
        'level': 3,
        'streak': 5,
        'total_quizzes': 10,
        'flashcards_due': 3,
        'xp_to_next_level': 50,
        'achievements': ['Primeiro Quiz', 'Semana Perfeita'],
      };

      final stats = UserStats.fromJson(json);

      expect(stats.xp, equals(250));
      expect(stats.level, equals(3));
      expect(stats.streak, equals(5));
      expect(stats.totalQuizzes, equals(10));
      expect(stats.flashcardsToday, equals(3));
      expect(stats.xpToNextLevel, equals(50));
      expect(stats.achievements, hasLength(2));
      expect(stats.achievements, contains('Primeiro Quiz'));
      expect(stats.achievements, contains('Semana Perfeita'));
    });

    test('fromJson parses backend stats payload', () {
      final json = {
        'total_xp': 420,
        'level': 'Bronze',
        'streak_days': 6,
        'total_questoes': 48,
        'today_questoes': 12,
        'today_acertos': 9,
        'today_xp': 80,
        'accuracy': 75.0,
      };

      final stats = UserStats.fromJson(json);

      expect(stats.xp, equals(420));
      expect(stats.level, equals(5));
      expect(stats.levelLabel, equals('Bronze'));
      expect(stats.streak, equals(6));
      expect(stats.totalQuizzes, equals(48));
      expect(stats.todayQuizzes, equals(12));
      expect(stats.todayCorrect, equals(9));
      expect(stats.todayXp, equals(80));
      expect(stats.taxaAcerto, equals(75.0));
      expect(stats.achievements, isNotEmpty);
    });

    test('fromJson handles missing numeric fields with defaults', () {
      final json = {
        'level': 2,
      };

      final stats = UserStats.fromJson(json);

      expect(stats.xp, equals(0));
      expect(stats.level, equals(2));
      expect(stats.streak, equals(0));
      expect(stats.totalQuizzes, equals(0));
      expect(stats.flashcardsToday, equals(0));
      expect(stats.xpToNextLevel, equals(100));
    });

    test('fromJson handles null values', () {
      final json = {
        'xp': null,
        'level': null,
        'achievements': null,
      };

      final stats = UserStats.fromJson(json);

      expect(stats.xp, equals(0));
      expect(stats.level, equals(1));
      expect(stats.achievements, isEmpty);
    });

    test('fromJson converts numeric types correctly', () {
      final json = {
        'xp': 150.5, // Should convert double to int
        'level': 2.0,
        'streak': 3,
      };

      final stats = UserStats.fromJson(json);

      expect(stats.xp, equals(150));
      expect(stats.level, equals(2));
      expect(stats.streak, equals(3));
    });

    test('copyWith updates single field', () {
      const stats = UserStats(
        xp: 100,
        level: 2,
        streak: 5,
      );

      final updated = stats.copyWith(xp: 200);

      expect(updated.xp, equals(200));
      expect(updated.level, equals(2));
      expect(updated.streak, equals(5));
    });

    test('copyWith updates multiple fields', () {
      const stats = UserStats(
        xp: 100,
        level: 2,
        streak: 5,
        totalQuizzes: 10,
      );

      final updated = stats.copyWith(
        xp: 300,
        level: 4,
        totalQuizzes: 20,
      );

      expect(updated.xp, equals(300));
      expect(updated.level, equals(4));
      expect(updated.streak, equals(5));
      expect(updated.totalQuizzes, equals(20));
    });

    test('copyWith preserves unmodified fields', () {
      const stats = UserStats(
        xp: 100,
        level: 2,
        streak: 5,
        totalQuizzes: 10,
        flashcardsToday: 3,
        xpToNextLevel: 100,
        achievements: ['Achievement 1'],
      );

      final updated = stats.copyWith(level: 3);

      expect(updated.xp, equals(stats.xp));
      expect(updated.level, equals(3));
      expect(updated.streak, equals(stats.streak));
      expect(updated.totalQuizzes, equals(stats.totalQuizzes));
      expect(updated.flashcardsToday, equals(stats.flashcardsToday));
      expect(updated.xpToNextLevel, equals(stats.xpToNextLevel));
      expect(updated.achievements, equals(stats.achievements));
    });

    test('copyWith updates achievements list', () {
      const stats = UserStats(
        achievements: ['Achievement 1'],
      );

      final updated = stats.copyWith(
        achievements: ['Achievement 1', 'Achievement 2'],
      );

      expect(updated.achievements, hasLength(2));
      expect(updated.achievements, contains('Achievement 2'));
    });

    test('fromJson with empty achievements list', () {
      final json = {
        'achievements': [],
      };

      final stats = UserStats.fromJson(json);

      expect(stats.achievements, isEmpty);
    });

    test('fromJson creates new list instances', () {
      final json1 = {
        'achievements': ['Achievement 1'],
      };
      final json2 = {
        'achievements': ['Achievement 1'],
      };

      final stats1 = UserStats.fromJson(json1);
      final stats2 = UserStats.fromJson(json2);

      expect(stats1.achievements, equals(stats2.achievements));
      // They should be different list objects
      expect(stats1.achievements, isNot(same(stats2.achievements)));
    });

    test('fromJson parses today_xp field from /user/stats backend response', () {
      final json = {
        'user_id': 1,
        'total_questoes': 50,
        'total_acertos': 40,
        'total_xp': 200,
        'level': 'Bronze',
        'streak_days': 3,
        'today_questoes': 5,
        'today_acertos': 4,
        'today_xp': 30,
        'accuracy': 80.0,
        'last_activity_day': '2026-03-20',
      };

      final stats = UserStats.fromJson(json);

      expect(stats.xp, equals(200));
      expect(stats.streak, equals(3));
      expect(stats.totalQuizzes, equals(50));
      expect(stats.todayQuizzes, equals(5));
      expect(stats.todayCorrect, equals(4));
      expect(stats.todayXp, equals(30));
      expect(stats.taxaAcerto, equals(80.0));
    });

    test('fromJson computes xpToNextLevel from xp when not provided', () {
      // XP=250 → level=3, xpForCurrentLevel=200, xpInLevel=50, xpToNext=50
      final stats = UserStats.fromJson({'xp': 250});
      expect(stats.xpToNextLevel, equals(50));
    });

    test('fromJson xpToNextLevel is 100 when at exact level boundary', () {
      // XP=200 → level=3, xpForCurrentLevel=200, xpInLevel=0, xpToNext=100
      final stats = UserStats.fromJson({'xp': 200});
      expect(stats.xpToNextLevel, equals(100));
    });
  });
}
