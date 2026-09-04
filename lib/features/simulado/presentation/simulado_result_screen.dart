import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/history/data/history_repository.dart';
import '../../../features/quiz/domain/question_model.dart';
import '../../../shared/providers/gamification_provider.dart';
import '../../../shared/providers/user_provider.dart';
import '../../../shared/widgets/achievement_toast.dart';
import '../../../shared/widgets/sync_status_card.dart';
import '../data/simulado_repository.dart';
import '../domain/simulado_review.dart';

class SimuladoResultScreen extends ConsumerStatefulWidget {
  const SimuladoResultScreen({super.key, required this.result});

  final QuizResult? result;

  @override
  ConsumerState<SimuladoResultScreen> createState() =>
      _SimuladoResultScreenState();
}

class _SimuladoResultScreenState extends ConsumerState<SimuladoResultScreen> {
  ProviderSubscription<AsyncValue<GamificationState>>?
      _gamificationSubscription;
  SyncStatusState _syncState = SyncStatusState.syncing;
  String _syncMessage =
      'Estamos salvando o simulado, atualizando estatísticas e histórico.';

  @override
  void initState() {
    super.initState();
    _gamificationSubscription =
        ref.listenManual(gamificationProvider, _onGamificationChanged);
    if (widget.result != null) {
      unawaited(_persistResult(widget.result!));
    }
  }

  @override
  void dispose() {
    _gamificationSubscription?.close();
    super.dispose();
  }

  Future<void> _persistResult(QuizResult result) async {
    if (mounted) {
      setState(() {
        _syncState = SyncStatusState.syncing;
        _syncMessage =
            'Estamos salvando o simulado, atualizando estatísticas e histórico.';
      });
    }

    try {
      await ref.read(gamificationProvider.notifier).recordQuizCompletion(
            eventId: result.sessionId,
            xpEarned: result.xpEarned,
          );
    } catch (error) {
      debugPrint('Gamification error: $error');
    }

    try {
      await ref.read(simuladoRepositoryProvider).submitResult({
        'session_id': result.sessionId,
        'correct': result.correct,
        'total': result.total,
        'accuracy': result.accuracy,
        'xp_earned': result.xpEarned,
        'time_taken_seconds': result.timeTaken.inSeconds,
      });
      await ref.read(userStatsNotifierProvider.notifier).refresh();
      ref.invalidate(activityHistoryProvider);

      if (!mounted) return;
      setState(() {
        _syncState = SyncStatusState.saved;
        _syncMessage =
            'Simulado salvo com sucesso. Estatísticas, quotas e histórico foram sincronizados.';
      });
    } catch (error) {
      debugPrint('Simulado submit error: $error');
      if (!mounted) return;
      setState(() {
        _syncState = SyncStatusState.pending;
        _syncMessage =
            'O resultado ficou disponível nesta tela, mas o backend não confirmou a sincronização. Toque para tentar novamente.';
      });
    }
  }

  void _onGamificationChanged(
    AsyncValue<GamificationState>? _,
    AsyncValue<GamificationState> next,
  ) {
    next.whenData((state) {
      if (!mounted) return;
      if (state.justLeveledUp) {
        AchievementToast.showLevelUp(context, level: state.level);
      }
      if (state.justUnlockedAchievement && state.newAchievement != null) {
        AchievementToast.showAchievement(
          context,
          name: state.newAchievement!,
          xp: state.newAchievementXp,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    if (result == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/simulado');
      });
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final pct = (result.accuracy * 100).round();
    final topics = _topicStats(result.answers);
    final wrongAnswers = reviewableSimuladoAnswers(result);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => context.go('/'),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: pct >= 70
                      ? AppColors.successGradient
                      : AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pct >= 70 ? 'Aprovado!' : 'Continue estudando',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${result.correct} de ${result.total} corretas',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.05),
              const SizedBox(height: 18),
              Row(
                children: [
                  _StatCard(
                    label: 'Corretas',
                    value: '${result.correct}',
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 10),
                  _StatCard(
                    label: 'Tempo',
                    value:
                        '${result.timeTaken.inMinutes}m ${(result.timeTaken.inSeconds % 60).toString().padLeft(2, '0')}s',
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  _StatCard(
                    label: 'XP',
                    value: '+${result.xpEarned}',
                    color: AppColors.xpGold,
                  ),
                ],
              ).animate(delay: 150.ms).fadeIn(),
              const SizedBox(height: 16),
              SyncStatusCard(
                state: _syncState,
                message: _syncMessage,
                onRetry: _syncState == SyncStatusState.pending
                    ? () => unawaited(_persistResult(result))
                    : null,
              ).animate(delay: 200.ms).fadeIn(),
              if (topics.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Desempenho por topico',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 180,
                        child: BarChart(
                          BarChartData(
                            borderData: FlBorderData(show: false),
                            gridData: const FlGridData(show: false),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, _) {
                                    final index = value.toInt();
                                    if (index >= topics.length) {
                                      return const SizedBox.shrink();
                                    }
                                    final label = topics[index].topic;
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        label.length > 7
                                            ? '${label.substring(0, 7)}...'
                                            : label,
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 9,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            barGroups: topics.asMap().entries.map((entry) {
                              final stat = entry.value;
                              return BarChartGroupData(
                                x: entry.key,
                                barRods: [
                                  BarChartRodData(
                                    toY: stat.total.toDouble(),
                                    color: AppColors.border,
                                    width: 18,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  BarChartRodData(
                                    toY: stat.correct.toDouble(),
                                    gradient: stat.correctRate >= 0.7
                                        ? AppColors.successGradient
                                        : AppColors.primaryGradient,
                                    width: 18,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate(delay: 220.ms).fadeIn(),
              ],
              const SizedBox(height: 22),
              if (wrongAnswers.isNotEmpty) ...[
                _SecondaryAction(
                  label: 'Revisar erros (${wrongAnswers.length})',
                  onTap: () => context.pushNamed(
                    'simuladoReview',
                    extra: {'result': result},
                  ),
                ).animate(delay: 280.ms).fadeIn(),
                const SizedBox(height: 10),
              ],
              _PrimaryAction(
                label: 'Novo simulado',
                onTap: () => context.go('/simulado'),
              ).animate(delay: 300.ms).fadeIn(),
              const SizedBox(height: 10),
              _SecondaryAction(
                label: 'Voltar ao inicio',
                onTap: () => context.go('/'),
              ).animate(delay: 360.ms).fadeIn(),
            ],
          ),
        ),
      ),
    );
  }

  List<_TopicStat> _topicStats(List<QuestionAnswer> answers) {
    final map = <String, _TopicStat>{};
    for (final answer in answers) {
      final topic = answer.question.topic ?? 'Geral';
      map.putIfAbsent(topic, () => _TopicStat(topic: topic));
      map[topic]!.total++;
      if (answer.isCorrect) {
        map[topic]!.correct++;
      }
    }
    return map.values.toList();
  }
}

class _TopicStat {
  _TopicStat({required this.topic});

  final String topic;
  int total = 0;
  int correct = 0;

  double get correctRate => total == 0 ? 0 : correct / total;
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
