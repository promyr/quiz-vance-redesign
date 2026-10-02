import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/features/quiz/data/quiz_repository.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_result_screen.dart';
import 'package:quiz_vance_flutter/shared/providers/gamification_provider.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_session_screen.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/shared/application/user_stats_cache_service.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';

class _Client extends ApiClient {
  final _fakeDio = Dio()
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(Response(
        requestOptions: options,
        data: <String, dynamic>{'today_questoes': 12},
      )),
    ));
  @override
  Dio get dio => _fakeDio;
}

class _BrokenCache extends UserStatsCacheService {
  @override
  Future<void> saveRemoteStatsPayload(Map<String, dynamic> payload) async {
    throw StateError('Cache unavailable');
  }

  @override
  Future<Map<String, dynamic>?> readRemoteStatsPayload() async =>
      {'today_questoes': 0};
}

class _BlockedGamification extends GamificationNotifier {
  final blocked = Completer<void>();
  @override
  Future<GamificationState> build() async => const GamificationState();
  @override
  Future<void> recordQuizCompletion(
          {required String eventId, required int xpEarned}) =>
      blocked.future;
}

class _RecordingRepository extends QuizRepository {
  _RecordingRepository() : super(_Client());
  int calls = 0;
  final pending = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> submit(
      {required String sessionId,
      required List<Map<String, dynamic>> answers,
      required Duration timeTaken,
      required int total,
      required int correct,
      required int xpEarned,
      String? topic}) {
    calls++;
    return pending.future;
  }
}

void main() {
  testWidgets('statistics submission is not blocked by gamification',
      (tester) async {
    final repository = _RecordingRepository();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          quizRepositoryProvider.overrideWithValue(repository),
          apiClientProvider.overrideWithValue(_Client()),
          gamificationProvider.overrideWith(_BlockedGamification.new),
        ],
        child: const MaterialApp(
            home: QuizResultScreen(
                result: QuizResult(
          sessionId: 'priority',
          total: 1,
          correct: 1,
          xpEarned: 10,
          timeTaken: Duration(seconds: 10),
          answers: [],
        )))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.calls, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('remote statistics survive a local cache write failure', () async {
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(_Client()),
      userStatsCacheServiceProvider.overrideWithValue(_BrokenCache()),
    ]);
    addTearDown(container.dispose);
    final provider =
        FutureProvider<Map<String, dynamic>>(fetchUserStatsPayload);
    final stats = await container.read(provider.future);
    expect(stats['today_questoes'], 12);
  });

  for (final systemBack in [false, true]) {
    testWidgets('exit keeps current answer (Android back: $systemBack)',
        (tester) async {
      QuizResult? captured;
      final question = Question.fromJson({
        'id': 'progress',
        'text': 'Pergunta de teste',
        'options': [
          {'id': 'a', 'text': 'Correta'},
          {'id': 'b', 'text': 'Errada'}
        ],
        'correct_answer': 'A',
      });
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) =>
                QuizSessionScreen(questions: [question, question])),
        GoRoute(
            path: '/result',
            name: 'quizResult',
            builder: (_, state) {
              captured = (state.extra as Map)['result'] as QuizResult;
              return const Scaffold(body: Text('Resultado registrado'));
            }),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        activePlanProvider.overrideWith((ref) async => null),
      ], child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correta'));
      await tester.pumpAndSettle();
      if (systemBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text('←'));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!.total, 1);
      expect(captured!.correct, 1);
      expect(captured!.answers, hasLength(1));
      expect(captured!.xpEarned, 10);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
