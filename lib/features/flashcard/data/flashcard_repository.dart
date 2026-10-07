import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/local_storage.dart';
import '../../../shared/application/offline_sync_queue.dart';
import '../../../shared/application/account_scoped_preferences.dart';
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

  Future<Flashcard> review({
    required Flashcard card,
    required FsrsGrade grade,
  }) async {
    final account = AccountScopedPreferences.instance.activeAccountId;
    final gradeValue = grade.index;
    final reviewedAt = DateTime.now().toUtc();
    final result = scheduleFlashcardReview(
      card: card,
      grade: grade,
      reviewedAt: reviewedAt,
    );
    final syncId = shouldSyncFlashcardReview(card.remoteId)
        ? card.remoteId!
        : (await Sha256().hash(utf8.encode(
                '${AccountScopedPreferences.instance.activeAccountId}:${card.createdAt.microsecondsSinceEpoch}:${card.id}')))
            .bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
    await LocalStorage.instance.updateFlashcard(card.id, {
      'remote_id': syncId,
      'interval_days': result.intervalDays,
      'easiness': result.easiness,
      'due_date': result.nextDue.toIso8601String().substring(0, 10),
      'repetitions': result.repetitions,
      'last_reviewed': reviewedAt.toIso8601String(),
      'synced': 0,
    });
    final remote = await _syncReview(
      remoteId: syncId,
      card: card,
      gradeValue: gradeValue,
      reviewedAt: reviewedAt,
      account: account,
    );
    final reviewed = card.copyWith(
      remoteId: syncId,
      intervalDays:
          (remote?['interval_days'] as num?)?.toInt() ?? result.intervalDays,
      easiness: (remote?['easiness'] as num?)?.toDouble() ?? result.easiness,
      repetitions:
          (remote?['repetitions'] as num?)?.toInt() ?? result.repetitions,
      dueDate: DateTime.tryParse(remote?['due_date']?.toString() ?? '') ??
          result.nextDue,
      lastReviewed:
          DateTime.tryParse(remote?['last_reviewed']?.toString() ?? '') ??
              reviewedAt,
      synced: remote != null,
    );
    if (AccountScopedPreferences.instance.activeAccountId == account) {
      await LocalStorage.instance.updateFlashcard(card.id, {
        'interval_days': reviewed.intervalDays,
        'easiness': reviewed.easiness,
        'repetitions': reviewed.repetitions,
        'due_date': reviewed.dueDate.toUtc().toIso8601String().substring(0, 10),
        'last_reviewed': reviewed.lastReviewed!.toUtc().toIso8601String(),
        'synced': reviewed.synced ? 1 : 0,
      });
    }
    return reviewed;
  }

  Future<Map<String, dynamic>?> _syncReview({
    required String remoteId,
    required Flashcard card,
    required int gradeValue,
    required DateTime reviewedAt,
    required String? account,
  }) async {
    final payload = {
      'flashcard_id': remoteId,
      'grade': FsrsGrade.values[gradeValue].name,
      'reviewed_at': reviewedAt.toIso8601String(),
      'front': card.front,
      'back': card.back,
      if (card.topic != null) 'topic': card.topic,
      'interval_days': card.intervalDays.clamp(1, 36500),
      'easiness': card.easiness.clamp(1.3, 4.0),
      'repetitions': card.repetitions.clamp(0, 100000),
    };
    final idempotencyKey =
        'flashcard:$remoteId:${reviewedAt.toIso8601String()}';
    try {
      final response = await _client.dio.post(
        ApiEndpoints.flashcardsReview,
        data: payload,
        options: Options(
            headers: {'Idempotency-Key': idempotencyKey},
            extra: {if (account != null) 'expectedAccountId': account}),
      );
      return response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : null;
    } catch (_) {
      if (AccountScopedPreferences.instance.activeAccountId != account) {
        return null;
      }
      await _syncQueue?.enqueueItem(
        type: 'flashcard_review',
        payload: payload,
        idempotencyKey: idempotencyKey,
      );
      return null;
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
