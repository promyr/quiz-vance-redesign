import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/user_stats_cache_service.dart';
import '../../core/exceptions/remote_service_exception.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../features/conquistas/domain/achievement_catalog.dart';

Future<Map<String, dynamic>> fetchUserStatsPayload(Ref ref) async {
  final client = ref.read(apiClientProvider);
  final cache = ref.read(userStatsCacheServiceProvider);

  try {
    final response = await client.dio.get(ApiEndpoints.userStats);
    final data = response.data as Map<String, dynamic>;
    await cache.saveRemoteStatsPayload(data);
    return data;
  } catch (_) {
    try {
      final cached = await cache.readRemoteStatsPayload();
      if (cached != null) {
        return cached;
      }
    } on FormatException {
      throw const RemoteServiceException(
        'O cache local de estatisticas esta corrompido.',
      );
    }

    throw const RemoteServiceException(
      'NÃ£o foi possÃ­vel carregar as estatÃ­sticas do usuÃ¡rio.',
    );
  }
}

/// Dados de quota diÃ¡ria de uso do produto.
///
/// Os campos `quizRestante`, `quizLimite`, `simuladoRestanteSemana` e
/// `simuladoLimiteSemana` usam a convenÃ§Ã£o do backend:
///   - `null`  â†’ campo ausente no payload (backend antigo ou nÃ£o carregado)
///   - `-1`    â†’ ilimitado (usuÃ¡rio Premium)
///   - `>= 0`  â†’ valor real restante ou limite do perÃ­odo
class UserStats {
  const UserStats({
    this.xp = 0,
    this.level = 1,
    this.levelLabel,
    this.streak = 0,
    this.totalQuizzes = 0,
    this.todayQuizzes = 0,
    this.todayCorrect = 0,
    this.todayXp = 0,
    this.flashcardsToday = 0,
    this.xpToNextLevel = 100,
    this.achievements = const [],
    this.taxaAcerto,
    this.isPremium = false,
    this.quizRestante,
    this.quizLimite,
    this.simuladoRestanteSemana,
    this.simuladoLimiteSemana,
    this.openQuizRestanteSemana,
    this.openQuizLimiteSemana,
  });

  factory UserStats.fromJson(Map<String, dynamic> data) {
    final xp = _readInt(data, ['xp', 'total_xp']);
    final numericLevel = _readIntOrNull(data, ['level']);
    final level = numericLevel ?? ((xp ~/ 100) + 1);
    final achievements = _readStringList(data, 'achievements');

    return UserStats(
      xp: xp,
      level: level,
      levelLabel: _readStringOrNull(data, ['level_name', 'level']),
      streak: _readInt(data, ['streak', 'streak_days', 'streak_dias']),
      totalQuizzes: _readInt(data, ['total_quizzes', 'total_questoes']),
      todayQuizzes: _readInt(data, ['today_quizzes', 'today_questoes']),
      todayCorrect: _readInt(data, ['today_correct', 'today_acertos']),
      todayXp: _readInt(data, ['today_xp']),
      flashcardsToday: _readInt(data, ['flashcards_due', 'flashcards_today']),
      xpToNextLevel: _readIntOrNull(data, ['xp_to_next_level']) ??
          _computeXpToNextLevel(xp),
      achievements: achievements.isNotEmpty
          ? achievements
          : unlockedAchievementNames(
              totalQuizzes: _readInt(data, ['total_quizzes', 'total_questoes']),
              streak: _readInt(data, ['streak', 'streak_days', 'streak_dias']),
              level: level,
              xp: xp,
            ),
      taxaAcerto:
          _readDoubleOrNull(data, ['accuracy_rate', 'accuracy', 'taxa_acerto']),
      isPremium: data['is_premium'] == true,
      quizRestante: _readIntOrNull(data, ['quiz_remaining_today']),
      quizLimite: _readIntOrNull(data, ['quiz_limit_today']),
      simuladoRestanteSemana: _readIntOrNull(data, ['simulado_remaining_week']),
      simuladoLimiteSemana: _readIntOrNull(data, ['simulado_limit_week']),
      openQuizRestanteSemana:
          _readIntOrNull(data, ['open_quiz_remaining_week']),
      openQuizLimiteSemana: _readIntOrNull(data, ['open_quiz_limit_week']),
    );
  }

  final int xp;
  final int level;
  final String? levelLabel;
  final int streak;
  final int totalQuizzes;
  final int todayQuizzes;
  final int todayCorrect;
  final int todayXp;
  final int flashcardsToday;
  final int xpToNextLevel;
  final List<String> achievements;
  final double? taxaAcerto;

  final bool isPremium;
  final int? quizRestante;
  final int? quizLimite;
  final int? simuladoRestanteSemana;
  final int? simuladoLimiteSemana;
  final int? openQuizRestanteSemana;
  final int? openQuizLimiteSemana;

  UserStats copyWith({
    int? xp,
    int? level,
    String? levelLabel,
    int? streak,
    int? totalQuizzes,
    int? todayQuizzes,
    int? todayCorrect,
    int? todayXp,
    int? flashcardsToday,
    int? xpToNextLevel,
    List<String>? achievements,
    double? taxaAcerto,
    bool? isPremium,
    int? quizRestante,
    int? quizLimite,
    int? simuladoRestanteSemana,
    int? simuladoLimiteSemana,
    int? openQuizRestanteSemana,
    int? openQuizLimiteSemana,
  }) {
    return UserStats(
      xp: xp ?? this.xp,
      level: level ?? this.level,
      levelLabel: levelLabel ?? this.levelLabel,
      streak: streak ?? this.streak,
      totalQuizzes: totalQuizzes ?? this.totalQuizzes,
      todayQuizzes: todayQuizzes ?? this.todayQuizzes,
      todayCorrect: todayCorrect ?? this.todayCorrect,
      todayXp: todayXp ?? this.todayXp,
      flashcardsToday: flashcardsToday ?? this.flashcardsToday,
      xpToNextLevel: xpToNextLevel ?? this.xpToNextLevel,
      achievements: achievements ?? this.achievements,
      taxaAcerto: taxaAcerto ?? this.taxaAcerto,
      isPremium: isPremium ?? this.isPremium,
      quizRestante: quizRestante ?? this.quizRestante,
      quizLimite: quizLimite ?? this.quizLimite,
      simuladoRestanteSemana:
          simuladoRestanteSemana ?? this.simuladoRestanteSemana,
      simuladoLimiteSemana: simuladoLimiteSemana ?? this.simuladoLimiteSemana,
      openQuizRestanteSemana:
          openQuizRestanteSemana ?? this.openQuizRestanteSemana,
      openQuizLimiteSemana: openQuizLimiteSemana ?? this.openQuizLimiteSemana,
    );
  }
}

class UserStatsNotifier extends AsyncNotifier<UserStats> {
  @override
  Future<UserStats> build() => _fetch();

  Future<UserStats> _fetch() async {
    final payload = await fetchUserStatsPayload(ref);
    return _mergeLocalFlashcards(UserStats.fromJson(payload));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> incrementFlashcardsToday({int amount = 1}) async {
    final current = state.valueOrNull ?? await _fetch();
    final nextCount = await ref
        .read(userStatsCacheServiceProvider)
        .incrementFlashcardsTodayCount(amount: amount);
    state = AsyncData(current.copyWith(flashcardsToday: nextCount));
  }

  Future<UserStats> _mergeLocalFlashcards(UserStats stats) async {
    final localCount = await ref
        .read(userStatsCacheServiceProvider)
        .readFlashcardsTodayCount();
    if (localCount == 0) return stats;
    return stats.copyWith(flashcardsToday: localCount);
  }
}

int _readInt(Map<String, dynamic> data, List<String> keys) {
  return _readIntOrNull(data, keys) ?? 0;
}

int? _readIntOrNull(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

double? _readDoubleOrNull(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

String? _readStringOrNull(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

List<String> _readStringList(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  return const [];
}

int _computeXpToNextLevel(int xp) {
  final remainder = xp % 100;
  return remainder == 0 ? 100 : 100 - remainder;
}

final userStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => fetchUserStatsPayload(ref),
);

final userStatsNotifierProvider =
    AsyncNotifierProvider<UserStatsNotifier, UserStats>(
  UserStatsNotifier.new,
);
