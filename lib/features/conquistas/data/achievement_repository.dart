/// Repositório de conquistas — persiste achievements desbloqueados no backend.
///
/// Chamado pelo [GamificationNotifier] assim que detecta um novo desbloqueio.
/// Idempotente: o backend ignora conquistas já registradas.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/achievement_catalog.dart';

class AchievementRepository {
  const AchievementRepository(this._client);

  final ApiClient _client;

  /// Busca as conquistas já desbloqueadas no backend.
  ///
  /// Retorna lista de `achievement_id` (codes). Em caso de erro retorna lista
  /// vazia para não bloquear o boot do app.
  Future<List<String>> getAchievements() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.userAchievements);
      final raw = response.data as Map<String, dynamic>?;
      final list = raw?['achievements'] as List<dynamic>? ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => e['achievement_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Envia um desbloqueio de conquista ao backend.
  ///
  /// Retorna silenciosamente em caso de erro de rede — a conquista já está
  /// persistida localmente em SharedPreferences e será re-tentada no futuro.
  Future<void> unlock(AchievementDefinition achievement) async {
    try {
      await _client.dio.post(
        ApiEndpoints.userAchievementsUnlock,
        data: {
          'achievement_id': achievement.code,
          'title': achievement.title,
          'description': achievement.description,
          'icon': achievement.emoji,
          'xp_reward': achievement.xpReward,
        },
      );
    } catch (_) {
      // Falha silenciosa — o desbloqueio local já ocorreu.
      // O backend sincronizará quando a conectividade for restaurada.
    }
  }
}

final achievementRepositoryProvider = Provider<AchievementRepository>(
  (ref) => AchievementRepository(ref.watch(apiClientProvider)),
);
