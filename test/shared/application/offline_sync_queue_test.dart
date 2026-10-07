import 'dart:async';
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

  test('offline local flashcard keeps content required to sync its reward',
      () async {
    await queue.enqueueItem(
        type: 'flashcard_review',
        payload: {
          'flashcard_id': 'local-42',
          'grade': 'good',
          'reviewed_at': '2026-10-06T12:00:00Z',
          'front': 'Proposição',
          'back': 'Justificativa',
          'topic': 'Matemática',
        },
        idempotencyKey: 'review-42');
    Map<String, dynamic>? sent;
    when(() => dio.post(ApiEndpoints.flashcardsReview,
        data: any(named: 'data'),
        options: any(named: 'options'))).thenAnswer((invocation) async {
      sent = Map<String, dynamic>.from(invocation.namedArguments[#data] as Map);
      return Response(
          requestOptions: RequestOptions(path: ApiEndpoints.flashcardsReview),
          data: {'xp_earned': 5});
    });
    expect(await queue.flushQueue(), 1);
    expect(sent!['front'], 'Proposição');
    expect(sent!['back'], 'Justificativa');
    expect(sent!['topic'], 'Matemática');
  });

  test('concurrent enqueue preserves both results', () async {
    await Future.wait([
      queue.enqueueItem(
          type: 'quiz_result',
          payload: {'session_id': 'one'},
          idempotencyKey: 'one'),
      queue.enqueueItem(
          type: 'quiz_result',
          payload: {'session_id': 'two'},
          idempotencyKey: 'two')
    ]);
    expect((await queue.getPendingItems()).map((i) => i.id).toSet(),
        {'one', 'two'});
  });
  test('transient connection failures stay pending after five attempts',
      () async {
    await queue.enqueueItem(
        type: 'quiz_result',
        payload: {'session_id': 'offline'},
        idempotencyKey: 'offline');
    when(() => dio.post(any(),
            data: any(named: 'data'), options: any(named: 'options')))
        .thenThrow(DioException(
            requestOptions: RequestOptions(path: '/quiz/submit'),
            type: DioExceptionType.connectionError));
    for (var i = 0; i < 6; i++) {
      await queue.flushQueue();
    }
    expect(await queue.getPendingItems(), hasLength(1));
    expect(await queue.getDeadLetterItems(), isEmpty);
  });
  test('concurrent flush calls share one network request', () async {
    await queue.enqueueItem(
        type: 'quiz_result',
        payload: {'session_id': 'one'},
        idempotencyKey: 'one');
    final response = Completer<Response<dynamic>>();
    var calls = 0;
    when(() => dio.post(any(),
        data: any(named: 'data'),
        options: any(named: 'options'))).thenAnswer((_) {
      calls++;
      return response.future;
    });
    final first = queue.flushQueue();
    final second = queue.flushQueue();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    response.complete(Response(
        requestOptions: RequestOptions(path: '/quiz/submit'),
        data: {'ok': true}));
    await Future.wait([first, second]);
    expect(calls, 1);
  });
  test('switching account during flush cannot overwrite the next account queue',
      () async {
    final prefs = AccountScopedPreferences.instance;
    prefs.setActiveAccountId('alice');
    await queue.enqueueItem(
        type: 'quiz_result',
        payload: {'session_id': 'alice'},
        idempotencyKey: 'alice');
    final response = Completer<Response<dynamic>>();
    when(() => dio.post(any(),
        data: any(named: 'data'),
        options: any(named: 'options'))).thenAnswer((_) => response.future);
    final flushing = queue.flushQueue();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    prefs.setActiveAccountId('bob');
    await queue.enqueueItem(
        type: 'quiz_result',
        payload: {'session_id': 'bob'},
        idempotencyKey: 'bob');
    response.complete(Response(
        requestOptions: RequestOptions(path: '/quiz/submit'),
        data: {'ok': true}));
    await flushing;
    expect((await queue.getPendingItems()).single.id, 'bob');
  });
  test('legacy flashcard payload is converted to the server contract',
      () async {
    await queue.enqueueItem(
        type: 'flashcard_review',
        payload: {'card_id': '12', 'grade': 2},
        idempotencyKey: 'card');
    Map<String, dynamic>? sent;
    when(() => dio.post(any(),
        data: any(named: 'data'),
        options: any(named: 'options'))).thenAnswer((call) async {
      sent = Map<String, dynamic>.from(call.namedArguments[#data] as Map);
      return Response(
          requestOptions: RequestOptions(path: '/flashcards/review'),
          data: {'ok': true});
    });
    await queue.flushQueue();
    expect(sent!['flashcard_id'], '12');
    expect(sent!['grade'], 'good');
    expect(DateTime.tryParse(sent!['reviewed_at'] as String), isNotNull);
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
        type: DioExceptionType.badResponse,
        response: Response(
            requestOptions: RequestOptions(path: ApiEndpoints.quizSubmit),
            statusCode: 422),
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
