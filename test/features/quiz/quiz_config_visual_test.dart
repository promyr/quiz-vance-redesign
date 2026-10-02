import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_config_screen.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUserStatsNotifier extends UserStatsNotifier {
  @override
  Future<UserStats> build() async => const UserStats(
        quizRestante: 5,
        quizLimite: 5,
      );
}

void main() {
  testWidgets('configuracao do quiz usa cabecalho visual atualizado',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(
      initialLocation: '/quiz',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Inicio')),
        ),
        GoRoute(
          path: '/quiz',
          builder: (_, __) => const QuizConfigScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userStatsNotifierProvider.overrideWith(_FakeUserStatsNotifier.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Novo Desafio'), findsOneWidget);
    expect(find.text('Qual assunto você quer dominar hoje?'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.text('Novo Quiz'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
