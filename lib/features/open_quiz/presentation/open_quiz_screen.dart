import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/exceptions/premium_limit_exception.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/library/domain/library_model.dart';
import '../../../features/profile/presentation/premium_upsell_dialog.dart';
import '../../../shared/providers/stats_provider.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/library_source_selector.dart';
import '../application/open_quiz_coordinator.dart';
import '../domain/open_quiz_model.dart';

/// Estados da tela de Quiz Dissertativo.
enum _OpenQuizPhase { config, answering, result }

/// Tela principal do Quiz Dissertativo (Open Quiz).
///
/// Implementa 3 fases:
/// 1. Config: selecionar tema e dificuldade, gerar pergunta
/// 2. Answering: responder a pergunta dissertativa
/// 3. Result: visualizar nota, critérios e feedback
class OpenQuizScreen extends ConsumerStatefulWidget {
  const OpenQuizScreen({super.key});

  @override
  ConsumerState<OpenQuizScreen> createState() => _OpenQuizScreenState();
}

class _OpenQuizScreenState extends ConsumerState<OpenQuizScreen> {
  late TextEditingController _temaCtrl;
  late TextEditingController _answerCtrl;

  String _difficulty = 'intermediario';
  _OpenQuizPhase _phase = _OpenQuizPhase.config;
  bool _loading = false;

  bool _useLibrary = false;
  LibraryFile? _selectedLibraryFile;

  OpenQuestion? _currentQuestion;
  OpenGrade? _currentGrade;

  @override
  void initState() {
    super.initState();
    _temaCtrl = TextEditingController();
    _answerCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _temaCtrl.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  /// Gera uma questao dissertativa.
  Future<void> _generateQuestion() async {
    setState(() => _loading = true);
    try {
      final question =
          await ref.read(openQuizCoordinatorProvider).generateQuestion(
                useLibrary: _useLibrary,
                tema: _temaCtrl.text,
                difficulty: _difficulty,
                selectedLibraryFile: _selectedLibraryFile,
              );
      if (mounted) {
        setState(() {
          _currentQuestion = question;
          _phase = _OpenQuizPhase.answering;
          _answerCtrl.clear();
        });
      }
    } on PremiumLimitException catch (_) {
      if (mounted) await showPremiumUpsell(context);
    } catch (e) {
      if (mounted) {
        final message = userVisibleErrorMessage(
          e,
          fallback: 'Não foi possível gerar a questão. Tente novamente.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Corrige a resposta do aluno.
  Future<void> _gradeAnswer() async {
    if (_currentQuestion == null) return;
    setState(() => _loading = true);
    try {
      final grade = await ref.read(openQuizCoordinatorProvider).gradeAnswer(
            question: _currentQuestion!,
            answer: _answerCtrl.text,
          );
      if (mounted) {
        setState(() {
          _currentGrade = grade;
          _phase = _OpenQuizPhase.result;
        });
      }
    } catch (e) {
      if (mounted) {
        final message = userVisibleErrorMessage(
          e,
          fallback: 'Não foi possível corrigir a resposta. Tente novamente.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Volta para a fase de configuracao.
  void _resetToConfig() {
    setState(() {
      _phase = _OpenQuizPhase.config;
      _currentQuestion = null;
      _currentGrade = null;
      _answerCtrl.clear();
      _temaCtrl.clear();
      _selectedLibraryFile = null;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                    onTap: () {
                      if (_phase == _OpenQuizPhase.config) {
                        context.go('/');
                      } else {
                        _resetToConfig();
                      }
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          '←',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '✍️ Quiz Dissertativo',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  const _OpenQuizQuotaBadge(),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // ── Content ──────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói o conteúdo baseado na fase atual.
  Widget _buildContent() {
    return switch (_phase) {
      _OpenQuizPhase.config => _buildConfigPhase(),
      _OpenQuizPhase.answering => _buildAnsweringPhase(),
      _OpenQuizPhase.result => _buildResultPhase(),
    };
  }

  /// Fase 1: Configuração (selecionar tema e dificuldade).
  Widget _buildConfigPhase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card informativo
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Text(
            'Responda com suas próprias palavras. '
            'A IA avalia sua resposta.\n'
            'Free: 1 questão dissertativa por semana. Premium: ilimitado.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Fonte da Dissertativa
        _SectionLabel('Fonte da Pergunta'),
        const SizedBox(height: 10),
        LibrarySourceSelector(
          useLibrary: _useLibrary,
          selectedFile: _selectedLibraryFile,
          onModeChanged: (v) => setState(() {
            _useLibrary = v;
            _selectedLibraryFile = null;
          }),
          onFileSelected: (f) => setState(() => _selectedLibraryFile = f),
          manualChild: TextFormField(
            controller: _temaCtrl,
            decoration: const InputDecoration(
              hintText: 'Ex: Fotossíntese, Revolução Francesa…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Chips de dificuldade
        _SectionLabel('Dificuldade'),
        const SizedBox(height: 10),
        Row(
          children: ['facil', 'intermediario', 'dificil'].map((d) {
            final isSelected = _difficulty == d;
            final labels = {
              'facil': 'Fácil',
              'intermediario': 'Intermediário',
              'dificil': 'Difícil',
            };
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _difficulty = d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      labels[d]!,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textMuted,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 36),

        // Botão Gerar Pergunta
        AppButton(
          label: 'Gerar Pergunta',
          icon: Icons.auto_awesome_rounded,
          isLoading: _loading,
          onPressed: _generateQuestion,
        ),
      ].animate(interval: 80.ms).fadeIn().slideY(begin: 0.05, end: 0),
    );
  }

  /// Fase 2: Responder a pergunta.
  Widget _buildAnsweringPhase() {
    if (_currentQuestion == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Contexto da pergunta
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            _currentQuestion!.contexto,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Pergunta em destaque
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary, width: 2),
          ),
          child: Text(
            _currentQuestion!.pergunta,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Campo de resposta
        _SectionLabel('Sua Resposta'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _answerCtrl,
          minLines: 5,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: 'Escreva sua resposta aqui…',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),

        // Contador de palavras
        Text(
          '${_answerCtrl.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} palavras',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 24),

        // Botão Corrigir
        AppButton(
          label: 'Corrigir Resposta',
          icon: Icons.check_circle_outline,
          isLoading: _loading,
          onPressed: _gradeAnswer,
        ),
      ].animate(interval: 60.ms).fadeIn().slideY(begin: 0.05, end: 0),
    );
  }

  /// Fase 3: Resultado da correção.
  Widget _buildResultPhase() {
    if (_currentGrade == null) return const SizedBox();

    final grade = _currentGrade!;
    final isApproved = grade.nota >= 70;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Círculo da nota
        Center(
          child: Column(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isApproved
                        ? AppColors.successGradient
                        : LinearGradient(
                            colors: [
                              AppColors.error,
                              AppColors.error.withOpacity(0.7),
                            ],
                          ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isApproved ? AppColors.success : AppColors.error)
                                .withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${grade.nota}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isApproved ? 'Aprovado ✅' : 'Refazer 📚',
                style: TextStyle(
                  color: isApproved ? AppColors.success : AppColors.error,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Grid de critérios
        _SectionLabel('Critérios de Avaliação'),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _CriterioCard(
              label: 'Aderência',
              value: grade.criterios['aderencia'] ?? 0,
            ),
            _CriterioCard(
              label: 'Estrutura',
              value: grade.criterios['estrutura'] ?? 0,
            ),
            _CriterioCard(
              label: 'Clareza',
              value: grade.criterios['clareza'] ?? 0,
            ),
            _CriterioCard(
              label: 'Fundamentação',
              value: grade.criterios['fundamentacao'] ?? 0,
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Pontos Fortes
        if (grade.pontosForts.isNotEmpty) ...[
          _SectionLabel('Pontos Fortes'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: grade.pontosForts
                .map(
                  (p) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Text(
                      p,
                      style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Pontos a Melhorar
        if (grade.pontosMelhorar.isNotEmpty) ...[
          _SectionLabel('Pontos a Melhorar'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: grade.pontosMelhorar
                .map(
                  (p) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Text(
                      p,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Feedback
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            grade.feedback,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Botões de ação
        AppButton(
          label: 'Nova Dissertativa',
          icon: Icons.refresh_rounded,
          onPressed: _resetToConfig,
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => context.go('/'),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Text(
                'Voltar ao início',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ].animate(interval: 60.ms).fadeIn().slideY(begin: 0.05, end: 0),
    );
  }
}

/// Widget para exibir um critério com barra de progresso.
class _CriterioCard extends StatelessWidget {
  const _CriterioCard({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final percentage = (value / 100).clamp(0.0, 1.0);
    final color = percentage >= 0.7
        ? AppColors.success
        : percentage >= 0.5
            ? AppColors.warning
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge com a quota semanal de questões dissertativas (visível apenas para free).
class _OpenQuizQuotaBadge extends ConsumerWidget {
  const _OpenQuizQuotaBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsNotifierProvider);

    return statsAsync.maybeWhen(
      data: (stats) {
        if (stats.isPremium) return const SizedBox.shrink();
        final remaining = stats.openQuizRestanteSemana ?? -1;
        final limit = stats.openQuizLimiteSemana ?? -1;
        if (remaining < 0 || limit < 0) return const SizedBox.shrink();

        final isExhausted = remaining == 0;
        return GestureDetector(
          onTap: () => showPremiumUpsell(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isExhausted
                  ? AppColors.error.withOpacity(0.12)
                  : AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isExhausted
                    ? AppColors.error.withOpacity(0.4)
                    : AppColors.primary.withOpacity(0.3),
              ),
            ),
            child: Text(
              isExhausted ? 'Limite semanal' : '$remaining/$limit esta semana',
              style: TextStyle(
                color: isExhausted ? AppColors.error : AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Widget de label de seção reutilizável.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: AppColors.textSecondary),
    );
  }
}
