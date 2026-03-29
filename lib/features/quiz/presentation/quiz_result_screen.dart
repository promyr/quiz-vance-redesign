import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/history/data/history_repository.dart';
import '../../../shared/providers/gamification_provider.dart';
import '../../../shared/providers/user_provider.dart';
import '../../../shared/widgets/achievement_toast.dart';
import '../../../shared/widgets/sync_status_card.dart';
import '../data/quiz_repository.dart';
import '../domain/question_model.dart';

class QuizResultScreen extends ConsumerStatefulWidget {
  const QuizResultScreen({super.key, required this.result});

  final QuizResult result;

  @override
  ConsumerState<QuizResultScreen> createState() => _QuizResultScreenState();
}

class _QuizResultScreenState extends ConsumerState<QuizResultScreen> {
  ProviderSubscription<AsyncValue<GamificationState>>?
      _gamificationSubscription;
  SyncStatusState _syncState = SyncStatusState.syncing;
  String _syncMessage =
      'Estamos salvando seu resultado, atualizando estatísticas e histórico.';

  @override
  void initState() {
    super.initState();
    _gamificationSubscription =
        ref.listenManual(gamificationProvider, _onGamificationChanged);
    unawaited(_persistResult());
  }

  @override
  void dispose() {
    _gamificationSubscription?.close();
    super.dispose();
  }

  Future<void> _persistResult() async {
    final result = widget.result;
    if (mounted) {
      setState(() {
        _syncState = SyncStatusState.syncing;
        _syncMessage =
            'Estamos salvando seu resultado, atualizando estatísticas e histórico.';
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
      await ref.read(quizRepositoryProvider).submit(
            sessionId: result.sessionId,
            answers: result.answers
                .map(
                  (answer) => {
                    'question_id': answer.question.id,
                    'selected_option_id': answer.selectedOptionId,
                    'is_correct': answer.isCorrect,
                  },
                )
                .toList(),
            timeTaken: result.timeTaken,
            total: result.total,
            correct: result.correct,
            xpEarned: result.xpEarned,
            topic: result.topic,
          );
      await ref.read(userStatsNotifierProvider.notifier).refresh();
      ref.invalidate(activityHistoryProvider);

      if (!mounted) return;
      setState(() {
        _syncState = SyncStatusState.saved;
        _syncMessage =
            'Resultado salvo com sucesso. Estatísticas, quotas e histórico foram sincronizados.';
      });
    } catch (error) {
      debugPrint('Quiz submit error: $error');
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
    final pct = (result.accuracy * 100).round();
    final title = pct >= 80
        ? 'Quiz completo!'
        : pct >= 60
            ? 'Bom resultado!'
            : 'Continue treinando!';
    final accent = pct >= 80
        ? AppColors.success
        : pct >= 60
            ? AppColors.primary
            : AppColors.accent;

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
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
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
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${result.correct} de ${result.total} corretas',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
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
                    label: 'Erradas',
                    value: '${result.total - result.correct}',
                    color: AppColors.accent,
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
                      'Tempo total',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${result.timeTaken.inMinutes}m ${(result.timeTaken.inSeconds % 60).toString().padLeft(2, '0')}s',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ).animate(delay: 220.ms).fadeIn(),
              const SizedBox(height: 16),
              SyncStatusCard(
                state: _syncState,
                message: _syncMessage,
                onRetry: _syncState == SyncStatusState.pending
                    ? () => unawaited(_persistResult())
                    : null,
              ).animate(delay: 260.ms).fadeIn(),
              const SizedBox(height: 22),
              _PrimaryAction(
                label: 'Fazer outro quiz',
                onTap: () => context.go('/quiz'),
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
                fontSize: 22,
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
