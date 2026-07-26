import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/flashcard/domain/flashcard_model.dart';
import 'package:quiz_vance_flutter/features/flashcard/domain/spaced_repetition.dart';

void main() {
  final now = DateTime.utc(2026, 7, 25, 12);
  final card = Flashcard(
    id: 1,
    front: 'Q',
    back: 'A',
    intervalDays: 6,
    easiness: 2.5,
    repetitions: 2,
    dueDate: now,
    createdAt: now,
  );

  test('good progresses from current scheduling state', () {
    final result = scheduleFlashcardReview(
      card: card,
      grade: FsrsGrade.good,
      reviewedAt: now,
    );
    expect(result.repetitions, 3);
    expect(result.intervalDays, 15);
    expect(result.nextDue, now.add(const Duration(days: 15)));
  });

  test('again resets repetitions without reducing ease below floor', () {
    final result = scheduleFlashcardReview(
      card: card.copyWith(easiness: 1.3),
      grade: FsrsGrade.again,
      reviewedAt: now,
    );
    expect(result.repetitions, 0);
    expect(result.intervalDays, 1);
    expect(result.easiness, 1.3);
  });
}
