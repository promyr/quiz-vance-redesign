import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_error_message.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../application/study_plan_coordinator.dart';
import '../data/study_plan_repository.dart';
import '../domain/study_plan_model.dart';

enum _PlanPhase { config, viewing }

String formatStudyPlanDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');
  return '$day/$month/$year';
}

DateTime? parseStudyPlanDateOrNull(String raw) {
  final trimmed = raw.trim();
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(trimmed);
  if (match == null) return null;

  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) return null;

  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }

  return parsed;
}

class StudyPlanScreen extends ConsumerStatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  ConsumerState<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends ConsumerState<StudyPlanScreen> {
  late _PlanPhase _phase;
  StudyPlan? _plan;

  final _objectiveCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _topicsCtrl = TextEditingController();

  DateTime? _selectedExamDate;
  int _tempo = 30;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _phase = _PlanPhase.config;
    _loadActivePlan();
  }

  Future<void> _loadActivePlan() async {
    try {
      final plan = await ref.read(activePlanProvider.future);
      if (plan != null && mounted) {
        setState(() {
          _plan = plan;
          _phase = _PlanPhase.viewing;
        });
      }
    } catch (_) {
      // Continua em config se houver erro
    }
  }

  @override
  void dispose() {
    _objectiveCtrl.dispose();
    _dateCtrl.dispose();
    _topicsCtrl.dispose();
    super.dispose();
  }

  Future<void> _generatePlan() async {
    if (_objectiveCtrl.text.trim().isEmpty) {
      _showError('Informe seu objetivo de estudo');
      return;
    }

    setState(() => _loading = true);

    try {
      final plan = await ref.read(studyPlanCoordinatorProvider).generatePlan(
            objective: _objectiveCtrl.text,
            examDate: _dateCtrl.text,
            tempoDiario: _tempo,
            rawTopics: _topicsCtrl.text,
          );

      if (mounted) {
        setState(() {
          _plan = plan;
          _phase = _PlanPhase.viewing;
          _loading = false;
        });
        ref.invalidate(activePlanProvider);
      }
    } catch (e) {
      if (mounted) {
        _showError(
          userVisibleErrorMessage(
            e,
            fallback:
                'Não foi possível gerar o plano de estudos. Tente novamente.',
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  Future<void> _pickExamDate() async {
    final now = DateTime.now();
    final initialDate = _selectedExamDate ??
        parseStudyPlanDateOrNull(_dateCtrl.text) ??
        now.add(const Duration(days: 30));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 15),
      helpText: 'Selecionar data da prova',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _selectedExamDate = picked;
      _dateCtrl.text = formatStudyPlanDate(picked);
    });
  }

  void _clearExamDate() {
    setState(() {
      _selectedExamDate = null;
      _dateCtrl.clear();
    });
  }

  Future<void> _toggleItem(int index) async {
    if (_plan != null) {
      await ref.read(studyPlanCoordinatorProvider).toggleItem(
            plan: _plan!,
            index: index,
          );
      // Recarrega o plano para refletir as mudanças
      try {
        final updatedPlan = await ref.read(activePlanProvider.future);
        if (updatedPlan != null && mounted) {
          setState(() => _plan = updatedPlan);
        }
      } catch (_) {}
      // Invalida para atualizar providers
      ref.invalidate(activePlanProvider);
    }
  }

  Future<void> _generateNewPlan() async {
    setState(() {
      _phase = _PlanPhase.config;
      _objectiveCtrl.clear();
      _dateCtrl.clear();
      _topicsCtrl.clear();
      _selectedExamDate = null;
      _tempo = 30;
    });
  }

  void _goToQuiz() {
    context.goNamed('quizConfig');
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _PlanPhase.config) {
      return _buildConfigPhase();
    } else {
      return _buildViewingPhase();
    }
  }

  Widget _buildConfigPhase() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/'),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text('←',
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '📅 Plano de Estudo',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Botão para ver plano atual se existir
                    if (_plan != null) ...[
                      _OutlineButton(
                        label: 'Ver Plano Atual →',
                        onPressed: () =>
                            setState(() => _phase = _PlanPhase.viewing),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Objetivo
                    _SectionLabel('Objetivo de Estudo'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _objectiveCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Ex: Aprovação no TRT, ENEM 2026…',
                        prefixIcon: Icon(Icons.flag_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Data da Prova
                    _SectionLabel('Data da Prova (Opcional)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('studyPlanDateField'),
                      controller: _dateCtrl,
                      readOnly: true,
                      onTap: _pickExamDate,
                      decoration: const InputDecoration(
                        hintText: 'DD/MM/AAAA',
                        prefixIcon: Icon(Icons.calendar_today_rounded),
                      ).copyWith(
                        suffixIcon: _dateCtrl.text.trim().isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpar data',
                                onPressed: _clearExamDate,
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tempo Diário
                    _SectionLabel('Tempo diário: ${_tempo}min por dia'),
                    Slider(
                      value: _tempo.toDouble(),
                      min: 15,
                      max: 120,
                      divisions: 7,
                      label: '${_tempo}min',
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _tempo = v.round()),
                    ),
                    const SizedBox(height: 24),

                    // Tópicos
                    _SectionLabel('Tópicos (Opcional)'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _topicsCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Tópicos separados por vírgula',
                        prefixIcon: Icon(Icons.menu_book_rounded),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 36),

                    // Botão Gerar
                    AppButton(
                      label: 'Gerar Plano com IA ✨',
                      isLoading: _loading,
                      onPressed: _generatePlan,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewingPhase() {
    if (_plan == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: Text('Nenhum plano disponível',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }

    final plan = _plan!;
    final itemsConcluidos = plan.items.where((item) => item.concluido).length;
    final progressPct =
        plan.items.isEmpty ? 0.0 : itemsConcluidos / plan.items.length;

    // Agrupar itens por dia
    final itensPorDia = <String, List<StudyPlanItem>>{};
    for (final item in plan.items) {
      itensPorDia.putIfAbsent(item.dia, () => []).add(item);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/'),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text('←',
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '📅 ${plan.objetivo}',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Progresso
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$itemsConcluidos/${plan.items.length} itens concluídos',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progressPct,
                              minHeight: 6,
                              backgroundColor: AppColors.border,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.success),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Chip com data da prova
                    if (plan.dataProva != null && plan.dataProva!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Chip(
                          label: Text('📅 Prova: ${plan.dataProva}',
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 12)),
                          backgroundColor: AppColors.primary.withOpacity(0.15),
                          side: const BorderSide(
                              color: AppColors.primary, width: 1),
                        ),
                      ),

                    // Itens agrupados por dia
                    ...itensPorDia.entries.map((entry) {
                      final dia = entry.key;
                      final itens = entry.value;
                      final indexInicial = plan.items.indexOf(itens.first);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 12),
                            child: Text(
                              dia.toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          ...itens.asMap().entries.map((itemEntry) {
                            final relativeIndex = itemEntry.key;
                            final item = itemEntry.value;
                            final globalIndex = indexInicial + relativeIndex;

                            return _StudyItemCard(
                              item: item,
                              onToggle: () => _toggleItem(globalIndex),
                            );
                          }),
                        ],
                      );
                    }),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Botões inferiores ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  _OutlineButton(
                    label: 'Gerar Novo Plano',
                    onPressed: _generateNewPlan,
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Estudar Agora →',
                    onPressed: _goToQuiz,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card que representa um item do plano de estudo.
class _StudyItemCard extends StatelessWidget {
  const _StudyItemCard({
    required this.item,
    required this.onToggle,
  });

  final StudyPlanItem item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isPriority = item.prioridade == 1;

    return GestureDetector(
      onTap: onToggle,
      child: Opacity(
        opacity: item.concluido ? 0.5 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isPriority ? AppColors.accent : AppColors.border,
              width: isPriority ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Checkbox
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color:
                      item.concluido ? AppColors.success : AppColors.surface2,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color:
                        item.concluido ? AppColors.success : AppColors.border,
                  ),
                ),
                child: item.concluido
                    ? const Center(
                        child: Icon(Icons.check_rounded,
                            size: 12, color: AppColors.background),
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Conteúdo
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.tema,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.atividade,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Chips de duração
                    Chip(
                      label: Text('⏱ ${item.duracaoMin}min',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                      backgroundColor: AppColors.surface2,
                      side:
                          const BorderSide(color: AppColors.border, width: 0.5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label para seções.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary,
          ),
    );
  }
}

/// Botão com estilo outline.
class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
