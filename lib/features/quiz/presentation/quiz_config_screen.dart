import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/exceptions/premium_limit_exception.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/error_notebook/providers/error_notebook_provider.dart';
import '../../../features/library/domain/library_model.dart';
import '../../../features/profile/presentation/premium_upsell_dialog.dart';
import '../../../shared/providers/stats_provider.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/library_source_selector.dart';
import '../../../shared/widgets/quantity_stepper.dart';
import '../../settings/providers/settings_provider.dart';
import '../application/quiz_generation_coordinator.dart';
import 'quiz_session_screen.dart' show QuizGenerationParams;

class QuizConfigScreen extends ConsumerStatefulWidget {
  const QuizConfigScreen({super.key});

  @override
  ConsumerState<QuizConfigScreen> createState() => _QuizConfigScreenState();
}

class _QuizConfigScreenState extends ConsumerState<QuizConfigScreen> {
  final _topicCtrl = TextEditingController();
  String _difficulty = 'medium';
  int _quantity = 10;
  String _provider = 'groq';
  bool _loading = false;
  bool _infiniteMode = false;

  bool _useLibrary = false;
  LibraryFile? _selectedLibraryFile;
  bool _clearingMemory = false;

  final _difficulties = [
    (
      key: 'easy',
      label: 'Fácil',
      icon: Icons.eco_rounded,
      color: AppColors.success
    ),
    (
      key: 'medium',
      label: 'Médio',
      icon: Icons.bolt_rounded,
      color: AppColors.primary
    ),
    (
      key: 'hard',
      label: 'Difícil',
      icon: Icons.local_fire_department_rounded,
      color: AppColors.error
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
      final tema = extra?['tema'] as String?;
      if (tema != null && _topicCtrl.text.isEmpty) {
        setState(() => _topicCtrl.text = tema);
      }
    });
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedProvider() async {
    final saved = await ref.read(aiProviderSettingProvider.future);
    if (mounted) {
      setState(() => _provider = saved);
    }
  }

  Future<void> _pickLibraryFile() async {
    HapticFeedback.selectionClick();
    final selected = await showLibraryFilePickerModal(context);
    if (selected != null && mounted) {
      setState(() {
        _selectedLibraryFile = selected;
        _useLibrary = true;
        _topicCtrl.text = selected.nome;
      });
    }
  }

  void _clearSelectedLibraryFile() {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedLibraryFile = null;
      _useLibrary = false;
      _topicCtrl.clear();
    });
  }

  Future<void> _start() async {
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    try {
      final result = await ref.read(quizGenerationCoordinatorProvider).generate(
            useLibrary: _useLibrary,
            topic: _topicCtrl.text,
            difficulty: _difficulty,
            quantity: _quantity,
            infiniteMode: _infiniteMode,
            preferredProvider: _provider,
            selectedLibraryFile: _selectedLibraryFile,
          );

      if (!mounted) return;
      context.goNamed('quizSession', extra: {
        'questions': result.questions,
        if (_infiniteMode)
          'generationParams': QuizGenerationParams(
            topic: result.topic,
            difficulty: result.difficulty,
            aiProvider: result.aiProvider,
            conteudo: result.context,
          ),
        'infiniteMode': result.infiniteMode,
      });
    } on PremiumLimitException catch (_) {
      if (mounted) await showPremiumUpsell(context);
    } catch (e) {
      if (!mounted) return;
      final message = userVisibleErrorMessage(
        e,
        fallback: 'Não foi possível gerar as questões. Tente novamente.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearMemory() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Limpar histórico deste tema?'),
            content: const Text(
              'Isso permitirá que você receba perguntas anteriores novamente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Limpar'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() => _clearingMemory = true);
    try {
      await ref.read(quizGenerationCoordinatorProvider).clearSeenQuestions(
            useLibrary: _useLibrary,
            topic: _topicCtrl.text,
            selectedLibraryFile: _selectedLibraryFile,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Memória de questões limpa com sucesso!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao limpar memória: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _clearingMemory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(userStatsNotifierProvider).valueOrNull;
    final isPremium = stats?.isPremium ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
      body: SafeArea(
        child: Column(
          children: [
            // Header Principal de Alto Impacto
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/'),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.textPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Novo Desafio',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Qual assunto você quer dominar hoje?',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _QuizQuotaBadge(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cartão Unificado de Escolha de Assunto & Biblioteca
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const _SectionLabel('O QUE VAMOS ESTUDAR?'),
                              GestureDetector(
                                onTap: _pickLibraryFile,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.primary.withOpacity(0.3),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.collections_bookmark_rounded,
                                        color: AppColors.primary,
                                        size: 13,
                                      ),
                                      SizedBox(width: 5),
                                      Text(
                                        'Biblioteca',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_selectedLibraryFile != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.description_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedLibraryFile!.nome,
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const Text(
                                          'Gerando quiz baseado neste resumo',
                                          style: TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _clearSelectedLibraryFile,
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: AppColors.textMuted,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ] else ...[
                            TextFormField(
                              controller: _topicCtrl,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Ex: História do Brasil, Genética, Álgebra...',
                                hintStyle: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  color: AppColors.primary,
                                ),
                                suffixIcon: _topicCtrl.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded,
                                            size: 18),
                                        onPressed: () =>
                                            setState(() => _topicCtrl.clear()),
                                      )
                                    : null,
                                filled: true,
                                fillColor: AppColors.surface2,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _PersonalizedTopicChips(
                              onTopicSelected: (topic) => setState(() {
                                _selectedLibraryFile = null;
                                _useLibrary = false;
                                _topicCtrl.text = topic;
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Dificuldade (Pills modernas)
                    const _SectionLabel('NÍVEL DE DIFICULDADE'),
                    const SizedBox(height: 8),
                    Row(
                      children: _difficulties.map((d) {
                        final isSelected = _difficulty == d.key;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _difficulty = d.key);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? d.color.withOpacity(0.15)
                                    : AppColors.surface2,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color:
                                      isSelected ? d.color : AppColors.border,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    d.icon,
                                    size: 16,
                                    color: isSelected
                                        ? d.color
                                        : AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    d.label,
                                    style: TextStyle(
                                      color: isSelected
                                          ? d.color
                                          : AppColors.textMuted,
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // Tamanho da Sessão (Seletor Numeral Direto)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _SectionLabel('QUANTIDADE DE QUESTÕES'),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isPremium
                                ? AppColors.xpGold.withOpacity(0.12)
                                : AppColors.surface2,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isPremium
                                  ? AppColors.xpGold.withOpacity(0.4)
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPremium
                                    ? Icons.bolt_rounded
                                    : Icons.lock_outline_rounded,
                                size: 12,
                                color: isPremium
                                    ? AppColors.xpGold
                                    : AppColors.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isPremium
                                    ? 'Premium: Ilimitado'
                                    : 'Grátis: Máx. 10',
                                style: TextStyle(
                                  color: isPremium
                                      ? AppColors.xpGold
                                      : AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    QuantityStepper(
                      quantity: _quantity,
                      isPremium: isPremium,
                      infiniteMode: _infiniteMode,
                      onChanged: (newQ) => setState(() => _quantity = newQ),
                    ),

                    const SizedBox(height: 16),

                    // Modo Infinito Card
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (!_infiniteMode) {
                          final stats =
                              ref.read(userStatsNotifierProvider).valueOrNull;
                          if (stats == null || !stats.isPremium) {
                            showPremiumUpsell(context);
                            return;
                          }
                        }
                        setState(() => _infiniteMode = !_infiniteMode);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _infiniteMode
                              ? AppColors.primary.withOpacity(0.12)
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _infiniteMode
                                ? AppColors.primary
                                : AppColors.border,
                            width: _infiniteMode ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _infiniteMode
                                    ? AppColors.primary.withOpacity(0.2)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  '∞',
                                  style: TextStyle(
                                    color: _infiniteMode
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'Treino Infinito',
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.xpGold
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'PREMIUM',
                                          style: TextStyle(
                                            color: AppColors.xpGold,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Gera perguntas contínuas sem limite de quantidade.',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _infiniteMode,
                              onChanged: (v) {
                                if (v) {
                                  final stats = ref
                                      .read(userStatsNotifierProvider)
                                      .valueOrNull;
                                  if (stats == null || !stats.isPremium) {
                                    showPremiumUpsell(context);
                                    return;
                                  }
                                }
                                setState(() => _infiniteMode = v);
                              },
                              activeColor: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Botão Principal de Iniciar
                    AppButton(
                      label: _infiniteMode
                          ? 'Iniciar Treino Infinito ⚡'
                          : 'Iniciar Quiz ⚡',
                      icon: _infiniteMode
                          ? Icons.all_inclusive_rounded
                          : Icons.bolt_rounded,
                      isLoading: _loading,
                      onPressed: _start,
                    ),

                    const SizedBox(height: 12),

                    // Limpar memória de histórico
                    Center(
                      child: GestureDetector(
                        onTap: _clearingMemory ? null : _clearMemory,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.refresh_rounded,
                                color: AppColors.textMuted,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _clearingMemory
                                    ? 'Limpar memória...'
                                    : 'Resetar histórico de questões deste tema',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]
                      .animate(interval: 50.ms)
                      .fadeIn()
                      .slideY(begin: 0.04, end: 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _QuizQuotaBadge extends ConsumerWidget {
  const _QuizQuotaBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsNotifierProvider);

    return statsAsync.maybeWhen(
      data: (stats) {
        if (stats.isPremium) return const SizedBox.shrink();
        final remaining = stats.quizRestante ?? -1;
        final limit = stats.quizLimite ?? -1;
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
              isExhausted ? 'Limite atingido' : '$remaining/$limit hoje',
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

class _PersonalizedTopicChips extends ConsumerWidget {
  const _PersonalizedTopicChips({required this.onTopicSelected});

  final ValueChanged<String> onTopicSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errorState = ref.watch(errorNotebookNotifierProvider);

    final List<({String label, String topic, IconData icon, Color color})>
        suggestions = [];

    // 1. Tópicos do Caderno de Erros (se houver)
    errorState.whenData((errors) {
      if (errors.isNotEmpty) {
        final topics = errors
            .map((e) => e.topic)
            .where((t) => t.isNotEmpty && t != 'Geral')
            .toSet()
            .take(2);
        for (final t in topics) {
          suggestions.add((
            label: '⚠️ Revisar: $t',
            topic: t,
            icon: Icons.warning_amber_rounded,
            color: AppColors.error,
          ));
        }
      }
    });

    // 2. Fallbacks populares do ENEM se houver espaço
    final fallbacks = [
      (
        label: '🧬 Biologia',
        topic: 'Biologia: Fotossíntese e Genética',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.success
      ),
      (
        label: '📜 História',
        topic: 'História do Brasil',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.xpGold
      ),
      (
        label: '📐 Matemática',
        topic: 'Matemática e Geometria',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.accent
      ),
      (
        label: '🧪 Química',
        topic: 'Química Geral',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.primaryLight
      ),
    ];

    for (final fb in fallbacks) {
      if (suggestions.length >= 4) break;
      if (!suggestions.any((s) => s.topic == fb.topic)) {
        suggestions.add((
          label: fb.label,
          topic: fb.topic,
          icon: fb.icon,
          color: fb.color,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sugestões para seu perfil:',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: suggestions.map((item) {
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTopicSelected(item.topic);
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: item.color.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, color: item.color, size: 12),
                      const SizedBox(width: 5),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: item.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
