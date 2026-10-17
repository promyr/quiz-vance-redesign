import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/open_quiz/presentation/open_quiz_screen.dart';
import 'package:quiz_vance_flutter/features/quiz/data/quiz_repository.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/quiz_generation_params.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_config_screen.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';
import 'package:quiz_vance_flutter/features/simulado/presentation/simulado_config_screen.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';
import 'package:quiz_vance_flutter/shared/widgets/hard_mode_toggle.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_fonts.dart';

class _Stats extends UserStatsNotifier {
  @override
  Future<UserStats> build() async => const UserStats(
        isPremium: true,
        quizRestante: -1,
        quizLimite: -1,
      );
}

class _QuizRepository extends Mock implements QuizRepository {}

class _GenerationGuard extends Mock implements AiGenerationGuard {}

Future<void> _pumpConfig(
  WidgetTester tester,
  Widget screen, {
  QuizRepository? repository,
  AiGenerationGuard? guard,
  ValueChanged<Map<String, dynamic>>? onSession,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/config', routes: [
    GoRoute(path: '/', builder: (_, __) => const Text('Início')),
    GoRoute(path: '/config', builder: (_, __) => screen),
    GoRoute(
      path: '/session',
      name: 'quizSession',
      builder: (_, state) {
        onSession?.call(state.extra as Map<String, dynamic>);
        return const Scaffold(body: Text('Sessão iniciada'));
      },
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      userStatsNotifierProvider.overrideWith(_Stats.new),
      if (repository != null)
        quizRepositoryProvider.overrideWithValue(repository),
      if (guard != null) aiGenerationGuardProvider.overrideWithValue(guard),
    ],
    child: MaterialApp.router(
      theme: ThemeData(fontFamily: 'VisualTestFont'),
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => loadTestFonts());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final config in const <String, Widget>{
    'quiz': QuizConfigScreen(),
    'simulado': SimuladoConfigScreen(),
    'dissertativo': OpenQuizScreen(),
  }.entries) {
    testWidgets('${config.key}: modo difícil começa desligado e alterna',
        (tester) async {
      await _pumpConfig(tester, config.value);
      final toggle = find.byType(HardModeToggle);
      expect(tester.widget<HardModeToggle>(toggle).enabled, isFalse);
      expect(find.text('Questões médias e difíceis'), findsOneWidget);
      expect(find.text('Fácil'), findsNothing);
      expect(find.text('Médio'), findsNothing);
      expect(find.text('Difícil'), findsNothing);
      await tester.ensureVisible(toggle);
      await tester
          .tap(find.descendant(of: toggle, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(tester.widget<HardModeToggle>(toggle).enabled, isTrue);
      expect(find.text('Somente questões difíceis'), findsOneWidget);

      await tester
          .tap(find.descendant(of: toggle, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(tester.widget<HardModeToggle>(toggle).enabled, isFalse);
      expect(find.text('Questões médias e difíceis'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final hardMode in [false, true]) {
    testWidgets('treino infinito conserva escolha manual hard=$hardMode',
        (tester) async {
      final repository = _QuizRepository();
      final guard = _GenerationGuard();
      String? requestedDifficulty;
      int? requestedQuantity;
      Map<String, dynamic>? session;
      when(() => guard.ensureReadyForGeneration(
            overrideProvider: any(named: 'overrideProvider'),
          )).thenAnswer((_) async => 'groq');
      when(() => repository.generate(
            topic: any(named: 'topic'),
            difficulty: any(named: 'difficulty'),
            quantity: any(named: 'quantity'),
            aiProvider: any(named: 'aiProvider'),
            conteudo: any(named: 'conteudo'),
            documentName: any(named: 'documentName'),
            documentId: any(named: 'documentId'),
          )).thenAnswer((invocation) async {
        requestedDifficulty = invocation.namedArguments[#difficulty] as String;
        requestedQuantity = invocation.namedArguments[#quantity] as int;
        return const [
          Question(
            id: 'q1',
            text: 'Qual é a função da válvula?',
            options: [
              QuizOption(id: 'a', text: 'Regular a vazão'),
              QuizOption(id: 'b', text: 'Armazenar combustível'),
            ],
            correctOptionId: 'a',
          ),
        ];
      });
      await _pumpConfig(
        tester,
        const QuizConfigScreen(),
        repository: repository,
        guard: guard,
        onSession: (value) => session = value,
      );
      await tester.enterText(find.byType(TextFormField).first, 'Válvulas');
      if (hardMode) {
        final toggle = find.byType(HardModeToggle);
        await tester.ensureVisible(toggle);
        await tester.tap(
          find.descendant(of: toggle, matching: find.byType(Switch)),
        );
        await tester.pumpAndSettle();
      }
      final infiniteSwitch = find.byType(Switch).last;
      await tester.ensureVisible(infiniteSwitch);
      await tester.tap(infiniteSwitch);
      await tester.pumpAndSettle();
      final start = find.text('Iniciar Treino Infinito ⚡');
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();

      final expectedDifficulty = hardMode ? 'hard' : 'mixed';
      expect(requestedDifficulty, expectedDifficulty);
      expect(requestedQuantity, 5);
      expect(session?['infiniteMode'], isTrue);
      final params = session?['generationParams'] as QuizGenerationParams?;
      expect(params?.difficulty, expectedDifficulty);
      expect(find.text('Sessão iniciada'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
