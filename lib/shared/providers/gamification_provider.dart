import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/conquistas/data/achievement_repository.dart';
import '../../features/conquistas/domain/achievement_catalog.dart';
import '../application/account_scoped_preferences.dart';

class GamificationState {
  const GamificationState({
    this.totalXp = 0,
    this.level = 1,
    this.streak = 0,
    this.longestStreak = 0,
    this.totalQuizzes = 0,
    this.unlockedAchievements = const [],
    this.justLeveledUp = false,
    this.justUnlockedAchievement = false,
    this.newAchievement,
    this.newAchievementXp = 0,
  });

  final int totalXp;
  final int level;
  final int streak;
  final int longestStreak;
  final int totalQuizzes;
  final List<String> unlockedAchievements;
  final bool justLeveledUp;
  final bool justUnlockedAchievement;
  final String? newAchievement;
  final int newAchievementXp;

  double get xpProgress {
    final xpForCurrentLevel = (level - 1) * 100;
    final xpInCurrentLevel = totalXp - xpForCurrentLevel;
    return (xpInCurrentLevel / 100).clamp(0.0, 1.0);
  }

  GamificationState copyWith({
    int? totalXp,
    int? level,
    int? streak,
    int? longestStreak,
    int? totalQuizzes,
    List<String>? unlockedAchievements,
    bool? justLeveledUp,
    bool? justUnlockedAchievement,
    String? newAchievement,
    int? newAchievementXp,
  }) {
    return GamificationState(
      totalXp: totalXp ?? this.totalXp,
      level: level ?? this.level,
      streak: streak ?? this.streak,
      longestStreak: longestStreak ?? this.longestStreak,
      totalQuizzes: totalQuizzes ?? this.totalQuizzes,
      unlockedAchievements: unlockedAchievements ?? this.unlockedAchievements,
      justLeveledUp: justLeveledUp ?? this.justLeveledUp,
      justUnlockedAchievement:
          justUnlockedAchievement ?? this.justUnlockedAchievement,
      newAchievement: newAchievement ?? this.newAchievement,
      newAchievementXp: newAchievementXp ?? this.newAchievementXp,
    );
  }
}

const _xpKey = 'gamif_xp';
const _levelKey = 'gamif_level';
const _streakKey = 'gamif_streak';
const _longestStreakKey = 'gamif_longest_streak';
const _totalQuizzesKey = 'gamif_total_quizzes';
const _achievementsKey = 'gamif_achievements';
const _processedQuizEventsKey = 'gamif_processed_quiz_events';
const _lastStreakDateKey = 'gamif_last_streak_date';

class GamificationNotifier extends AsyncNotifier<GamificationState> {
  Timer? _transientFlagTimer;
  final AccountScopedPreferences _preferences = AccountScopedPreferences.instance;

  AchievementRepository get _achievementRepo =>
      ref.read(achievementRepositoryProvider);

  @override
  Future<GamificationState> build() async {
    ref.onDispose(() => _transientFlagTimer?.cancel());

    final localAchievements =
        await _preferences.getStringList(_achievementsKey) ?? <String>[];

    unawaited(_syncAchievementsFromBackend(localAchievements));

    return GamificationState(
      totalXp: await _preferences.getInt(_xpKey) ?? 0,
      level: await _preferences.getInt(_levelKey) ?? 1,
      streak: await _preferences.getInt(_streakKey) ?? 0,
      longestStreak: await _preferences.getInt(_longestStreakKey) ?? 0,
      totalQuizzes: await _preferences.getInt(_totalQuizzesKey) ?? 0,
      unlockedAchievements: localAchievements,
    );
  }

  Future<void> _syncAchievementsFromBackend(List<String> currentLocal) async {
    try {
      final remoteCodes = await _achievementRepo.getAchievements();
      if (remoteCodes.isEmpty) return;

      final remoteNames = remoteCodes
          .map((code) {
            try {
              return achievementCatalog.firstWhere((item) => item.code == code);
            } catch (_) {
              return null;
            }
          })
          .whereType<AchievementDefinition>()
          .map(achievementDisplayName)
          .toList(growable: false);

      final merged = {...currentLocal, ...remoteNames}.toList(growable: false);
      if (merged.length == currentLocal.length) return;

      await _preferences.setStringList(_achievementsKey, merged);
      state.whenData(
        (current) =>
            state = AsyncData(current.copyWith(unlockedAchievements: merged)),
      );
    } catch (_) {
      // Falha silenciosa; o estado local continua valido.
    }
  }

  Future<void> addXp(int amount) async {
    final current = state.valueOrNull ?? const GamificationState();
    final newXp = current.totalXp + amount;
    final newLevel = _calculateLevel(newXp);
    final justLeveledUp = newLevel > current.level;

    final newAchievementDef = _checkAchievementDef(
      existing: current.unlockedAchievements,
      xp: newXp,
      streak: current.streak,
      level: newLevel,
      totalQuizzes: current.totalQuizzes,
    );
    final newAchievementName = newAchievementDef != null
        ? achievementDisplayName(newAchievementDef)
        : null;

    final updatedAchievements = newAchievementName != null
        ? [...current.unlockedAchievements, newAchievementName]
        : current.unlockedAchievements;

    await _preferences.setInt(_xpKey, newXp);
    await _preferences.setInt(_levelKey, newLevel);
    if (newAchievementName != null) {
      await _preferences.setStringList(_achievementsKey, updatedAchievements);
      unawaited(_achievementRepo.unlock(newAchievementDef!));
    }

    state = AsyncData(
      current.copyWith(
        totalXp: newXp,
        level: newLevel,
        justLeveledUp: justLeveledUp,
        justUnlockedAchievement: newAchievementName != null,
        newAchievement: newAchievementName,
        newAchievementXp: newAchievementDef?.xpReward ?? 0,
        unlockedAchievements: updatedAchievements,
      ),
    );

    _clearTransientFlags();
  }

  Future<void> incrementStreak() async {
    final current = state.valueOrNull ?? const GamificationState();
    final newStreak = current.streak + 1;
    final newLongest =
        newStreak > current.longestStreak ? newStreak : current.longestStreak;

    final newAchievementDef = _checkAchievementDef(
      existing: current.unlockedAchievements,
      xp: current.totalXp,
      streak: newStreak,
      level: current.level,
      totalQuizzes: current.totalQuizzes,
    );
    final newAchievementName = newAchievementDef != null
        ? achievementDisplayName(newAchievementDef)
        : null;
    final updatedAchievements = newAchievementName != null
        ? [...current.unlockedAchievements, newAchievementName]
        : current.unlockedAchievements;

    await _preferences.setInt(_streakKey, newStreak);
    await _preferences.setInt(_longestStreakKey, newLongest);
    if (newAchievementName != null) {
      await _preferences.setStringList(_achievementsKey, updatedAchievements);
      unawaited(_achievementRepo.unlock(newAchievementDef!));
    }

    state = AsyncData(
      current.copyWith(
        streak: newStreak,
        longestStreak: newLongest,
        justUnlockedAchievement: newAchievementName != null,
        newAchievement: newAchievementName,
        newAchievementXp: newAchievementDef?.xpReward ?? 0,
        unlockedAchievements: updatedAchievements,
      ),
    );

    if (newAchievementName != null) {
      _clearTransientFlags();
    }
  }

  Future<void> incrementTotalQuizzes() async {
    final current = state.valueOrNull ?? const GamificationState();
    final newTotal = current.totalQuizzes + 1;

    final newAchievementDef = _checkAchievementDef(
      existing: current.unlockedAchievements,
      xp: current.totalXp,
      streak: current.streak,
      level: current.level,
      totalQuizzes: newTotal,
    );
    final newAchievementName = newAchievementDef != null
        ? achievementDisplayName(newAchievementDef)
        : null;
    final updatedAchievements = newAchievementName != null
        ? [...current.unlockedAchievements, newAchievementName]
        : current.unlockedAchievements;

    await _preferences.setInt(_totalQuizzesKey, newTotal);
    if (newAchievementName != null) {
      await _preferences.setStringList(_achievementsKey, updatedAchievements);
      unawaited(_achievementRepo.unlock(newAchievementDef!));
    }

    state = AsyncData(
      current.copyWith(
        totalQuizzes: newTotal,
        justUnlockedAchievement: newAchievementName != null,
        newAchievement: newAchievementName,
        newAchievementXp: newAchievementDef?.xpReward ?? 0,
        unlockedAchievements: updatedAchievements,
      ),
    );

    if (newAchievementName != null) {
      _clearTransientFlags();
    }
  }

  Future<void> recordQuizCompletion({
    required String eventId,
    required int xpEarned,
  }) async {
    final processed =
        await _preferences.getStringList(_processedQuizEventsKey) ?? const [];
    if (processed.contains(eventId)) return;

    await addXp(xpEarned);
    await incrementTotalQuizzes();

    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _updateDailyStreak(today);

    final updated = [...processed, eventId];
    if (updated.length > 500) {
      updated.removeRange(0, updated.length - 500);
    }
    await _preferences.setStringList(_processedQuizEventsKey, updated);
  }

  Future<void> recordFlashcardReview({int xpEarned = 5}) async {
    await addXp(xpEarned);

    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _updateDailyStreak(today);
  }

  Future<void> _updateDailyStreak(String todayStr) async {
    final lastStreakDateStr = await _preferences.getString(_lastStreakDateKey);
    if (lastStreakDateStr == todayStr) return;

    if (lastStreakDateStr != null && lastStreakDateStr.isNotEmpty) {
      final now = DateTime.now();
      final yesterdayStr =
          now.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
      if (lastStreakDateStr != yesterdayStr) {
        // Passou mais de 1 dia desde a última prática: resetar streak para 1
        await _preferences.setInt(_streakKey, 1);
        await _preferences.setString(_lastStreakDateKey, todayStr);
        state.whenData((current) {
          final newLongest =
              current.longestStreak < 1 ? 1 : current.longestStreak;
          state = AsyncData(current.copyWith(
            streak: 1,
            longestStreak: newLongest,
          ));
        });
        return;
      }
    }

    await incrementStreak();
    await _preferences.setString(_lastStreakDateKey, todayStr);
  }

  Future<void> resetStreak() async {
    await _preferences.setInt(_streakKey, 0);
    state.whenData((current) => state = AsyncData(current.copyWith(streak: 0)));
  }

  int _calculateLevel(int xp) => (xp ~/ 100) + 1;

  AchievementDefinition? _checkAchievementDef({
    required List<String> existing,
    required int xp,
    required int streak,
    required int level,
    required int totalQuizzes,
  }) {
    for (final achievement in achievementCatalog) {
      final name = achievementDisplayName(achievement);
      final unlocked = isAchievementUnlocked(
        achievement,
        totalQuizzes: totalQuizzes,
        streak: streak,
        level: level,
        xp: xp,
      );
      if (!existing.contains(name) && unlocked) {
        return achievement;
      }
    }
    return null;
  }

  void _clearTransientFlags() {
    _transientFlagTimer?.cancel();
    _transientFlagTimer = Timer(const Duration(seconds: 3), () {
      try {
        state.whenData(
          (current) => state = AsyncData(
            current.copyWith(
              justLeveledUp: false,
              justUnlockedAchievement: false,
            ),
          ),
        );
      } catch (_) {
        // Notifier ja foi descartado.
      }
    });
  }
}

final gamificationProvider =
    AsyncNotifierProvider<GamificationNotifier, GamificationState>(
  GamificationNotifier.new,
);
