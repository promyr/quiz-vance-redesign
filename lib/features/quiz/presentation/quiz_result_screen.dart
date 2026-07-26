import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/error_notebook/providers/error_notebook_provider.dart';
import '../../../features/history/data/history_repository.dart';
import '../providers/quiz_do_dia_provider.dart';
import '../../../shared/providers/gamification_provider.dart';
import '../../../shared/providers/user_provider.dart';
import '../../../shared/application/offline_sync_queue.dart';
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

  bool _showGabarito = false;

  @override
  void initState() {
    super.initState();
    _gamificationSubscription =
        ref.listenManual(gamificationProvider, _onGamificationChanged);
    unawaited(_persistResult());

    if ((widget.result.accuracy * 100).round() >= 80) {
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _gamificationSubscription?.close();
    super.dispose();
  }

  Future<void> _persistResult() async {
    final result = widget.result;

    final gamification = ref.read(gamificationProvider.notifier);
    final quizRepo = ref.read(quizRepositoryProvider);
    final userStatsNotifier = ref.read(userStatsNotifierProvider.notifier);
    final errorNotebook = ref.read(errorNotebookNotifierProvider.notifier);
    final dailyNotifier = ref.read(dailyChallengeNotifierProvider.notifier);

    if (mounted) {
      setState(() {
        _syncState = SyncStatusState.syncing;
        _syncMessage =
            'Salvando seu progresso e atualizando seu histórico de estudos...';
      });
    }

    try {
      final currentDaily = ref.read(dailyChallengeNotifierProvider).valueOrNull;
      if (currentDaily != null &&
          result.topic != null &&
          (result.topic == currentDaily.topic ||
              result.topic!.contains(currentDaily.topic))) {
        await dailyNotifier.markCompleted();
      }
    } catch (_) {}

    final wrongAnswers = result.answers.where((a) => !a.isCorrect).toList();
    if (wrongAnswers.isNotEmpty) {
      try {
        await errorNotebook.recordWrongQuestions(
          wrongAnswers: wrongAnswers,
          topic: result.topic ?? '',
        );
      } catch (error) {
        debugPrint('ErrorNotebook error: $error');
      }
    }

    try {
      await gamification.recordQuizCompletion(
        eventId: result.sessionId,
        xpEarned: result.xpEarned,
      );
    } catch (error) {
      debugPrint('Gamification error: $error');
    }

    try {
      await quizRepo.submit(
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
      await userStatsNotifier.refresh();
      try {
        ref.invalidate(activityHistoryProvider);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _syncState = SyncStatusState.saved;
        _syncMessage =
            'Resultado salvo! Seu progresso e histórico foram atualizados.';
      });
    } catch (error) {
      debugPrint('Quiz submit error: $error');
      var queued = false;
      try {
        await ref.read(offlineSyncQueueProvider).enqueueItem(
          type: 'quiz_result',
          idempotencyKey: result.sessionId,
          payload: {
            'session_id': result.sessionId,
            'answers': result.answers
                .map(
                  (answer) => {
                    'question_id': answer.question.id,
                    'selected_option_id': answer.selectedOptionId,
                    'is_correct': answer.isCorrect,
                  },
                )
                .toList(),
            'time_taken_seconds': result.timeTaken.inSeconds,
            'total': result.total,
            'correct': result.correct,
            'xp_earned': result.xpEarned,
            if (result.topic != null && result.topic!.isNotEmpty)
              'topic': result.topic,
          },
        );
        queued = true;
      } catch (queueError) {
        debugPrint('Quiz offline queue error: $queueError');
      }
      if (!mounted) return;
      setState(() {
        _syncState = SyncStatusState.pending;
        _syncMessage = queued
            ? 'Resultado salvo no seu aparelho! Sincronizaremos com a nuvem quando a conexão voltar.'
            : 'Não foi possível salvar o resultado. Tente novamente antes de sair.';
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
                    color: AppColors.error,
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

              // BOTÃO E SEÇÃO DE GABARITO & EXPLICAÇÕES (NOVO)
              if (result.answers.isNotEmpty) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => setState(() => _showGabarito = !_showGabarito),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.menu_book_rounded,
                          color: AppColors.primaryLight,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _showGabarito
                                ? 'Ocultar Gabarito e Explicações'
                                : 'Revisar Gabarito e Explicações (${result.answers.length})',
                            style: const TextStyle(
                              color: AppColors.primaryLight,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(
                          _showGabarito
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: AppColors.primaryLight,
                        ),
                      ],
                    ),
                  ),
                ).animate(delay: 280.ms).fadeIn(),
                if (_showGabarito) ...[
                  const SizedBox(height: 12),
                  ...result.answers.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final answer = entry.value;
                    final question = answer.question;
                    final isCorrect = answer.isCorrect;

                    QuizOption? selectedOpt;
                    try {
                      selectedOpt = question.options.firstWhere(
                        (o) => o.id == answer.selectedOptionId,
                      );
                    } catch (_) {}

                    QuizOption? correctOpt;
                    try {
                      correctOpt = question.options.firstWhere(
                        (o) => o.id == question.correctOptionId,
                      );
                    } catch (_) {}

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isCorrect
                              ? AppColors.success.withOpacity(0.4)
                              : AppColors.error.withOpacity(0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isCorrect
                                      ? AppColors.success.withOpacity(0.15)
                                      : AppColors.error.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Q$index • ${isCorrect ? "Correta" : "Incorreta"}',
                                  style: TextStyle(
                                    color: isCorrect
                                        ? AppColors.success
                                        : AppColors.error,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            question.text,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (!isCorrect && selectedOpt != null) ...[
                            Text(
                              'Sua resposta: ${selectedOpt.text}',
                              style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (correctOpt != null)
                            Text(
                              'Resposta correta: ${correctOpt.text}',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (question.explanation != null &&
                              question.explanation!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.lightbulb_outline_rounded,
                                    color: AppColors.xpGold,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      question.explanation!,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ],

              const SizedBox(height: 22),
              _PrimaryAction(
                label: 'Fazer outro quiz',
                onTap: () => context.go('/quiz'),
              ).animate(delay: 300.ms).fadeIn(),
              const SizedBox(height: 10),
              _SecondaryAction(
                label: 'Voltar ao início',
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
