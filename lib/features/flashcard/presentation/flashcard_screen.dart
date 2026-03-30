import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/gamification_provider.dart';
import '../../../shared/providers/user_provider.dart';
import '../data/flashcard_repository.dart';
import '../domain/flashcard_model.dart';
import '../domain/flashcard_review_session.dart';

Future<void> applyFlashcardReviewRewards({
  required Future<void> Function() incrementFlashcardsToday,
  required Future<void> Function() recordFlashcardReview,
}) async {
  await incrementFlashcardsToday();
  try {
    await recordFlashcardReview();
  } catch (error) {
    debugPrint('Gamification error: $error');
  }
}

class FlashcardScreen extends ConsumerStatefulWidget {
  const FlashcardScreen({super.key});

  @override
  ConsumerState<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends ConsumerState<FlashcardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipController;
  late final Animation<double> _flipAnimation;

  bool _showAnswer = false;
  int _currentIndex = 0;
  int _reviewedCount = 0;
  int _cycleTotalCount = 0;
  bool _waitingForNextCycle = false;
  List<Flashcard> _activeCycleCards = const <Flashcard>[];
  List<Flashcard> _nextCycleCards = const <Flashcard>[];

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _toggleCardFace() {
    if (_showAnswer) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _showAnswer = !_showAnswer);
  }

  Future<void> _grade(List<Flashcard> cards, FsrsGrade grade) async {
    final card = cards[_currentIndex];

    await ref.read(flashcardRepositoryProvider).review(
          localId: card.id,
          remoteId: card.remoteId,
          grade: grade,
        );
    await applyFlashcardReviewRewards(
      incrementFlashcardsToday: () => ref
          .read(userStatsNotifierProvider.notifier)
          .incrementFlashcardsToday(),
      recordFlashcardReview: () =>
          ref.read(gamificationProvider.notifier).recordFlashcardReview(),
    );

    if (!mounted) {
      return;
    }
    final progressed = advanceFlashcardReviewSession(
      activeCards: cards,
      nextCycleCards: _nextCycleCards,
      currentIndex: _currentIndex,
      reviewedCount: _reviewedCount,
      cycleTotalCount: _cycleTotalCount,
      reviewedCard: card,
    );
    setState(() {
      _activeCycleCards = progressed.activeCards;
      _nextCycleCards = progressed.nextCycleCards;
      _currentIndex = progressed.currentIndex;
      _reviewedCount = progressed.reviewedCount;
      _cycleTotalCount = progressed.cycleTotalCount;
      _waitingForNextCycle = progressed.waitingForNextCycle;
      _showAnswer = false;
    });
    _flipController.reset();
  }

  void _continueReviewCycle() {
    final nextState = continueFlashcardReviewSession(_nextCycleCards);
    setState(() {
      _activeCycleCards = nextState.activeCards;
      _nextCycleCards = nextState.nextCycleCards;
      _currentIndex = nextState.currentIndex;
      _reviewedCount = nextState.reviewedCount;
      _cycleTotalCount = nextState.cycleTotalCount;
      _waitingForNextCycle = nextState.waitingForNextCycle;
      _showAnswer = false;
    });
    _flipController.reset();
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(reviewFlashcardsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: cardsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (error, _) => Center(
            child: Text(
              'Erro: $error',
              style: const TextStyle(color: AppColors.accent),
            ),
          ),
          data: (cards) {
            if (_activeCycleCards.isEmpty &&
                _nextCycleCards.isEmpty &&
                !_waitingForNextCycle &&
                cards.isNotEmpty) {
              final initialState = startFlashcardReviewSession(cards);
              _activeCycleCards = initialState.activeCards;
              _nextCycleCards = initialState.nextCycleCards;
              _currentIndex = initialState.currentIndex;
              _reviewedCount = initialState.reviewedCount;
              _cycleTotalCount = initialState.cycleTotalCount;
            }

            final sessionCards = _activeCycleCards;
            if (sessionCards.isEmpty && !_waitingForNextCycle) {
              return _EmptyReviewState(
                onBack: () => context.go('/'),
              );
            }

            if (_waitingForNextCycle) {
              return _CycleCheckpointState(
                reviewedCount: _cycleTotalCount,
                onBack: () => context.go('/'),
                onContinue: _continueReviewCycle,
              );
            }

            if (_currentIndex >= sessionCards.length) {
              _currentIndex = 0;
            }

            final card = sessionCards[_currentIndex];
            final visiblePosition = (_reviewedCount + 1).clamp(1, _cycleTotalCount);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: AppColors.textPrimary,
                            size: 18,
                          ),
                        ),
                      ),
                      const Text(
                        'Flashcards',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '$visiblePosition / $_cycleTotalCount',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _toggleCardFace,
                          child: AnimatedBuilder(
                            animation: _flipAnimation,
                            builder: (context, child) {
                              final angle = _flipAnimation.value * 3.14159;
                              final isBack = _flipAnimation.value > 0.5;

                              return Transform(
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.001)
                                  ..rotateY(angle),
                                alignment: Alignment.center,
                                child: Container(
                                  width: double.infinity,
                                  constraints:
                                      const BoxConstraints(minHeight: 220),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppColors.surface,
                                        AppColors.surface2,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: AppColors.border),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.4),
                                        blurRadius: 60,
                                        offset: const Offset(0, 20),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        top: 0,
                                        left: 20,
                                        right: 20,
                                        child: Container(
                                          height: 1,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Colors.transparent,
                                                AppColors.primary,
                                                Colors.transparent,
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(1),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 14,
                                        right: 14,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withOpacity(0.2),
                                            border: Border.all(
                                              color: AppColors.primary
                                                  .withOpacity(0.4),
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(100),
                                          ),
                                          child: Text(
                                            isBack
                                                ? 'Resposta'
                                                : 'SRS  Revisao',
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          22,
                                          40,
                                          22,
                                          28,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              isBack ? 'RESPOSTA' : 'PERGUNTA',
                                              style: const TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 10,
                                                letterSpacing: 1,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Transform(
                                              transform: isBack
                                                  ? (Matrix4.identity()
                                                    ..rotateY(3.14159))
                                                  : Matrix4.identity(),
                                              alignment: Alignment.center,
                                              child: Text(
                                                isBack ? card.back : card.front,
                                                style: const TextStyle(
                                                  color: AppColors.textPrimary,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  height: 1.5,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                            if (!isBack) ...[
                                              const SizedBox(height: 20),
                                              const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.touch_app_rounded,
                                                    size: 14,
                                                    color: AppColors.textMuted,
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'Toque para ver a resposta',
                                                    style: TextStyle(
                                                      color:
                                                          AppColors.textMuted,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (_showAnswer) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'Quanto voce se lembrou?',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_showAnswer)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
                    child: Row(
                      children: [
                        _GradeButton(
                          icon: Icons.refresh_rounded,
                          label: 'De novo',
                          color: AppColors.accent,
                          onTap: () => _grade(sessionCards, FsrsGrade.again),
                        ),
                        const SizedBox(width: 8),
                        _GradeButton(
                          icon: Icons.trending_down_rounded,
                          label: 'Dificil',
                          color: AppColors.warning,
                          onTap: () => _grade(sessionCards, FsrsGrade.hard),
                        ),
                        const SizedBox(width: 8),
                        _GradeButton(
                          icon: Icons.check_rounded,
                          label: 'Bom',
                          color: AppColors.success,
                          onTap: () => _grade(sessionCards, FsrsGrade.good),
                        ),
                        const SizedBox(width: 8),
                        _GradeButton(
                          icon: Icons.bolt_rounded,
                          label: 'Facil',
                          color: AppColors.primary,
                          onTap: () => _grade(sessionCards, FsrsGrade.easy),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyReviewState extends StatelessWidget {
  const _EmptyReviewState({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.task_alt_rounded,
          size: 64,
          color: AppColors.success,
        ),
        const SizedBox(height: 16),
        const Text(
          'Nenhum flashcard salvo',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Gere ou salve cards na biblioteca para iniciar a revisao continua.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: onBack,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Voltar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CycleCheckpointState extends StatelessWidget {
  const _CycleCheckpointState({
    required this.reviewedCount,
    required this.onBack,
    required this.onContinue,
  });

  final int reviewedCount;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 64,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Ciclo concluído',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Você revisou $reviewedCount cards neste ciclo. Continue quando quiser, sem sair da sessão.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onContinue,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'Continuar revisão',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Text(
                  'Voltar',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
