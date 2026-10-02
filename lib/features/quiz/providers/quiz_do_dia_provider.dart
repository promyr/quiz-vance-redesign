import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/local_storage.dart';

const _kDailyChallengeCompletedDateKey = 'daily_challenge_last_completed_date';

class DailyChallengeInfo {
  const DailyChallengeInfo({
    required this.topic,
    required this.dayName,
    required this.bonusXp,
    required this.isCompletedToday,
  });

  final String topic;
  final String dayName;
  final int bonusXp;
  final bool isCompletedToday;
}

class DailyChallengeNotifier extends AsyncNotifier<DailyChallengeInfo> {
  @override
  Future<DailyChallengeInfo> build() async {
    final now = DateTime.now();
    final todayStr = now.toIso8601String().substring(0, 10);

    final storage = LocalStorage.instance;
    final lastCompleted =
        await storage.getCacheValue(_kDailyChallengeCompletedDateKey);
    final isCompletedToday = lastCompleted == todayStr;

    // Rotação temática por dia da semana
    final (dayName, topic) = switch (now.weekday) {
      1 => ('Segunda-feira', 'Língua Portuguesa & Interpretação'),
      2 => ('Terça-feira', 'Raciocínio Lógico & Matemática'),
      3 => ('Quarta-feira', 'Direito Constitucional & Direitos Fundamentais'),
      4 => ('Quinta-feira', 'Informática & Tecnologia para Concursos'),
      5 => ('Sexta-feira', 'Atualidades & Conhecimentos Gerais'),
      6 => ('Sábado', 'Direito Administrativo & Licitações'),
      _ => ('Domingo', 'Simulado Geral Conhecimentos Mistos'),
    };

    return DailyChallengeInfo(
      topic: topic,
      dayName: dayName,
      bonusXp: 50,
      isCompletedToday: isCompletedToday,
    );
  }

  Future<void> markCompleted() async {
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    await LocalStorage.instance
        .setCacheValue(_kDailyChallengeCompletedDateKey, todayStr);
    ref.invalidateSelf();
  }
}

final dailyChallengeNotifierProvider =
    AsyncNotifierProvider<DailyChallengeNotifier, DailyChallengeInfo>(
  DailyChallengeNotifier.new,
);
