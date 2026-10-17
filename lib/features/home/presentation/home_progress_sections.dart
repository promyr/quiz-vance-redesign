part of 'home_screen.dart';

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak, required this.compact});
  final int streak;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreakBadge(
      streak: streak,
      isActiveToday: true,
      compact: compact,
    );
  }
}

class _QuotaBanner extends StatelessWidget {
  const _QuotaBanner({
    required this.quizRestante,
    required this.quizLimite,
    required this.isPremium,
  });

  final int quizRestante;
  final int quizLimite;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    if (isPremium || quizRestante == -1) {
      return NeoGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        borderRadius: 20,
        borderGradient: AppColors.goldGradient,
        backgroundColor: AppColors.xpGold.withOpacity(0.08),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppColors.goldGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Colors.black,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ACESSO VIP',
                    style: TextStyle(
                      color: AppColors.xpGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Quizzes Ilimitados',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final double progress =
        quizLimite > 0 ? (quizRestante / quizLimite).clamp(0.0, 1.0) : 0.0;

    return NeoGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: 20,
      backgroundColor: AppColors.surface.withOpacity(0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Quotas de Hoje',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$quizRestante / $quizLimite',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.primaryLight),
            ),
          ),
        ],
      ),
    );
  }
}

class _XPBar extends StatelessWidget {
  const _XPBar({required this.stats});
  final dynamic stats;

  @override
  Widget build(BuildContext context) {
    final level = stats.level ?? 1;
    final xp = stats.xp ?? 0;
    final totalQuizzes = stats.totalQuizzes ?? 0;
    final xpToNextLevel = stats.xpToNextLevel ?? 100;
    final progress = xpToNextLevel > 0 ? (xp % 100) / 100.0 : 1.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: NeoGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.xpGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.xpGold.withOpacity(0.4),
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(children: [
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.bolt_rounded,
                              color: AppColors.xpGold, size: 15),
                        ),
                      ),
                      TextSpan(text: 'Nível $level · ${_getRankName(level)}'),
                    ]),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '$xp XP',
                  style: const TextStyle(
                    color: AppColors.xpGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '• $totalQuizzes questões',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                minHeight: 7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
