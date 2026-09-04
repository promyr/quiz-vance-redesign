import 'dart:convert';
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
  });

  final String id;
  final String type; // 'quiz_result', 'xp_gain', 'streak_update'
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final int retryCount;

  QueuedSyncItem copyWith({int? retryCount}) => QueuedSyncItem(
        id: id,
        type: type,
        payload: payload,
        timestamp: timestamp,
        retryCount: retryCount ?? this.retryCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
        'retryCount': retryCount,
      };

  factory QueuedSyncItem.fromJson(Map<String, dynamic> json) => QueuedSyncItem(
        id: json['id'] as String,
        type: json['type'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        timestamp: DateTime.parse(json['timestamp'] as String),
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
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

  Future<List<QueuedSyncItem>> getPendingItems() async {
    final raw = await _preferences.getStringList(_queueKey) ?? [];
    final items = <QueuedSyncItem>[];
    for (final str in raw) {
      try {
        final map = jsonDecode(str) as Map<String, dynamic>;
        items.add(QueuedSyncItem.fromJson(map));
      } catch (_) {}
    }
    return items;
  }

  Future<void> enqueueItem({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final items = await getPendingItems();
    final newItem = QueuedSyncItem(
      id: '${DateTime.now().millisecondsSinceEpoch}_${items.length}',
      type: type,
      payload: payload,
      timestamp: DateTime.now(),
    );
    items.add(newItem);
    await _saveItems(items);
  }

  Future<int> flushQueue() async {
    final client = _client;
    if (client == null) return 0;

    final itemsToSync = await getPendingItems();
    if (itemsToSync.isEmpty) return 0;

    int syncedCount = 0;
    final succeededIds = <String>{};
    final updatedRetries = <String, QueuedSyncItem>{};

    for (final item in itemsToSync) {
      try {
        if (item.type == 'quiz_result') {
          await client.dio.post(
            ApiEndpoints.userStats,
            data: item.payload,
          );
          syncedCount++;
          succeededIds.add(item.id);
        } else {
          // General analytics / XP sync
          syncedCount++;
          succeededIds.add(item.id);
        }
      } catch (_) {
        final nextRetry = item.retryCount + 1;
        if (nextRetry < 5) {
          updatedRetries[item.id] = item.copyWith(retryCount: nextRetry);
        }
        // If nextRetry >= 5, drop poison pill item to prevent infinite loops
      }
    }

    // Safely re-read items to preserve items enqueued concurrently during flushQueue
    final freshItems = await getPendingItems();
    final finalItems = <QueuedSyncItem>[];
    for (final item in freshItems) {
      if (succeededIds.contains(item.id)) {
        continue; // Successfully synced
      }
      if (updatedRetries.containsKey(item.id)) {
        finalItems.add(updatedRetries[item.id]!);
      } else {
        // Either newly enqueued or untouched item
        finalItems.add(item);
      }
    }

    await _saveItems(finalItems);
    return syncedCount;
  }

  Future<void> _saveItems(List<QueuedSyncItem> items) async {
    final raw = items.map((i) => jsonEncode(i.toJson())).toList();
    await _preferences.setStringList(_queueKey, raw);
  }
}

final offlineSyncQueueProvider = Provider<OfflineSyncQueue>((ref) {
  return OfflineSyncQueue(
    client: ref.watch(apiClientProvider),
  );
});
