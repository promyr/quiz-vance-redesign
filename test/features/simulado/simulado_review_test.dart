import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/simulado/data/simulado_repository.dart';
import 'package:quiz_vance_flutter/features/simulado/domain/simulado_review.dart';
import 'package:quiz_vance_flutter/features/simulado/presentation/simulado_result_screen.dart';
import 'package:quiz_vance_flutter/features/simulado/presentation/simulado_review_screen.dart';
import 'package:quiz_vance_flutter/shared/providers/gamification_provider.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('reviewableSimuladoAnswers retorna apenas respostas erradas', () {
    final result = _buildResult();

    final wrongAnswers = reviewableSimuladoAnswers(result);

    expect(wrongAnswers, hasLength(1));
    expect(wrongAnswers.single.selectedOptionId, equals('opt_a'));
    expect(wrongAnswers.single.isCorrect, isFalse);
  });

  testWidgets('resultado mostra CTA de revisao quando houver erros',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          simuladoRepositoryProvider.overrideWith((ref) {
            return _FakeSimuladoRepository();
          }),
          gamificationProvider.overrideWith(_FakeGamificationNotifier.new),
          userStatsNotifierProvider.overrideWith(_FakeUserStatsNotifier.new),
        ],
        child: MaterialApp(
          home: SimuladoResultScreen(result: _buildResult()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Revisar erros (1)'), findsOneWidget);
    expect(find.text('Novo simulado'), findsOneWidget);
  });

  testWidgets('revisao mostra resposta escolhida e correta', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SimuladoReviewScreen(result: _reviewResult),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sua resposta'), findsOneWidget);
    expect(find.text('Correta'), findsOneWidget);
    expect(find.text('Resposta correta'), findsOneWidget);
    expect(find.textContaining('opt_a'), findsNothing);
    expect(
      find.textContaining('Aprender a investir em acoes'),
      findsWidgets,
    );
    expect(
      find.textContaining('Gerenciar o orcamento pessoal e familiar'),
      findsWidgets,
    );
  });
}

const _reviewQuestion = Question(
  id: 'q1',
  text: 'O que e educacao financeira?',
  options: [
    QuizOption(id: 'opt_a', text: 'Aprender a investir em acoes'),
    QuizOption(
      id: 'opt_b',
      text: 'Gerenciar o orcamento pessoal e familiar',
      isCorrect: true,
    ),
    QuizOption(id: 'opt_c', text: 'Estudar teoria economica'),
    QuizOption(id: 'opt_d', text: 'Fazer contabilidade empresarial'),
  ],
  correctOptionId: 'opt_b',
  explanation:
      'Educacao financeira e aprender a gerenciar o orcamento pessoal e familiar.',
  topic: 'Educacao Financeira',
);

const _reviewResult = QuizResult(
  sessionId: 'session-1',
  total: 2,
  correct: 1,
  xpEarned: 5,
  timeTaken: Duration(minutes: 2, seconds: 30),
  answers: [
    QuestionAnswer(
      question: _reviewQuestion,
      selectedOptionId: 'opt_a',
      isCorrect: false,
    ),
    QuestionAnswer(
      question: _reviewQuestion,
      selectedOptionId: 'opt_b',
      isCorrect: true,
    ),
  ],
);

QuizResult _buildResult() => _reviewResult;

class _FakeSimuladoRepository extends SimuladoRepository {
  _FakeSimuladoRepository() : super(ApiClient());

  @override
  Future<void> submitResult(Map<String, dynamic> payload) async {}
}

class _FakeGamificationNotifier extends GamificationNotifier {
  @override
  Future<GamificationState> build() async => const GamificationState();

  @override
  Future<void> recordQuizCompletion({
    required String eventId,
    required int xpEarned,
  }) async {}
}

class _FakeUserStatsNotifier extends UserStatsNotifier {
  @override
  Future<UserStats> build() async => const UserStats();

  @override
  Future<void> refresh() async {
    state = const AsyncData(UserStats());
  }
}
