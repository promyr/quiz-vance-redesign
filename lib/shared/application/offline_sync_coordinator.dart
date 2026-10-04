import 'account_scoped_preferences.dart';
import 'offline_sync_queue.dart';

/// One sync pass per trigger, without blocking navigation or authentication.
class OfflineSyncCoordinator {
  OfflineSyncCoordinator(this.queue, {required this.onSynced});
  final OfflineSyncQueue queue;
  final void Function() onSynced;
  Future<void>? _running;
  bool _disposed = false;
  void dispose() {
    _disposed = true;
  }

  Future<void> synchronize() {
    if (_disposed || AccountScopedPreferences.instance.activeAccountId == null) {
      return Future.value();
    }
    final running = _running;
    if (running != null) return running;
    final account = AccountScopedPreferences.instance.activeAccountId;
    late final Future<void> operation;
    operation = () async {
      try {
        final count = await queue.flushQueue();
        if (!_disposed &&
            count > 0 &&
            account == AccountScopedPreferences.instance.activeAccountId) {
          onSynced();
        }
      } catch (_) {
        /* Local or network failure leaves the queue for the next pass. */
      } finally {
        if (identical(_running, operation)) _running = null;
      }
    }();
    _running = operation;
    return operation;
  }
}
