enum AchievementMetric { totalQuizzes, streak, level, xp }

class AchievementDefinition {
  const AchievementDefinition({
    required this.code,
    required this.title,
    required this.description,
    required this.emoji,
    required this.xpReward,
    required this.metric,
    required this.target,
  });

  final String code;
  final String title;
  final String description;
  final String emoji;
  final int xpReward;
  final AchievementMetric metric;
  final int target;
}

const achievementCatalog = <AchievementDefinition>[
  AchievementDefinition(
    code: 'primeira_questao',
    title: 'Primeira Questão',
    description: 'Complete sua primeira questão',
    emoji: '🎯',
    xpReward: 50,
    metric: AchievementMetric.totalQuizzes,
    target: 1,
  ),
  AchievementDefinition(
    code: '10_questoes',
    title: 'Iniciante',
    description: 'Complete 10 questões',
    emoji: '📚',
    xpReward: 100,
    metric: AchievementMetric.totalQuizzes,
    target: 10,
  ),
  AchievementDefinition(
    code: '50_questoes',
    title: 'Estudante',
    description: 'Complete 50 questões',
    emoji: '🎓',
    xpReward: 250,
    metric: AchievementMetric.totalQuizzes,
    target: 50,
  ),
  AchievementDefinition(
    code: '100_questoes',
    title: 'Dedicado',
    description: 'Complete 100 questões',
    emoji: '🏆',
    xpReward: 500,
    metric: AchievementMetric.totalQuizzes,
    target: 100,
  ),
  AchievementDefinition(
    code: 'streak_3',
    title: 'Consistente',
    description: 'Mantenha sequência de 3 dias',
    emoji: '🔥',
    xpReward: 150,
    metric: AchievementMetric.streak,
    target: 3,
  ),
  AchievementDefinition(
    code: 'streak_7',
    title: 'Comprometido',
    description: 'Mantenha sequência de 7 dias',
    emoji: '⚡',
    xpReward: 350,
    metric: AchievementMetric.streak,
    target: 7,
  ),
  AchievementDefinition(
    code: 'nivel_5',
    title: 'Nível 5',
    description: 'Alcance o nível 5',
    emoji: '⭐',
    xpReward: 300,
    metric: AchievementMetric.level,
    target: 5,
  ),
  AchievementDefinition(
    code: 'nivel_mestre',
    title: 'Mestre Supremo',
    description: 'Alcance o nível 10',
    emoji: '👑',
    xpReward: 1000,
    metric: AchievementMetric.level,
    target: 10,
  ),
  AchievementDefinition(
    code: 'xp_100',
    title: '100 XP',
    description: 'Acumule 100 XP',
    emoji: '💫',
    xpReward: 100,
    metric: AchievementMetric.xp,
    target: 100,
  ),
  AchievementDefinition(
    code: 'xp_500',
    title: '500 XP',
    description: 'Acumule 500 XP',
    emoji: '💎',
    xpReward: 500,
    metric: AchievementMetric.xp,
    target: 500,
  ),
];

bool isAchievementUnlocked(
  AchievementDefinition achievement, {
  required int totalQuizzes,
  required int streak,
  required int level,
  required int xp,
}) {
  switch (achievement.metric) {
    case AchievementMetric.totalQuizzes:
      return totalQuizzes >= achievement.target;
    case AchievementMetric.streak:
      return streak >= achievement.target;
    case AchievementMetric.level:
      return level >= achievement.target;
    case AchievementMetric.xp:
      return xp >= achievement.target;
  }
}

String achievementDisplayName(AchievementDefinition achievement) {
  return '${achievement.emoji} ${achievement.title}';
}

List<String> unlockedAchievementNames({
  required int totalQuizzes,
  required int streak,
  required int level,
  required int xp,
}) {
  return achievementCatalog
      .where(
        (achievement) => isAchievementUnlocked(
          achievement,
          totalQuizzes: totalQuizzes,
          streak: streak,
          level: level,
          xp: xp,
        ),
      )
      .map(achievementDisplayName)
      .toList();
}
