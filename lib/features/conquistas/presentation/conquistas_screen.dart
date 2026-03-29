import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/user_provider.dart';
import '../domain/achievement_catalog.dart';

class ConquistasScreen extends ConsumerWidget {
  const ConquistasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.canPop() ? context.pop() : context.go('/'),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.textPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Conquistas',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            statsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (stats) {
                final unlocked = achievementCatalog
                    .where(
                      (achievement) => isAchievementUnlocked(
                        achievement,
                        totalQuizzes: stats.totalQuizzes,
                        streak: stats.streak,
                        level: stats.level,
                        xp: stats.xp,
                      ),
                    )
                    .toList();
                final totalXp = unlocked.fold<int>(
                  0,
                  (sum, achievement) => sum + achievement.xpReward,
                );

                return Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Row(
                    children: [
                      _ChipLabel(
                        label:
                            '${unlocked.length}/${achievementCatalog.length} desbloqueadas',
                      ),
                      const SizedBox(width: 8),
                      _ChipLabel(
                        label: '$totalXp XP',
                        textColor: AppColors.xpGold,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: statsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (_, __) => const Center(
                  child: Text(
                    'Erro ao carregar conquistas',
                    style: TextStyle(color: AppColors.accent),
                  ),
                ),
                data: (stats) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                    child: Column(
                      children: achievementCatalog.asMap().entries.map((entry) {
                        final achievement = entry.value;
                        final unlocked = isAchievementUnlocked(
                          achievement,
                          totalQuizzes: stats.totalQuizzes,
                          streak: stats.streak,
                          level: stats.level,
                          xp: stats.xp,
                        );
                        return _AchievementCard(
                          achievement: achievement,
                          isUnlocked: unlocked,
                          index: entry.key,
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({
    required this.label,
    this.textColor = AppColors.textMuted,
  });

  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.achievement,
    required this.isUnlocked,
    required this.index,
  });

  final AchievementDefinition achievement;
  final bool isUnlocked;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: isUnlocked ? AppColors.primary : AppColors.border,
          width: isUnlocked ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Opacity(
        opacity: isUnlocked ? 1.0 : 0.5,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: isUnlocked
                    ? Text(
                        achievement.emoji,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : const Icon(
                        Icons.lock_rounded,
                        color: AppColors.textMuted,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    achievement.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    achievement.description,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '+${achievement.xpReward} XP',
                style: const TextStyle(
                  color: AppColors.xpGold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate(delay: (index * 50).ms).fadeIn(duration: 300.ms).slideX(begin: 0.05);
  }
}
