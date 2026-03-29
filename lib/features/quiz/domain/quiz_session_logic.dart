const int infiniteQuizBatchSize = 5;
const int infiniteQuizPrefetchRemainingThreshold = 2;

int resolveQuizRequestQuantity({
  required bool infiniteMode,
  required int selectedQuantity,
}) {
  return infiniteMode ? infiniteQuizBatchSize : selectedQuantity;
}

bool shouldPrefetchInfiniteQuizBatch({
  required bool infiniteMode,
  required bool isLoadingMore,
  required bool hasMoreQuestions,
  required int currentIndex,
  required int loadedCount,
}) {
  if (!infiniteMode || isLoadingMore || !hasMoreQuestions || loadedCount <= 0) {
    return false;
  }

  final remainingIncludingCurrent = loadedCount - currentIndex;
  return remainingIncludingCurrent <= infiniteQuizPrefetchRemainingThreshold;
}

String buildQuizPrimaryActionLabel({
  required bool infiniteMode,
  required bool waitingForMore,
  required bool loadingMore,
  required bool hasMoreQuestions,
  required int currentIndex,
  required int loadedCount,
}) {
  if (waitingForMore || (loadingMore && currentIndex + 1 >= loadedCount)) {
    return 'Carregando mais...';
  }
  if (currentIndex + 1 < loadedCount) {
    return 'Proxima questao';
  }
  if (infiniteMode && hasMoreQuestions) {
    return 'Carregar mais 5';
  }
  return 'Ver resultado';
}
