import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/local_storage.dart';
import '../domain/flashcard_model.dart';

bool shouldSyncFlashcardReview(String? remoteId) {
  return remoteId != null && remoteId.trim().isNotEmpty;
}

class FlashcardRepository {
  const FlashcardRepository(this._client);
  final ApiClient _client;

  Future<List<Flashcard>> getDue() async {
    try {
      final response = await _client.dio.get(ApiEndpoints.flashcardsDue);
      final list = ((response.data['flashcards'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>();
      final db = LocalStorage.instance;
      for (final card in list) {
        await db.upsertFlashcard({
          'remote_id': card['id']?.toString(),
          'front': card['front'],
          'back': card['back'],
          'topic': card['topic'],
          'interval_days': card['interval_days'] ?? 1,
          'easiness': card['easiness'] ?? 2.5,
          'due_date': card['due_date'],
          'repetitions': card['repetitions'] ?? 0,
          'last_reviewed': card['last_reviewed'],
          'synced': 1,
          'created_at': card['created_at'] ?? DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {
      // Offline: usa cache local.
    }

    final rows = await LocalStorage.instance.getDueFlashcards();
    return rows.map(Flashcard.fromDb).toList();
  }

  Future<List<Flashcard>> getReviewDeck() async {
    await getDue();
    final rows = await LocalStorage.instance.getReviewFlashcards();
    return rows.map(Flashcard.fromDb).toList();
  }

  Future<void> review({
    required int localId,
    required String? remoteId,
    required FsrsGrade grade,
  }) async {
    final gradeValue = grade.index;
    final result = _calculateFsrs(grade);
    await LocalStorage.instance.updateFlashcard(localId, {
      'interval_days': result.intervalDays,
      'easiness': result.easiness,
      'due_date': result.nextDue.toIso8601String().substring(0, 10),
      'repetitions': result.repetitions,
      'last_reviewed': DateTime.now().toIso8601String(),
      'synced': 0,
    });
    if (shouldSyncFlashcardReview(remoteId)) {
      unawaited(_syncReview(remoteId: remoteId!, gradeValue: gradeValue));
    }
  }

  Future<void> _syncReview({
    required String remoteId,
    required int gradeValue,
  }) async {
    try {
      await _client.dio.post(
        ApiEndpoints.flashcardsReview,
        data: {'card_id': remoteId, 'grade': gradeValue},
      );
    } catch (_) {
      // Sync remoto best-effort.
    }
  }

  _FsrsResult _calculateFsrs(FsrsGrade grade) {
    const defaultEasiness = 2.5;
    final gradeMap = {
      FsrsGrade.again: 0,
      FsrsGrade.hard: 2,
      FsrsGrade.good: 4,
      FsrsGrade.easy: 5,
    };
    final q = gradeMap[grade]!;
    final easiness = (defaultEasiness + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        .clamp(1.3, 4.0);
    final intervalDays = q < 3 ? 1 : (1 * easiness).round().clamp(1, 365);
    return _FsrsResult(
      intervalDays: intervalDays,
      easiness: easiness,
      nextDue: DateTime.now().add(Duration(days: intervalDays)),
      repetitions: q >= 3 ? 1 : 0,
    );
  }
}

class _FsrsResult {
  const _FsrsResult({
    required this.intervalDays,
    required this.easiness,
    required this.nextDue,
    required this.repetitions,
  });
  final int intervalDays;
  final double easiness;
  final DateTime nextDue;
  final int repetitions;
}

final flashcardRepositoryProvider = Provider<FlashcardRepository>(
  (ref) => FlashcardRepository(ref.watch(apiClientProvider)),
);

final dueFlashcardsProvider =
    FutureProvider.autoDispose<List<Flashcard>>((ref) {
  return ref.watch(flashcardRepositoryProvider).getDue();
});

final reviewFlashcardsProvider =
    FutureProvider.autoDispose<List<Flashcard>>((ref) {
  return ref.watch(flashcardRepositoryProvider).getReviewDeck();
});
