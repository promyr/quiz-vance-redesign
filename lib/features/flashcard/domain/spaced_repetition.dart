import 'dart:math' as math;

import 'flashcard_model.dart';

class SpacedRepetitionResult {
  const SpacedRepetitionResult({
    required this.intervalDays,
    required this.easiness,
    required this.repetitions,
    required this.nextDue,
  });

  final int intervalDays;
  final double easiness;
  final int repetitions;
  final DateTime nextDue;
}

SpacedRepetitionResult scheduleFlashcardReview({
  required Flashcard card,
  required FsrsGrade grade,
  required DateTime reviewedAt,
}) {
  var easiness = card.easiness.clamp(1.3, 4.0);
  var repetitions = card.repetitions;
  late int interval;

  switch (grade) {
    case FsrsGrade.again:
      repetitions = 0;
      easiness = math.max(1.3, easiness - 0.2);
      interval = 1;
    case FsrsGrade.hard:
      repetitions += 1;
      easiness = math.max(1.3, easiness - 0.15);
      interval = math.max(1, (card.intervalDays * 1.2).round());
    case FsrsGrade.good:
      repetitions += 1;
      interval = repetitions == 1
          ? 1
          : repetitions == 2
              ? 6
              : (card.intervalDays * easiness).round();
    case FsrsGrade.easy:
      repetitions += 1;
      easiness = math.min(4.0, easiness + 0.15);
      interval =
          repetitions == 1 ? 4 : (card.intervalDays * easiness * 1.3).round();
  }

  interval = interval.clamp(1, 36500);
  return SpacedRepetitionResult(
    intervalDays: interval,
    easiness: easiness,
    repetitions: repetitions,
    nextDue: reviewedAt.add(Duration(days: interval)),
  );
}
