import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/library/domain/library_model.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/library_source_selector.dart';
import '../application/flashcard_generation_coordinator.dart';
import '../data/flashcard_repository.dart';
import '../domain/flashcard_model.dart';

class FlashcardHubReviewModel {
  const FlashcardHubReviewModel({
    required this.isEmpty,
    required this.hasDueCards,
    required this.bannerEmoji,
    required this.bannerTitle,
    required this.bannerSubtitle,
    required this.ctaLabel,
  });

  final bool isEmpty;
  final bool hasDueCards;
  final String bannerEmoji;
  final String bannerTitle;
  final String bannerSubtitle;
  final String ctaLabel;
}

String _flashcardLabel(int count) => 'card${count > 1 ? 's' : ''}';

FlashcardHubReviewModel buildFlashcardHubReviewModel(
  List<Flashcard> cards,
) {
  final totalCount = cards.length;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dueCount = cards.where((card) => !card.dueDate.isAfter(today)).length;

  if (totalCount == 0) {
    return const FlashcardHubReviewModel(
      isEmpty: true,
      hasDueCards: false,
      bannerEmoji: '✅',
      bannerTitle: 'Nenhum flashcard salvo',
      bannerSubtitle: 'Gere novos cards abaixo para iniciar sua revisão.',
      ctaLabel: 'Gerar flashcards para estudar',
    );
  }

  if (dueCount == 0) {
    return const FlashcardHubReviewModel(
      isEmpty: false,
      hasDueCards: false,
      bannerEmoji: '🔁',
      bannerTitle: 'Revisão contínua pronta',
      bannerSubtitle: 'Sem pendentes agora, mas seu deck continua disponível.',
      ctaLabel: 'Continuar revisão',
    );
  }

  return FlashcardHubReviewModel(
    isEmpty: false,
    hasDueCards: true,
    bannerEmoji: '🧠',
    bannerTitle: '$dueCount ${_flashcardLabel(dueCount)} para hoje',
    bannerSubtitle: 'Pendentes primeiro, depois o restante do deck continua.',
    ctaLabel: 'Revisar $dueCount ${_flashcardLabel(dueCount)} agora',
  );
}

class FlashcardHubScreen extends ConsumerStatefulWidget {
  const FlashcardHubScreen({super.key});

  @override
  ConsumerState<FlashcardHubScreen> createState() => _FlashcardHubScreenState();
}

class _FlashcardHubScreenState extends ConsumerState<FlashcardHubScreen> {
  final _topicCtrl = TextEditingController();

  bool _showGenerate = false;
  bool _useLibrary = false;
  bool _generating = false;
  LibraryFile? _selectedLibraryFile;

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateAndStudy() async {
    final topic = _topicCtrl.text.trim();

    setState(() => _generating = true);
    try {
      final result = await ref
          .read(flashcardGenerationCoordinatorProvider)
          .generateAndStore(
            useLibrary: _useLibrary,
            topic: topic,
            selectedLibraryFile: _selectedLibraryFile,
          );

      ref.invalidate(dueFlashcardsProvider);
      ref.invalidate(reviewFlashcardsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.createdCount} flashcards criados sobre "${result.packageTitle}"!',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      context.goNamed('flashcardsReview');
    } catch (error) {
      if (!mounted) return;
      final message = userVisibleErrorMessage(
        error,
        fallback: 'Nao foi possivel gerar os flashcards. Tente novamente.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _generating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviewAsync = ref.watch(reviewFlashcardsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  _HubHeaderButton(
                    onTap: () => context.go('/'),
                    icon: Icons.arrow_back_rounded,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Flashcards SRS',
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    reviewAsync.when(
                      loading: () => const _StatsBannerSkeleton(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (cards) => _StatsBanner(
                        model: buildFlashcardHubReviewModel(cards),
                      ),
                    ),
                    const SizedBox(height: 16),
                    reviewAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (cards) {
                        final model = buildFlashcardHubReviewModel(cards);
                        final isEnabled = cards.isNotEmpty;

                        return GestureDetector(
                          onTap: isEnabled
                              ? () => context.goNamed('flashcardsReview')
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 56,
                            decoration: BoxDecoration(
                              gradient:
                                  isEnabled ? AppColors.primaryGradient : null,
                              color: isEnabled ? null : AppColors.surface2,
                              borderRadius: BorderRadius.circular(14),
                              border: isEnabled
                                  ? null
                                  : Border.all(color: AppColors.border),
                              boxShadow: isEnabled
                                  ? [
                                      BoxShadow(
                                        color:
                                            AppColors.primary.withOpacity(0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isEnabled
                                      ? Icons.play_arrow_rounded
                                      : Icons.celebration_rounded,
                                  color: isEnabled
                                      ? Colors.white
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  model.ctaLabel,
                                  style: TextStyle(
                                    color: isEnabled
                                        ? Colors.white
                                        : AppColors.textMuted,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: Container(height: 1, color: AppColors.border),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'ou',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(height: 1, color: AppColors.border),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showGenerate = !_showGenerate),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _showGenerate
                                ? AppColors.primary
                                : AppColors.border,
                            width: _showGenerate ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Gerar Flashcards com IA',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (!_showGenerate) ...[
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Digite um topico ou use um material da Biblioteca',
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            AnimatedRotation(
                              turns: _showGenerate ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _showGenerate
                          ? Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LibrarySourceSelector(
                                    useLibrary: _useLibrary,
                                    selectedFile: _selectedLibraryFile,
                                    onModeChanged: (value) => setState(() {
                                      _useLibrary = value;
                                      _selectedLibraryFile = null;
                                    }),
                                    onFileSelected: (file) => setState(
                                        () => _selectedLibraryFile = file),
                                    manualChild: TextFormField(
                                      controller: _topicCtrl,
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Ex: Mitose, Segunda Guerra Mundial...',
                                        prefixIcon: Icon(Icons.search_rounded),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  GestureDetector(
                                    onTap:
                                        _generating ? null : _generateAndStudy,
                                    child: Container(
                                      height: 52,
                                      decoration: BoxDecoration(
                                        gradient: _generating
                                            ? null
                                            : AppColors.primaryGradient,
                                        color: _generating
                                            ? AppColors.surface2
                                            : null,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: _generating
                                            ? const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: AppColors.primary,
                                                    ),
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text(
                                                    'Gerando flashcards...',
                                                    style: TextStyle(
                                                      color: AppColors.primary,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.auto_awesome_rounded,
                                                    color: Colors.white,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Gerar e Estudar',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ).animate().fadeIn().slideY(begin: 0.05, end: 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubHeaderButton extends StatelessWidget {
  const _HubHeaderButton({
    required this.onTap,
    required this.icon,
  });

  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: AppColors.textPrimary,
          size: 18,
        ),
      ),
    );
  }
}

class _StatsBanner extends StatelessWidget {
  const _StatsBanner({required this.model});

  final FlashcardHubReviewModel model;

  @override
  Widget build(BuildContext context) {
    final isEmpty = model.isEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: isEmpty
            ? null
            : LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.15),
                  AppColors.accent.withOpacity(0.08),
                ],
              ),
        color: isEmpty ? AppColors.surface2 : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isEmpty ? AppColors.border : AppColors.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.bannerEmoji,
            style: const TextStyle(fontSize: 34),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.bannerTitle,
                  style: TextStyle(
                    color: isEmpty ? AppColors.textPrimary : AppColors.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  model.bannerSubtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBannerSkeleton extends StatelessWidget {
  const _StatsBannerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      ),
    );
  }
}
