import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/shared/application/offline_sync_queue.dart';
import 'package:quiz_vance_flutter/shared/application/offline_sync_coordinator.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';

class Queue extends OfflineSyncQueue {
  final result = Completer<int>();
  int calls = 0;
  @override
  Future<int> flushQueue() {
    calls++;
    return result.future;
  }
}

void main() {
  test(
      'sync updates visible stats once and stops callback after account change',
      () async {
    AccountScopedPreferences.instance.setActiveAccountId('alice');
    final queue = Queue();
    var refreshed = 0;
    final coordinator =
        OfflineSyncCoordinator(queue, onSynced: () => refreshed++);
    final first = coordinator.synchronize();
    final second = coordinator.synchronize();
    queue.result.complete(2);
    await Future.wait([first, second]);
    expect(queue.calls, 1);
    expect(refreshed, 1);
    final other = Queue();
    final previous = OfflineSyncCoordinator(other, onSynced: () => refreshed++);
    final pending = previous.synchronize();
    AccountScopedPreferences.instance.setActiveAccountId('bob');
    other.result.complete(1);
    await pending;
    expect(refreshed, 1);
  });
}
