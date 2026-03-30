import 'flashcard_model.dart';

class FlashcardReviewSessionState {
  const FlashcardReviewSessionState({
    required this.activeCards,
    required this.nextCycleCards,
    required this.currentIndex,
    required this.reviewedCount,
    required this.cycleTotalCount,
    required this.waitingForNextCycle,
  });

  final List<Flashcard> activeCards;
  final List<Flashcard> nextCycleCards;
  final int currentIndex;
  final int reviewedCount;
  final int cycleTotalCount;
  final bool waitingForNextCycle;
}

FlashcardReviewSessionState startFlashcardReviewSession(List<Flashcard> cards) {
  return FlashcardReviewSessionState(
    activeCards: List<Flashcard>.from(cards),
    nextCycleCards: const <Flashcard>[],
    currentIndex: 0,
    reviewedCount: 0,
    cycleTotalCount: cards.length,
    waitingForNextCycle: false,
  );
}

FlashcardReviewSessionState advanceFlashcardReviewSession({
  required List<Flashcard> activeCards,
  required List<Flashcard> nextCycleCards,
  required int currentIndex,
  required int reviewedCount,
  required int cycleTotalCount,
  required Flashcard reviewedCard,
}) {
  if (activeCards.isEmpty) {
    return FlashcardReviewSessionState(
      activeCards: const <Flashcard>[],
      nextCycleCards: nextCycleCards,
      currentIndex: 0,
      reviewedCount: reviewedCount,
      cycleTotalCount: cycleTotalCount,
      waitingForNextCycle: false,
    );
  }

  final normalizedIndex = currentIndex.clamp(0, activeCards.length - 1);
  final remainingCards = List<Flashcard>.from(activeCards)
    ..removeAt(normalizedIndex);
  final upcomingCards = List<Flashcard>.from(nextCycleCards)..add(reviewedCard);
  final updatedReviewedCount = reviewedCount + 1;

  if (remainingCards.isEmpty) {
    return FlashcardReviewSessionState(
      activeCards: const <Flashcard>[],
      nextCycleCards: upcomingCards,
      currentIndex: 0,
      reviewedCount: updatedReviewedCount,
      cycleTotalCount: cycleTotalCount,
      waitingForNextCycle: true,
    );
  }

  final nextIndex =
      normalizedIndex >= remainingCards.length ? 0 : normalizedIndex;

  return FlashcardReviewSessionState(
    activeCards: remainingCards,
    nextCycleCards: upcomingCards,
    currentIndex: nextIndex,
    reviewedCount: updatedReviewedCount,
    cycleTotalCount: cycleTotalCount,
    waitingForNextCycle: false,
  );
}

FlashcardReviewSessionState continueFlashcardReviewSession(
  List<Flashcard> nextCycleCards,
) {
  return startFlashcardReviewSession(nextCycleCards);
}
