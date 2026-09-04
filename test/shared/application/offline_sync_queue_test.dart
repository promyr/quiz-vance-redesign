import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:quiz_vance_flutter/shared/application/offline_sync_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApiClient extends Mock implements ApiClient {}
class _MockDio extends Mock implements Dio {}

void main() {
  late OfflineSyncQueue queue;
  late _MockApiClient apiClient;
  late _MockDio dio;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountScopedPreferences.instance.setActiveAccountId(null);

    apiClient = _MockApiClient();
    dio = _MockDio();
    when(() => apiClient.dio).thenReturn(dio);

    queue = OfflineSyncQueue(
      client: apiClient,
      preferences: AccountScopedPreferences.instance,
    );
  });

  test('enqueues item and retrieves pending list', () async {
    await queue.enqueueItem(
      type: 'quiz_result',
      payload: {'score': 90, 'total': 10},
    );

    final pending = await queue.getPendingItems();
    expect(pending.length, 1);
    expect(pending.first.type, 'quiz_result');
    expect(pending.first.payload['score'], 90);
  });

  test('flushQueue sends items to backend API and clears queue', () async {
    await queue.enqueueItem(
      type: 'quiz_result',
      payload: {'score': 100},
    );

    when(
      () => dio.post(
        ApiEndpoints.userStats,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.userStats),
        data: {'ok': true},
      ),
    );

    final syncedCount = await queue.flushQueue();
    expect(syncedCount, 1);

    final remaining = await queue.getPendingItems();
    expect(remaining, isEmpty);
  });
}
