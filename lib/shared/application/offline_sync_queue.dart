import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'account_scoped_preferences.dart';

class QueuedSyncItem {
  const QueuedSyncItem({
    required this.id,
    required this.type,
    required this.payload,
    required this.timestamp,
    this.retryCount = 0,
    this.nextAttemptAt,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final int retryCount;
  final DateTime? nextAttemptAt;

  QueuedSyncItem copyWith({int? retryCount, DateTime? nextAttemptAt}) =>
      QueuedSyncItem(
        id: id,
        type: type,
        payload: payload,
        timestamp: timestamp,
        retryCount: retryCount ?? this.retryCount,
        nextAttemptAt: nextAttemptAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
        'retryCount': retryCount,
        'nextAttemptAt': nextAttemptAt?.toIso8601String(),
      };

  factory QueuedSyncItem.fromJson(Map<String, dynamic> json) => QueuedSyncItem(
        id: json['id'] as String,
        type: json['type'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        timestamp: DateTime.parse(json['timestamp'] as String),
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
        nextAttemptAt:
            DateTime.tryParse(json['nextAttemptAt']?.toString() ?? ''),
      );
}

class OfflineSyncQueue {
  OfflineSyncQueue({
    ApiClient? client,
    AccountScopedPreferences? preferences,
  })  : _client = client,
        _preferences = preferences ?? AccountScopedPreferences.instance;

  final ApiClient? _client;
  final AccountScopedPreferences _preferences;

  static const _queueKey = 'offline_sync_queue_v1';
  static const _deadLetterKey = 'offline_sync_dead_letter_v1';

  static Future<void>? _writes;
  static final Map<String, Future<int>> _flushes = {};
  String _key(String key) => _preferences.scopedKey(key);
  Future<T> _mutate<T>(Future<T> Function() operation) {
    final previous = _writes;
    late final Future<void> marker;
    final completion = Completer<T>();
    marker = () async {
      if (previous != null) await previous;
      try {
        completion.complete(await operation());
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        if (identical(_writes, marker)) _writes = null;
      }
    }();
    _writes = marker;
    return completion.future;
  }

  Future<List<QueuedSyncItem>> getPendingItems() => _readItems(_key(_queueKey));
  Future<List<QueuedSyncItem>> getDeadLetterItems() =>
      _readItems(_key(_deadLetterKey));
  Future<List<QueuedSyncItem>> _readItems(String key) async {
    final raw = await _preferences.getStringList(key, scoped: false) ?? [];
    final items = <QueuedSyncItem>[];
    for (final str in raw) {
      try {
        items.add(
            QueuedSyncItem.fromJson(jsonDecode(str) as Map<String, dynamic>));
      } catch (_) {/* Keep other recoverable entries. */}
    }
    return items;
  }

  Future<void> _save(String key, List<QueuedSyncItem> items) =>
      _preferences.setStringList(
          key, items.map((i) => jsonEncode(i.toJson())).toList(),
          scoped: false);
  Future<void> enqueueItem(
      {required String type,
      required Map<String, dynamic> payload,
      String? idempotencyKey}) {
    final key = _key(_queueKey);
    final stableId = idempotencyKey?.trim();
    final snapshot =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(payload)) as Map);
    return _mutate(() async {
      final items = await _readItems(key);
      if (stableId != null &&
          stableId.isNotEmpty &&
          items.any((i) => i.id == stableId && i.type == type)) {
        return;
      }
      items.add(QueuedSyncItem(
          id: stableId == null || stableId.isEmpty
              ? '${DateTime.now().microsecondsSinceEpoch}_${items.length}'
              : stableId,
          type: type,
          payload: snapshot,
          timestamp: DateTime.now()));
      await _save(key, items);
    });
  }

  Future<void> acknowledge(String id, {required String type}) {
    final key = _key(_queueKey);
    return _mutate(() async {
      final items = await _readItems(key);
      items.removeWhere((i) => i.id == id && i.type == type);
      await _save(key, items);
    });
  }

  Future<int> flushQueue() {
    final key = _key(_queueKey);
    final existing = _flushes[key];
    if (existing != null) return existing;
    final account = _preferences.activeAccountId;
    late final Future<int> operation;
    operation = () async {
      try {
        return await _flush(key, _key(_deadLetterKey), account);
      } finally {
        if (identical(_flushes[key], operation)) _flushes.remove(key);
      }
    }();
    _flushes[key] = operation;
    return operation;
  }

  Future<int> _flush(String key, String deadKey, String? account) async {
    final client = _client;
    if (client == null) return 0;
    final pending = _writes;
    if (pending != null) await pending;
    final items = await _readItems(key);
    var count = 0;
    for (final item in items) {
      if (_preferences.activeAccountId != account) break;
      if (item.nextAttemptAt?.isAfter(DateTime.now()) == true) continue;
      try {
        await _submit(client, item, account);
        // Use captured keys, never the account selected after the request.
        await _mutate(() async {
          final fresh = await _readItems(key);
          fresh.removeWhere((i) => i.id == item.id && i.type == item.type);
          await _save(key, fresh);
        });
        count++;
      } catch (error) {
        if (_preferences.activeAccountId != account) break;
        final code = error is DioException ? error.response?.statusCode : null;
        if (code == 401 ||
            code == 403 ||
            error is DioException && error.type == DioExceptionType.cancel) {
          break;
        }
        final retry = item.retryCount + 1;
        final permanent =
            error is StateError || code == 400 || code == 404 || code == 422;
        final updated = item.copyWith(
            retryCount: retry,
            nextAttemptAt: permanent
                ? null
                : DateTime.now().add(Duration(
                    seconds: (30 * (1 << retry.clamp(0, 4))).clamp(30, 300))));
        await _mutate(() async {
          final fresh = await _readItems(key);
          final index =
              fresh.indexWhere((i) => i.id == item.id && i.type == item.type);
          if (index < 0) return;
          if (permanent && retry >= 5) {
            final dead = await _readItems(deadKey);
            dead.removeWhere((i) => i.id == item.id && i.type == item.type);
            dead.add(updated);
            await _save(
                deadKey, dead); // Persist recovery before removing pending.
            fresh.removeAt(index);
          } else {
            fresh[index] = updated;
          }
          await _save(key, fresh);
        });
      }
    }
    return count;
  }

  Future<void> _submit(
      ApiClient client, QueuedSyncItem item, String? account) async {
    final endpoint = switch (item.type) {
      'quiz_result' => ApiEndpoints.quizSubmit,
      'simulado_result' => ApiEndpoints.simuladoSubmit,
      'flashcard_review' => ApiEndpoints.flashcardsReview,
      _ => throw StateError('Unsupported sync item type'),
    };
    var payload = item.payload;
    if (item.type == 'flashcard_review') {
      final grade = payload['grade'];
      payload = {
        'flashcard_id': payload['flashcard_id'] ?? payload['card_id'],
        'grade': grade is num
            ? ['again', 'hard', 'good', 'easy'][grade.toInt().clamp(0, 3)]
            : grade,
        'reviewed_at':
            payload['reviewed_at'] ?? item.timestamp.toUtc().toIso8601String(),
      };
    }
    await client.dio.post(endpoint,
        data: payload,
        options: Options(
            headers: {'Idempotency-Key': item.id},
            extra: {if (account != null) 'expectedAccountId': account}));
  }
}

final offlineSyncQueueProvider = Provider<OfflineSyncQueue>((ref) {
  return OfflineSyncQueue(
    client: ref.watch(apiClientProvider),
  );
});
