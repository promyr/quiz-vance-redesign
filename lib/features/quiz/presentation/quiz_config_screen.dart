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
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/library_source_selector.dart';
import '../../settings/providers/settings_provider.dart';
import '../application/quiz_generation_coordinator.dart';
import 'quiz_session_screen.dart' show QuizGenerationParams;

/*
bool _isRetryableAiGenerationFailure(String message) {
  final normalized = message.trim().toLowerCase();
  if (normalized.isEmpty) return false;

  return normalized.contains('erro ao gerar') ||
      normalized.contains('nao foi possivel gerar') ||
      normalized.contains('tente novamente') ||
      normalized.contains('chave de api') ||
      normalized.contains('prove') ||
      normalized.contains('modelo') ||
      normalized.contains('autentic') ||
      normalized.contains('quota') ||
      normalized.contains('crédito') ||
      normalized.contains('credito');
}

List<String> _buildProviderFallbackOrder({
  required String preferredProvider,
  required AiGenerationConfigState config,
}) {
  final providers = <String>[
    if (config.geminiKey.trim().isNotEmpty) 'gemini',
    if (config.openaiKey.trim().isNotEmpty) 'openai',
    if (config.groqKey.trim().isNotEmpty) 'groq',
  ];

  if (providers.contains(preferredProvider)) {
    providers.remove(preferredProvider);
    providers.insert(0, preferredProvider);
  }

  return providers;
}

List<String?> _buildContextFallbackOrder({
  required bool useLibrary,
  required String? initialContext,
  required String? rawLibraryContent,
}) {
  if (!useLibrary || rawLibraryContent == null) {
    return [initialContext];
  }

  final candidates = <String?>[
    initialContext,
    sanitizeStudyMaterialForPrompt(rawLibraryContent, maxChars: 1400),
    sanitizeStudyMaterialForPrompt(rawLibraryContent, maxChars: 900),
  ];

  final deduped = <String?>[];
  for (final candidate in candidates) {
    final text = candidate?.trim();
    if (text == null || text.isEmpty) continue;
    if (deduped.contains(text)) continue;
    deduped.add(text);
  }

  return deduped.isEmpty ? [initialContext] : deduped;
}
*/

class QuizConfigScreen extends ConsumerStatefulWidget {
  const QuizConfigScreen({super.key});

  @override
  ConsumerState<QuizConfigScreen> createState() => _QuizConfigScreenState();
}

class _QuizConfigScreenState extends ConsumerState<QuizConfigScreen> {
  final _topicCtrl = TextEditingController();
  String _difficulty = 'medium';
  int _quantity = 10;
  String _provider = 'gemini';
  bool _loading = false;
  bool _infiniteMode = false;

  bool _useLibrary = false;
  LibraryFile? _selectedLibraryFile;
  bool _clearingMemory = false;

  final _difficulties = ['easy', 'medium', 'hard'];
  final _providers = ['gemini', 'openai', 'groq'];

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

  Future<void> _start() async {
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
        fallback: 'NÃ£o foi possÃ­vel gerar as questÃµes. Tente novamente.',
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
    return;
    /*

    String topic = '';
    String? libraryConteudo;

    try {
      final guard = ref.read(aiGenerationGuardProvider);
      final repo = ref.read(quizRepositoryProvider);
      final provider = await guard.ensureReadyForGeneration(
        overrideProvider: _provider,
      );

      // No modo infinito, carrega apenas o primeiro batch de 5 questões.
      final effectiveQuantity = _infiniteMode ? 5 : _quantity;

      List<Question>? questions;
      try {
        questions = await repo.generate(
          topic: topic,
          difficulty: _difficulty,
          quantity: effectiveQuantity,
          aiProvider: provider,
          conteudo: libraryConteudo,
        );
      } catch (firstError) {
        if (!_useLibrary) rethrow;

        final firstMessage = userVisibleErrorMessage(
          firstError,
          fallback: '',
        );

        if (!_isRetryableAiGenerationFailure(firstMessage)) {
          rethrow;
        }

        final config = await guard.loadConfig(overrideProvider: _provider);
        final providers = _buildProviderFallbackOrder(
          preferredProvider: provider,
          config: config,
        );
        final contexts = _buildContextFallbackOrder(
          useLibrary: _useLibrary,
          initialContext: libraryConteudo,
          rawLibraryContent: _selectedLibraryFile?.conteudo,
        );

        Object lastError = firstError;
        bool recovered = false;

        for (final candidateProvider in providers) {
          for (final candidateContext in contexts) {
            final sameAsOriginal = candidateProvider == provider &&
                candidateContext == libraryConteudo;
            if (sameAsOriginal) continue;

            try {
              await guard.ensureReadyForGeneration(
                overrideProvider: candidateProvider,
              );
              questions = await repo.generate(
                topic: topic,
                difficulty: _difficulty,
                quantity: effectiveQuantity,
                aiProvider: candidateProvider,
                conteudo: candidateContext,
              );
              recovered = true;
              break;
            } catch (retryError) {
              lastError = retryError;
              final retryMessage = userVisibleErrorMessage(
                retryError,
                fallback: '',
              );
              if (!_isRetryableAiGenerationFailure(retryMessage)) {
                rethrow;
              }
            }
          }
          if (recovered) break;
        }

        if (!recovered) {
          throw lastError;
        }
      }

      if (questions == null) {
        throw StateError('quiz_generation_result_missing');
      }

      if (!mounted) return;
      context.goNamed('quizSession', extra: {
        'questions': questions,
        if (_infiniteMode)
          'generationParams': QuizGenerationParams(
            topic: topic,
            difficulty: _difficulty,
            aiProvider: provider,
            conteudo: libraryConteudo,
          ),
        'infiniteMode': _infiniteMode,
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
    */
  }

  Future<void> _clearMemory() async {
    setState(() => _clearingMemory = true);
    try {
      await ref.read(quizGenerationCoordinatorProvider).clearSeenQuestions(
            useLibrary: _useLibrary,
            topic: _topicCtrl.text,
            selectedLibraryFile: _selectedLibraryFile,
          );
      if (!mounted) return;
      final topic = _useLibrary
          ? _selectedLibraryFile?.nome
          : _topicCtrl.text.trim().isNotEmpty
              ? _topicCtrl.text.trim()
              : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            topic != null
                ? 'Memoria de "$topic" apagada.'
                : 'Memoria de perguntas apagada.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('NÃ£o foi possÃ­vel limpar a memÃ³ria. Tente novamente.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _clearingMemory = false);
    }
    return;
    /*

    final topic = _useLibrary
        ? _selectedLibraryFile?.nome
        : _topicCtrl.text.trim().isNotEmpty
            ? _topicCtrl.text.trim()
            : null;

    setState(() => _clearingMemory = true);
    try {
      await ref.read(quizRepositoryProvider).clearSeenQuestions(topic: topic);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            topic != null
                ? 'Memoria de "$topic" apagada.'
                : 'Memoria de perguntas apagada.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível limpar a memória. Tente novamente.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _clearingMemory = false);
    }
    */
  }

  Future<void> _loadSavedProvider() async {
    try {
      final provider = await ref.read(aiProviderSettingProvider.future);
      if (mounted && _providers.contains(provider)) {
        setState(() => _provider = provider);
      }
    } catch (error) {
      debugPrint('Erro ao carregar provider: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
      body: SafeArea(
        child: Column(
          children: [
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
                        child: Text(
                          '<-',
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
                    'Novo Quiz',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  const _QuizQuotaBadge(),
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
                    const _SectionLabel('Fonte do Quiz'),
                    const SizedBox(height: 10),
                    LibrarySourceSelector(
                      useLibrary: _useLibrary,
                      selectedFile: _selectedLibraryFile,
                      onModeChanged: (v) => setState(() {
                        _useLibrary = v;
                        _selectedLibraryFile = null;
                      }),
                      onFileSelected: (f) =>
                          setState(() => _selectedLibraryFile = f),
                      manualChild: TextFormField(
                        controller: _topicCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Ex: Algebra linear, Historia do Brasil...',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _SectionLabel('Dificuldade'),
                    const SizedBox(height: 10),
                    Row(
                      children: _difficulties.map((d) {
                        final isSelected = _difficulty == d;
                        const labels = {
                          'easy': 'Facil',
                          'medium': 'Medio',
                          'hard': 'Dificil',
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
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  labels[d] ?? d,
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    // Modo Infinito toggle
                    GestureDetector(
                      onTap: () {
                        // Modo Infinito é exclusivo para usuários Premium.
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _infiniteMode
                              ? AppColors.primary.withOpacity(0.12)
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
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
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _infiniteMode
                                    ? AppColors.primary.withOpacity(0.2)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '∞',
                                  style: TextStyle(
                                    color: _infiniteMode
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                    fontSize: 18,
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
                                      Text(
                                        'Modo Infinito',
                                        style: TextStyle(
                                          color: _infiniteMode
                                              ? AppColors.primary
                                              : AppColors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.xpGold
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: AppColors.xpGold
                                                  .withOpacity(0.4)),
                                        ),
                                        child: const Text(
                                          'Premium',
                                          style: TextStyle(
                                            color: AppColors.xpGold,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Questões contínuas até você decidir parar',
                                    style: TextStyle(
                                      color: _infiniteMode
                                          ? AppColors.primary.withOpacity(0.7)
                                          : AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 42,
                              height: 24,
                              decoration: BoxDecoration(
                                color: _infiniteMode
                                    ? AppColors.primary
                                    : AppColors.border,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: AnimatedAlign(
                                duration: const Duration(milliseconds: 200),
                                alignment: _infiniteMode
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Quantidade (desabilitado no modo infinito)
                    AnimatedOpacity(
                      opacity: _infiniteMode ? 0.4 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: _infiniteMode,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionLabel(
                              _infiniteMode
                                  ? 'Quantidade: 5 por batch (automático)'
                                  : 'Quantidade: $_quantity questões',
                            ),
                            Slider(
                              value: _quantity.toDouble(),
                              min: 5,
                              max: 30,
                              divisions: 5,
                              label: '$_quantity',
                              activeColor: AppColors.primary,
                              onChanged: (v) =>
                                  setState(() => _quantity = v.round()),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _SectionLabel('Provedor de IA'),
                    const SizedBox(height: 10),
                    Row(
                      children: _providers.map((p) {
                        final isSelected = _provider == p;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _provider = p),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.accent.withOpacity(0.1)
                                    : AppColors.surface2,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.accent
                                      : AppColors.border,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  p.toUpperCase(),
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppColors.accent
                                        : AppColors.textMuted,
                                    fontWeight: FontWeight.w600,
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
                    AppButton(
                      label: _infiniteMode
                          ? 'Iniciar Modo Infinito'
                          : 'Gerar Quiz',
                      icon: _infiniteMode
                          ? Icons.all_inclusive_rounded
                          : Icons.auto_awesome_rounded,
                      isLoading: _loading,
                      onPressed: _start,
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _clearingMemory ? null : _clearMemory,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: _clearingMemory
                            ? const Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.delete_sweep_rounded,
                                    color: AppColors.textMuted,
                                    size: 16,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Limpar memoria de perguntas',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ]
                      .animate(interval: 80.ms)
                      .fadeIn()
                      .slideY(begin: 0.05, end: 0),
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
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
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
