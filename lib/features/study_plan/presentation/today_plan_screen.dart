import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../quiz/domain/question_model.dart';
import '../application/study_plan_coordinator.dart';
import '../application/study_plan_quiz_request.dart';
import '../data/study_plan_repository.dart';
import '../domain/study_plan_model.dart';

part 'today_plan_sections.dart';

class TodayPlanScreen extends ConsumerStatefulWidget {
  const TodayPlanScreen({super.key});

  @override
  ConsumerState<TodayPlanScreen> createState() => _TodayPlanScreenState();
}

class _TodayPlanScreenState extends ConsumerState<TodayPlanScreen> {
  bool _loadingDocument = false;

  String _formatDate(DateTime date) {
    const days = [
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];
    const months = [
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];
    final dayName = days[date.weekday - 1];
    final monthName = months[date.month - 1];
    return '$dayName, ${date.day} de $monthName';
  }

  void _showPlanSelector(List<StudyPlan> plans, String activeId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Seus Planos de Estudo',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: plans.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: AppColors.border, height: 1),
                itemBuilder: (ctx, i) {
                  final plan = plans[i];
                  final isSelected = plan.id == activeId;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? AppColors.primary.withOpacity(0.2)
                          : AppColors.surface,
                      child: Icon(
                        Icons.description_rounded,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                    ),
                    title: Text(
                      plan.title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '${(plan.totalProgress * 100).toInt()}% concluído • ${plan.items.length} sessões',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded,
                            color: AppColors.primary)
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ref
                          .read(studyPlanCoordinatorProvider)
                          .setActivePlan(plan.id);
                      ref.invalidate(activePlanProvider);
                      ref.invalidate(allPlansProvider);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Criar Novo Plano',
              icon: Icons.add_rounded,
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/study-plan');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startQuizForSession(StudyPlan plan, StudyPlanItem session) {
    context.pushNamed('quizSession', extra: {
      'questions': const <Question>[],
      'generationParams': studyPlanQuizRequest(plan, session),
      'infiniteMode': false,
    });
  }

  Future<void> _readMaterialForSession(StudyPlanItem session) async {
    if (session.sourceDocumentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum documento PDF vinculado a esta sessão.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _loadingDocument = true);
    try {
      final docId = session.sourceDocumentIds.first;
      final content =
          await ref.read(studyPlanRepositoryProvider).getDocumentContent(docId);
      final doc =
          await ref.read(studyPlanRepositoryProvider).getDocument(docId);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        doc.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(color: AppColors.border),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Text(
                      content.isNotEmpty ? content : 'Conteúdo indisponível.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível carregar o documento.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingDocument = false);
    }
  }

  Future<void> _rescheduleSession(StudyPlan plan, StudyPlanItem session) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            surface: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      final dateStr = picked.toIso8601String().substring(0, 10);
      await ref.read(studyPlanCoordinatorProvider).rescheduleSession(
            planId: plan.id,
            sessionId: session.sessionId,
            newScheduledDate: dateStr,
          );
      ref.invalidate(activePlanProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePlanAsync = ref.watch(activePlanProvider);
    final allPlansAsync = ref.watch(allPlansProvider);
    final today = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text(
          'Plano de Hoje',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          allPlansAsync.when(
            data: (plans) {
              if (plans.length <= 1) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.swap_horiz_rounded,
                    color: AppColors.primary),
                tooltip: 'Trocar Plano',
                onPressed: () {
                  final activeId = activePlanAsync.valueOrNull?.id ?? '';
                  _showPlanSelector(plans, activeId);
                },
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: activePlanAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Erro ao carregar o plano de estudos.',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Tentar Novamente',
                    onPressed: () => ref.invalidate(activePlanProvider),
                  ),
                ],
              ),
            ),
          ),
          data: (plan) {
            if (plan == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.note_alt_outlined,
                            color: AppColors.primary, size: 48),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Nenhum plano de estudos ativo',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Crie um plano baseado no seu edital para organizar seus estudos diários.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      AppButton(
                        label: 'Criar Plano de Estudos',
                        icon: Icons.add_rounded,
                        onPressed: () => context.push('/study-plan'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final todaySessions = plan.getSessionsForDate(today);
            final overdueSessions = plan.getOverduePendingSessions(today);
            final completedCount =
                todaySessions.where((s) => s.isCompleted).length;
            final totalCount = todaySessions.length;
            final remainingMinutes = plan.getTodayRemainingMinutes(today);
            final progressRatio =
                totalCount > 0 ? completedCount / totalCount : 0.0;

            final firstPending = todaySessions.firstWhere(
              (s) => !s.isCompleted,
              orElse: () => todaySessions.isNotEmpty
                  ? todaySessions.first
                  : plan.items.first,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Data e Concurso
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: AppColors.primary, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        _formatDate(today),
                        style: const TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plan.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Card de Resumo Diário
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.surface, AppColors.surface2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Progresso diário',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '$completedCount de $totalCount sessões',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(100),
                          child: LinearProgressIndicator(
                            value: progressRatio,
                            minHeight: 8,
                            backgroundColor: AppColors.border,
                            valueColor:
                                const AlwaysStoppedAnimation(AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined,
                                color: AppColors.textMuted, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              remainingMinutes > 0
                                  ? 'Tempo restante: ~$remainingMinutes minutos'
                                  : 'Todas as sessões de hoje foram concluídas!',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (totalCount > 0 && completedCount < totalCount) ...[
                          const SizedBox(height: 16),
                          AppButton(
                            label: 'Iniciar sessão recomendada',
                            icon: Icons.play_arrow_rounded,
                            onPressed: _loadingDocument
                                ? null
                                : () {
                                    if (firstPending.recommendedMode ==
                                        StudyRecommendedMode.reading) {
                                      _readMaterialForSession(firstPending);
                                    } else {
                                      _startQuizForSession(plan, firstPending);
                                    }
                                  },
                          ),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(),

                  // Banner de Sessões Atrasadas (se houver)
                  if (overdueSessions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${overdueSessions.length} sessões atrasadas',
                                  style: const TextStyle(
                                    color: AppColors.error,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Text(
                                  'De dias anteriores que ainda não foram concluídas.',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await ref
                                  .read(studyPlanCoordinatorProvider)
                                  .carryOverOverdueSessions(
                                    planId: plan.id,
                                    customDate: today,
                                  );
                              ref.invalidate(activePlanProvider);
                            },
                            child: const Text(
                              'Puxar p/ hoje',
                              style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  const Text(
                    'MATÉRIAS DE HOJE',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (todaySessions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.event_available_rounded,
                              color: AppColors.success, size: 36),
                          const SizedBox(height: 12),
                          const Text(
                            'Nenhum estudo programado para hoje',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Aproveite para revisar conteúdos ou adiantar próximas sessões.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.style_rounded, size: 16),
                                label: const Text('Fazer Quiz'),
                                onPressed: () => context.go('/quiz'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side:
                                      const BorderSide(color: AppColors.border),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: todaySessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, idx) {
                        final session = todaySessions[idx];
                        return _StudySessionCard(
                          session: session,
                          isLoading: _loadingDocument,
                          onToggleComplete: () async {
                            final targetIndex = plan.items.indexWhere(
                              (i) =>
                                  i.effectiveSessionId ==
                                  session.effectiveSessionId,
                            );
                            if (targetIndex >= 0) {
                              await ref
                                  .read(studyPlanCoordinatorProvider)
                                  .toggleItem(
                                    plan: plan,
                                    index: targetIndex,
                                  );
                              ref.invalidate(activePlanProvider);
                            }
                          },
                          onStartQuiz: () =>
                              _startQuizForSession(plan, session),
                          onReadMaterial: () =>
                              _readMaterialForSession(session),
                          onReschedule: () => _rescheduleSession(plan, session),
                        );
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
