import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/flashcard/domain/flashcard_model.dart';

void main() {
  group('FsrsGrade', () {
    test('enum values are defined', () {
      expect(FsrsGrade.again, isNotNull);
      expect(FsrsGrade.hard, isNotNull);
      expect(FsrsGrade.good, isNotNull);
      expect(FsrsGrade.easy, isNotNull);
    });
  });

  group('Flashcard', () {
    test('fromDb creates Flashcard from database row', () {
      final now = DateTime.now();
      final row = {
        'id': 1,
        'remote_id': 'remote_1',
        'front': 'Front text',
        'back': 'Back text',
        'topic': 'Science',
        'interval_days': 3,
        'easiness': 2.5,
        'due_date': now.toIso8601String(),
        'repetitions': 5,
        'last_reviewed': now.toIso8601String(),
        'synced': 1,
        'created_at': now.toIso8601String(),
      };

      final flashcard = Flashcard.fromDb(row);

      expect(flashcard.id, equals(1));
      expect(flashcard.remoteId, equals('remote_1'));
      expect(flashcard.front, equals('Front text'));
      expect(flashcard.back, equals('Back text'));
      expect(flashcard.topic, equals('Science'));
      expect(flashcard.intervalDays, equals(3));
      expect(flashcard.easiness, equals(2.5));
      expect(flashcard.repetitions, equals(5));
      expect(flashcard.synced, equals(true));
    });

    test('fromDb handles nullable fields', () {
      final now = DateTime.now();
      final row = {
        'id': 2,
        'remote_id': null,
        'front': 'Front',
        'back': 'Back',
        'topic': null,
        'interval_days': null,
        'easiness': null,
        'due_date': now.toIso8601String(),
        'repetitions': null,
        'last_reviewed': null,
        'synced': 0,
        'created_at': now.toIso8601String(),
      };

      final flashcard = Flashcard.fromDb(row);

      expect(flashcard.remoteId, isNull);
      expect(flashcard.topic, isNull);
      expect(flashcard.intervalDays, equals(1));
      expect(flashcard.easiness, equals(2.5));
      expect(flashcard.repetitions, equals(0));
      expect(flashcard.lastReviewed, isNull);
      expect(flashcard.synced, equals(false));
    });

    test('copyWith creates new Flashcard with updated fields', () {
      final now = DateTime.now();
      final original = Flashcard(
        id: 1,
        front: 'Original front',
        back: 'Original back',
        dueDate: now,
        createdAt: now,
      );

      final updated = original.copyWith(
        front: 'New front',
        intervalDays: 7,
        repetitions: 10,
      );

      expect(updated.id, equals(original.id));
      expect(updated.front, equals('New front'));
      expect(updated.back, equals(original.back));
      expect(updated.intervalDays, equals(7));
      expect(updated.repetitions, equals(10));
      expect(updated.dueDate, equals(original.dueDate));
    });

    test('copyWith preserves unchanged fields', () {
      final now = DateTime.now();
      final flashcard = Flashcard(
        id: 1,
        remoteId: 'remote_1',
        front: 'Front',
        back: 'Back',
        topic: 'Math',
        intervalDays: 5,
        easiness: 2.5,
        dueDate: now,
        repetitions: 3,
        synced: true,
        createdAt: now,
      );

      final updated = flashcard.copyWith(easiness: 3.0);

      expect(updated.id, equals(flashcard.id));
      expect(updated.remoteId, equals(flashcard.remoteId));
      expect(updated.front, equals(flashcard.front));
      expect(updated.back, equals(flashcard.back));
      expect(updated.topic, equals(flashcard.topic));
      expect(updated.intervalDays, equals(flashcard.intervalDays));
      expect(updated.easiness, equals(3.0));
      expect(updated.repetitions, equals(flashcard.repetitions));
      expect(updated.synced, equals(flashcard.synced));
    });

    test('fromJson creates Flashcard from JSON', () {
      final now = DateTime.now();
      final json = {
        'id': 10,
        'remote_id': 'remote_10',
        'front': 'Front JSON',
        'back': 'Back JSON',
        'topic': 'History',
        'interval_days': 2,
        'easiness': 2.8,
        'due_date': now.toIso8601String(),
        'repetitions': 2,
        'last_reviewed': now.toIso8601String(),
        'synced': true,
        'created_at': now.toIso8601String(),
      };

      final flashcard = Flashcard.fromJson(json);

      expect(flashcard.id, equals(10));
      expect(flashcard.remoteId, equals('remote_10'));
      expect(flashcard.front, equals('Front JSON'));
    });
  });
}
