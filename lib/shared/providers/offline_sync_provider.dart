import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/history/data/history_repository.dart';
import '../application/offline_sync_coordinator.dart';
import '../application/offline_sync_queue.dart';
import 'account_session_epoch_provider.dart';
import 'user_provider.dart';

final offlineSyncCoordinatorProvider = Provider<OfflineSyncCoordinator>((ref) {
  ref.watch(accountSessionEpochProvider);
  final coordinator =
      OfflineSyncCoordinator(ref.watch(offlineSyncQueueProvider), onSynced: () {
    ref.invalidate(userStatsNotifierProvider);
    ref.invalidate(userStatsProvider);
    ref.invalidate(activityHistoryProvider);
  });
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
