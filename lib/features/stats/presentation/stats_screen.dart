import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/user_provider.dart';

/// Meta diária padrão de questões. Futuramente pode vir de UserSettings.
const kDefaultDailyGoal = 20;

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  static const int _dailyGoal = kDefaultDailyGoal;

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
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Estatísticas',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: statsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (_, __) => _StatsError(
                  onRetry: () => ref.read(userStatsNotifierProvider.notifier).refresh(),
                ),
                data: (stats) {
                  final dailyProgress =
                      (stats.todayQuizzes / _dailyGoal).clamp(0.0, 1.0);

                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () => ref.read(userStatsNotifierProvider.notifier).refresh(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                      children: [
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.1,
                          children: [
                            _MetricCard(
                              title: 'XP total',
                              value: '${stats.xp}',
                              suffix: 'XP',
                              color: AppColors.xpGold,
                              index: 0,
                            ),
                            _MetricCard(
                              title: 'Nivel',
                              value: '${stats.level}',
                              suffix: stats.levelLabel,
                              color: AppColors.levelPurple,
                              index: 1,
                            ),
                            _MetricCard(
                              title: 'Streak',
                              value: '${stats.streak}',
                              suffix: 'dias',
                              color: AppColors.streakOrange,
                              index: 2,
                            ),
                            _MetricCard(
                              title: 'Questões',
                              value: '${stats.totalQuizzes}',
                              suffix: 'total',
                              color: AppColors.success,
                              index: 3,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const _SectionTitle(title: 'Meta diária'),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Progresso do dia',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${stats.todayQuizzes}/$_dailyGoal',
                                    style: const TextStyle(
                                      color: AppColors.xpGold,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: dailyProgress,
                                  minHeight: 8,
                                  backgroundColor: AppColors.surface2,
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _InfoPill(
                                    label: 'Acertos hoje',
                                    value: '${stats.todayCorrect}',
                                  ),
                                  _InfoPill(
                                    label: 'XP hoje',
                                    value: '${stats.todayXp}',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.05),
                        const SizedBox(height: 20),
                        const _SectionTitle(title: 'Desempenho'),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Taxa de acerto',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    stats.taxaAcerto != null
                                        ? '${stats.taxaAcerto!.toStringAsFixed(1)}%'
                                        : 'Sem dados',
                                    style: TextStyle(
                                      color: stats.taxaAcerto != null
                                          ? (stats.taxaAcerto! >= 70
                                              ? AppColors.success
                                              : AppColors.accent)
                                          : AppColors.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Flashcards hoje',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${stats.flashcardsToday}',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.05),
                        const SizedBox(height: 20),
                        const _SectionTitle(title: 'Feedback'),
                        const SizedBox(height: 8),
                        _FeedbackCard(stats: stats),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: () => context.push('/conquistas'),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Text(
                                'Ver conquistas',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ).animate(delay: 350.ms).fadeIn().slideY(begin: 0.1),
                        const SizedBox(height: 10),
                        // ── Botão de histórico ───────────────────────────
                        GestureDetector(
                          onTap: () => context.push('/history'),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  color: AppColors.textSecondary,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Ver histórico de atividades',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).animate(delay: 380.ms).fadeIn().slideY(begin: 0.1),
                      ],
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

class _StatsError extends StatelessWidget {
  const _StatsError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Não foi possível carregar as estatísticas.',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Puxe para atualizar ou tente novamente agora.',
              style: TextStyle(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () => onRetry(),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    late final String message;

    if (stats.streak >= 7) {
      message = 'Excelente ritmo. Ja vale subir a dificuldade.';
    } else if (stats.todayQuizzes >= 10) {
      message = 'Bom volume hoje. Feche o dia com uma revisao curta.';
    } else if (stats.taxaAcerto != null && stats.taxaAcerto! < 50) {
      message = 'Sua taxa caiu. Revise fundamentos antes do proximo quiz.';
    } else {
      message = 'Consistência vence intensidade. Mantenha o estudo diário.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.05);
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.color,
    required this.index,
    this.suffix,
  });

  final String title;
  final String value;
  final String? suffix;
  final Color color;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (suffix != null && suffix!.isNotEmpty)
                Text(
                  suffix!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    ).animate(delay: (index * 80).ms).fadeIn(duration: 300.ms).slideY(begin: 0.05);
  }
}
