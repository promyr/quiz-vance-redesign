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

  test('flushQueue sends quiz result to its submission endpoint', () async {
    await queue.enqueueItem(
      type: 'quiz_result',
      payload: {'score': 100},
    );

    when(
      () => dio.post(
        ApiEndpoints.quizSubmit,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.quizSubmit),
        data: {'ok': true},
      ),
    );

    final syncedCount = await queue.flushQueue();
    expect(syncedCount, 1);

    final remaining = await queue.getPendingItems();
    expect(remaining, isEmpty);
  });

  test('flushQueue sends simulado result to its submission endpoint', () async {
    await queue.enqueueItem(
      type: 'simulado_result',
      payload: {'score': 75},
      idempotencyKey: 'simulado-session-1',
    );

    when(
      () => dio.post(
        ApiEndpoints.simuladoSubmit,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.simuladoSubmit),
        data: {'ok': true},
      ),
    );

    expect(await queue.flushQueue(), 1);
    expect(await queue.getPendingItems(), isEmpty);
  });

  test('enqueue is idempotent for the same key', () async {
    await queue.enqueueItem(
      type: 'quiz_result',
      payload: {'score': 80},
      idempotencyKey: 'quiz-session-1',
    );
    await queue.enqueueItem(
      type: 'quiz_result',
      payload: {'score': 80},
      idempotencyKey: 'quiz-session-1',
    );

    expect(await queue.getPendingItems(), hasLength(1));
  });

  test('moves poison item to dead-letter instead of silently dropping it',
      () async {
    await queue.enqueueItem(
      type: 'quiz_result',
      payload: {'score': 80},
      idempotencyKey: 'quiz-session-dead',
    );
    when(
      () => dio.post(
        ApiEndpoints.quizSubmit,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.quizSubmit),
        type: DioExceptionType.connectionError,
      ),
    );

    for (var attempt = 0; attempt < 5; attempt++) {
      await queue.flushQueue();
    }

    expect(await queue.getPendingItems(), isEmpty);
    final deadLetters = await queue.getDeadLetterItems();
    expect(deadLetters, hasLength(1));
    expect(deadLetters.single.id, 'quiz-session-dead');
    expect(deadLetters.single.retryCount, 5);
  });
}
