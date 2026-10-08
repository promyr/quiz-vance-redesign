import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/features/error_notebook/data/error_notebook_repository.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/history/data/history_repository.dart';
import 'package:quiz_vance_flutter/features/conquistas/data/achievement_repository.dart';

class Client extends Mock implements ApiClient {}

class Network extends Mock implements Dio {}

Question question(String id) => Question(
    id: id,
    text: '2 + 2?',
    options: const [
      QuizOption(id: 'a', text: '4', isCorrect: true),
      QuizOption(id: 'b', text: '3')
    ],
    correctOptionId: 'a');
QuestionAnswer wrong(String id) => QuestionAnswer(
    question: question(id), selectedOptionId: 'b', isCorrect: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Caderno de erros com SQLite real isolado', () {
    late ErrorNotebookRepository repo;
    setUp(() async {
      final directory = await Directory.systemTemp.createTemp('notebook-');
      await LocalStorage.instance.configureForTesting(
          databasePath: '${directory.path}/qa.db',
          keyStore: MemoryLocalStorageKeyStore());
      await LocalStorage.instance.init();
      LocalStorage.instance.setActiveAccountId('qa-a');
      repo = ErrorNotebookRepository();
    });
    tearDown(() async {
      await LocalStorage.instance.resetForTesting();
    });
    test('erro, dois acertos, novo erro e limpeza preservam progresso',
        () async {
      await repo.recordWrongQuestions(
          wrongAnswers: [wrong('q')], topic: 'Matemática');
      await repo.markQuestionMastered('q');
      expect((await repo.getErrorQuestions()).single.consecutiveCorrect, 1);
      await repo.markQuestionMastered('q');
      expect(await repo.getErrorQuestions(), isEmpty);
      await repo.recordWrongQuestions(
          wrongAnswers: [wrong('q')], topic: 'Matemática');
      var item = (await repo.getErrorQuestions()).single;
      expect(item.timesFailed, 2);
      expect(item.consecutiveCorrect, 0);
      await repo.markQuestionMastered('q');
      await repo.markQuestionMastered('q');
      await repo.clearMastered();
      expect(await repo.getErrorQuestions(includeMastered: true), isEmpty);
    });
    test('troca de conta isola e restaura caderno', () async {
      await repo.recordWrongQuestions(wrongAnswers: [wrong('a')], topic: 'A');
      LocalStorage.instance.setActiveAccountId('qa-b');
      expect(await repo.getErrorQuestions(), isEmpty);
      await repo.recordWrongQuestions(wrongAnswers: [wrong('b')], topic: 'B');
      LocalStorage.instance.setActiveAccountId('qa-a');
      expect((await repo.getErrorQuestions()).single.id, 'a');
    });
    test('retry concorrente e reabertura contam uma falha por sessão',
        () async {
      await Future.wait(List.generate(
          3,
          (_) => repo.recordWrongQuestions(
              wrongAnswers: [wrong('same')],
              topic: 'A',
              sessionId: 'session-1')));
      repo = ErrorNotebookRepository();
      await repo.recordWrongQuestions(
          wrongAnswers: [wrong('same')], topic: 'A', sessionId: 'session-1');
      expect((await repo.getErrorQuestions()).single.timesFailed, 1);
      await repo.recordWrongQuestions(
          wrongAnswers: [wrong('same')], topic: 'A', sessionId: 'session-2');
      expect((await repo.getErrorQuestions()).single.timesFailed, 2);
    });
    test('duas gravações simultâneas não perdem questões distintas', () async {
      await Future.wait([
        repo.recordWrongQuestions(wrongAnswers: [wrong('first')], topic: 'A'),
        repo.recordWrongQuestions(wrongAnswers: [wrong('second')], topic: 'B'),
      ]);
      expect((await repo.getErrorQuestions()).map((e) => e.id).toSet(),
          {'first', 'second'});
    });
  });
  group('Histórico e conquistas', () {
    late Client client;
    late Network dio;
    setUp(() {
      client = Client();
      dio = Network();
      when(() => client.dio).thenReturn(dio);
    });
    test('histórico preserva resultado real e data', () async {
      when(() => dio.get(ApiEndpoints.quizHistory,
              queryParameters: any(named: 'queryParameters')))
          .thenAnswer((_) async =>
              Response(requestOptions: RequestOptions(path: '/'), data: {
                'history': [
                  {
                    'event_id': 'q1',
                    'total': 10,
                    'correct': 7,
                    'xp_earned': 35,
                    'accuracy': 70,
                    'created_at': '2026-10-07T12:00:00Z'
                  }
                ]
              }));
      final row = (await HistoryRepository(client).getHistory()).single;
      expect(row.eventId, 'q1');
      expect(row.wrong, 3);
      expect(row.xpEarned, 35);
    });
    test('histórico offline mostra erro recuperável', () async {
      when(() => dio.get(ApiEndpoints.quizHistory,
              queryParameters: any(named: 'queryParameters')))
          .thenThrow(DioException(
              requestOptions: RequestOptions(path: '/'),
              type: DioExceptionType.connectionError));
      await expectLater(HistoryRepository(client).getHistory(),
          throwsA(isA<RemoteServiceException>()));
    });
    test('conquistas remotas retornam códigos e ignoram vazio', () async {
      when(() => dio.get(ApiEndpoints.userAchievements)).thenAnswer((_) async =>
          Response(requestOptions: RequestOptions(path: '/'), data: {
            'achievements': [
              {'achievement_id': 'first_quiz'},
              {'achievement_id': ''}
            ]
          }));
      expect(await AchievementRepository(client).getAchievements(),
          ['first_quiz']);
    });
    test('conquistas indisponíveis não derrubam inicialização', () async {
      when(() => dio.get(ApiEndpoints.userAchievements))
          .thenThrow(DioException(requestOptions: RequestOptions(path: '/')));
      expect(await AchievementRepository(client).getAchievements(), isEmpty);
    });
  });
}
