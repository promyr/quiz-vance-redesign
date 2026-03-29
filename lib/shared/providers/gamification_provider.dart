import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/conquistas/data/achievement_repository.dart';
import '../../features/conquistas/domain/achievement_catalog.dart';

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

  AchievementRepository get _achievementRepo =>
      ref.read(achievementRepositoryProvider);

  @override
  Future<GamificationState> build() async {
    ref.onDispose(() => _transientFlagTimer?.cancel());
    final prefs = await SharedPreferences.getInstance();

    final localAchievements = prefs.getStringList(_achievementsKey) ?? [];

    // Sincroniza conquistas do backend de forma assíncrona — não bloqueia o
    // boot. Se o backend tiver conquistas que o dispositivo perdeu (reinstal,
    // troca de celular), elas são restauradas sem spam de notificações.
    _syncAchievementsFromBackend(prefs, localAchievements);

    return GamificationState(
      totalXp: prefs.getInt(_xpKey) ?? 0,
      level: prefs.getInt(_levelKey) ?? 1,
      streak: prefs.getInt(_streakKey) ?? 0,
      longestStreak: prefs.getInt(_longestStreakKey) ?? 0,
      totalQuizzes: prefs.getInt(_totalQuizzesKey) ?? 0,
      unlockedAchievements: localAchievements,
    );
  }

  /// Baixa conquistas do backend e mescla com o estado local.
  ///
  /// Conquistas presentes no backend mas ausentes localmente são restauradas
  /// silenciosamente (sem toast) — evita spam depois de reinstalação.
  Future<void> _syncAchievementsFromBackend(
    SharedPreferences prefs,
    List<String> currentLocal,
  ) async {
    try {
      final remoteCodes = await _achievementRepo.getAchievements();
      if (remoteCodes.isEmpty) return;

      // Converte codes de volta para displayNames usados no estado local.
      final remoteNames = remoteCodes
          .map((code) {
            try {
              return achievementCatalog.firstWhere((a) => a.code == code);
            } catch (_) {
              return null;
            }
          })
          .whereType<AchievementDefinition>()
          .map(achievementDisplayName)
          .toList();

      final merged = {...currentLocal, ...remoteNames}.toList();
      if (merged.length == currentLocal.length) return; // nada novo

      await prefs.setStringList(_achievementsKey, merged);
      // Atualiza estado sem disparar toast (justUnlockedAchievement = false).
      state.whenData(
        (s) => state = AsyncData(s.copyWith(unlockedAchievements: merged)),
      );
    } catch (_) {
      // Falha silenciosa — conquistas locais permanecem intactas.
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_xpKey, newXp);
    await prefs.setInt(_levelKey, newLevel);
    if (newAchievementName != null) {
      await prefs.setStringList(_achievementsKey, updatedAchievements);
      // Persiste no backend de forma assíncrona (fire-and-forget).
      _achievementRepo.unlock(newAchievementDef!);
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
    final newLongest = newStreak > current.longestStreak
        ? newStreak
        : current.longestStreak;

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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_streakKey, newStreak);
    await prefs.setInt(_longestStreakKey, newLongest);
    if (newAchievementName != null) {
      await prefs.setStringList(_achievementsKey, updatedAchievements);
      _achievementRepo.unlock(newAchievementDef!);
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

    if (newAchievementName != null) _clearTransientFlags();
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_totalQuizzesKey, newTotal);
    if (newAchievementName != null) {
      await prefs.setStringList(_achievementsKey, updatedAchievements);
      _achievementRepo.unlock(newAchievementDef!);
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

    if (newAchievementName != null) _clearTransientFlags();
  }

  Future<void> recordQuizCompletion({
    required String eventId,
    required int xpEarned,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final processed = prefs.getStringList(_processedQuizEventsKey) ?? const [];
    if (processed.contains(eventId)) return;

    await addXp(xpEarned);
    await incrementTotalQuizzes();

    // Streak só incrementa uma vez por dia — evita inflação quando o
    // usuário completa vários quizzes no mesmo dia.
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastStreakDate = prefs.getString(_lastStreakDateKey);
    if (lastStreakDate != today) {
      await incrementStreak();
      await prefs.setString(_lastStreakDateKey, today);
    }

    final updated = [...processed, eventId];
    // Mantém os últimos 500 eventos para melhor proteção contra XP duplicado.
    if (updated.length > 500) {
      updated.removeRange(0, updated.length - 500);
    }
    await prefs.setStringList(_processedQuizEventsKey, updated);
  }

  Future<void> resetStreak() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_streakKey, 0);
    state.whenData((s) => state = AsyncData(s.copyWith(streak: 0)));
  }

  int _calculateLevel(int xp) => (xp ~/ 100) + 1;

  /// Retorna a definição completa da primeira conquista recém-atingida,
  /// ou null se nenhuma nova foi desbloqueada.
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
    // Cancela timer anterior para evitar múltiplos callbacks empilhados.
    _transientFlagTimer?.cancel();
    _transientFlagTimer = Timer(const Duration(seconds: 3), () {
      try {
        state.whenData(
          (s) => state = AsyncData(
            s.copyWith(
              justLeveledUp: false,
              justUnlockedAchievement: false,
            ),
          ),
        );
      } catch (_) {
        // Notifier descartado — ignorado com segurança.
      }
    });
  }
}

final gamificationProvider =
    AsyncNotifierProvider<GamificationNotifier, GamificationState>(
  GamificationNotifier.new,
);
