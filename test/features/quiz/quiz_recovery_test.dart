import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/resume_quiz_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_session_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:quiz_vance_flutter/shared/application/document_text_cache.dart';
import 'package:quiz_vance_flutter/features/quiz/data/quiz_recovery_store.dart';
import 'package:quiz_vance_flutter/core/content/relevant_study_material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountScopedPreferences.instance.setActiveAccountId('alice');
  });
  test(
      'checkpoint preserves questions and answers only for its account and session',
      () async {
    final store = QuizRecoveryStore();
    await store.save('plan/session', {
      'questions': [
        {'id': 'q1'}
      ],
      'answers': ['a'],
      'index': 1
    });
    expect((await store.load('plan/session'))!['answers'], ['a']);
    expect(await store.load('other/session'), isNull);
    AccountScopedPreferences.instance.setActiveAccountId('bob');
    expect(await store.load('plan/session'), isNull);
    AccountScopedPreferences.instance.setActiveAccountId('alice');
    await store.clear('plan/session');
    expect(await store.load('plan/session'), isNull);
  });
  testWidgets(
      'reopens same plan session with saved question and selected answer',
      (tester) async {
    await QuizRecoveryStore().save('plan:p/session:s', {
      'questions': [
        {
          'id': 'q1',
          'text': 'Pergunta recuperada',
          'options': [
            {'id': 'a', 'text': 'Resposta salva'},
            {'id': 'b', 'text': 'Outra'}
          ],
          'correct_option_id': 'a',
          'explanation': 'Explicacao recuperada'
        }
      ],
      'answers': [],
      'index': 0,
      'selected': 'a',
      'answered': true,
      'elapsed': 45,
    });
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: QuizSessionScreen(
                questions: [],
                generationParams: QuizGenerationParams(
                    topic: 'Tema',
                    difficulty: 'medium',
                    aiProvider: null,
                    planId: 'p',
                    studySessionId: 's')))));
    await tester.pumpAndSettle();
    expect(find.text('Pergunta recuperada'), findsOneWidget);
    expect(find.text('Você acertou! Explicação do Assunto'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
      'latest checkpoint exposes a resume entry without needing new generation',
      () async {
    final store = QuizRecoveryStore();
    await store.save('first', {
      'questions': [
        {'id': 'one'}
      ]
    });
    await store.save('second', {
      'questions': [
        {'id': 'two'}
      ]
    });
    expect((await store.latest())!['key'], 'second');
    await store.clear('second');
    expect((await store.latest())!['key'], 'first');
  });
  testWidgets('resume button sends saved questions without new configuration',
      (tester) async {
    await QuizRecoveryStore().save('regular', {
      'questions': [
        {
          'id': 'q1',
          'text': 'Salva',
          'options': [
            {'id': 'a', 'text': 'Correta'}
          ],
          'correct_option_id': 'a'
        }
      ],
      'index': 0,
      'answers': [],
      'elapsed': 20
    });
    Map<String, dynamic>? captured;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: ResumeQuizCard())),
      GoRoute(
          path: '/session',
          name: 'quizSession',
          builder: (_, state) {
            captured = state.extra as Map<String, dynamic>;
            return const Text('Retomada');
          })
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retomar quiz pausado'));
    await tester.pumpAndSettle();
    expect(captured!['recoveryKey'], 'regular');
    expect((captured!['questions'] as List).length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('corrupt checkpoint is safely ignored', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account:alice:quiz_recovery_v1', 'broken');
    expect(await QuizRecoveryStore().load('session'), isNull);
  });
  test('relevance selection reaches subject beyond the opening pages', () {
    final text =
        '${List.filled(300, 'Biologia celular e organismos vivos.').join('\n')}\nDireito constitucional: direitos fundamentais e liberdade.\n';
    final selected = selectRelevantStudyMaterial(
        text, 'Direito constitucional; direitos fundamentais',
        maxChars: 1000);
    expect(selected, contains('direitos fundamentais'));
    expect(selected.length, lessThanOrEqualTo(1000));
  });
  test('cache avoids duplicate loads but separates accounts and invalidation',
      () async {
    final cache = DocumentTextCache();
    var calls = 0;
    Future<String> fetch() async {
      calls++;
      return 'texto do PDF';
    }

    expect(await cache.get(12, fetch), 'texto do PDF');
    expect(await cache.get(12, fetch), 'texto do PDF');
    expect(calls, 1);
    await cache.invalidate(12);
    await cache.get(12, fetch);
    expect(calls, 2);
    AccountScopedPreferences.instance.setActiveAccountId('bob');
    await cache.get(12, fetch);
    expect(calls, 3);
  });
  test('concurrent requests share only one document fetch', () async {
    final cache = DocumentTextCache();
    var calls = 0;
    Future<String> fetch() async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return 'texto';
    }

    final values =
        await Future.wait([cache.get(5, fetch), cache.get(5, fetch)]);
    expect(values, ['texto', 'texto']);
    expect(calls, 1);
  });
  test('failed and empty document loads are not cached', () async {
    final cache = DocumentTextCache();
    var calls = 0;
    Future<String> fetch() async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return calls == 2 ? '' : 'ready';
    }

    await expectLater(cache.get(1, fetch), throwsStateError);
    expect(await cache.get(1, fetch), '');
    expect(await cache.get(1, fetch), 'ready');
    expect(calls, 3);
  });
}
