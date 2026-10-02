import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/local_storage.dart';
import '../../../shared/application/offline_sync_queue.dart';
import '../domain/flashcard_model.dart';
import '../domain/spaced_repetition.dart';

bool shouldSyncFlashcardReview(String? remoteId) {
  return remoteId != null && remoteId.trim().isNotEmpty;
}

class FlashcardRepository {
  const FlashcardRepository(this._client, {OfflineSyncQueue? syncQueue})
      : _syncQueue = syncQueue;
  final ApiClient _client;
  final OfflineSyncQueue? _syncQueue;

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
    required Flashcard card,
    required FsrsGrade grade,
  }) async {
    final gradeValue = grade.index;
    final reviewedAt = DateTime.now().toUtc();
    final result = scheduleFlashcardReview(
      card: card,
      grade: grade,
      reviewedAt: reviewedAt,
    );
    await LocalStorage.instance.updateFlashcard(card.id, {
      'interval_days': result.intervalDays,
      'easiness': result.easiness,
      'due_date': result.nextDue.toIso8601String().substring(0, 10),
      'repetitions': result.repetitions,
      'last_reviewed': reviewedAt.toIso8601String(),
      'synced': 0,
    });
    if (shouldSyncFlashcardReview(card.remoteId)) {
      await _syncReview(
        remoteId: card.remoteId!,
        gradeValue: gradeValue,
        reviewedAt: reviewedAt,
      );
    }
  }

  Future<void> _syncReview({
    required String remoteId,
    required int gradeValue,
    required DateTime reviewedAt,
  }) async {
    final payload = {'card_id': remoteId, 'grade': gradeValue};
    final idempotencyKey =
        'flashcard:$remoteId:${reviewedAt.toIso8601String()}';
    try {
      await _client.dio.post(
        ApiEndpoints.flashcardsReview,
        data: payload,
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
    } catch (_) {
      await _syncQueue?.enqueueItem(
        type: 'flashcard_review',
        payload: payload,
        idempotencyKey: idempotencyKey,
      );
    }
  }
}

final flashcardRepositoryProvider = Provider<FlashcardRepository>(
  (ref) => FlashcardRepository(
    ref.watch(apiClientProvider),
    syncQueue: ref.watch(offlineSyncQueueProvider),
  ),
);

final dueFlashcardsProvider =
    FutureProvider.autoDispose<List<Flashcard>>((ref) {
  return ref.watch(flashcardRepositoryProvider).getDue();
});

final reviewFlashcardsProvider =
    FutureProvider.autoDispose<List<Flashcard>>((ref) {
  return ref.watch(flashcardRepositoryProvider).getReviewDeck();
});
