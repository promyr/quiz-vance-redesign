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

  final cases = <(FsrsGrade, int, double, int, int, double, int)>[
    (FsrsGrade.again, 6, 2.5, 4, 1, 2.3, 0),
    (FsrsGrade.hard, 1, 2.5, 0, 1, 2.35, 1),
    (FsrsGrade.hard, 5, 1.31, 4, 6, 1.3, 5),
    (FsrsGrade.good, 3, 2.5, 0, 1, 2.5, 1),
    (FsrsGrade.good, 1, 2.5, 1, 6, 2.5, 2),
    (FsrsGrade.good, 6, 2.5, 2, 15, 2.5, 3),
    (FsrsGrade.good, 1, 2.5, 2, 3, 2.5, 3),
    (FsrsGrade.easy, 1, 2.5, 0, 4, 2.65, 1),
    (FsrsGrade.easy, 4, 2.5, 1, 14, 2.65, 2),
    (FsrsGrade.easy, 20, 3.9, 4, 104, 4.0, 5),
    (FsrsGrade.good, 100000, 4.0, 4, 36500, 4.0, 5),
    (FsrsGrade.again, 2, 5.0, 1, 1, 3.8, 0),
  ];
  for (var i = 0; i < cases.length; i++) {
    final c = cases[i];
    test('backend/mobile schedule contract case $i ${c.$1.name}', () {
      final result = scheduleFlashcardReview(
          card: card.copyWith(
              intervalDays: c.$2, easiness: c.$3, repetitions: c.$4),
          grade: c.$1,
          reviewedAt: now);
      expect(result.intervalDays, c.$5);
      expect(result.easiness, closeTo(c.$6, 0.0000001));
      expect(result.repetitions, c.$7);
      expect(result.nextDue, now.add(Duration(days: c.$5)));
    });
  }
}
