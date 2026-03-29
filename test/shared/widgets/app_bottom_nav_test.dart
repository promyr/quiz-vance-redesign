import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_vance_flutter/shared/widgets/app_bottom_nav.dart';

void main() {
  testWidgets('AppBottomNav navega para a rota selecionada', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <GoRoute>[
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            bottomNavigationBar: AppBottomNav(currentIndex: 0),
            body: Text('Home page'),
          ),
        ),
        GoRoute(
          path: '/quiz',
          builder: (context, state) => const Scaffold(
            bottomNavigationBar: AppBottomNav(currentIndex: 1),
            body: Text('Quiz page'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Quiz'));
    await tester.pumpAndSettle();

    expect(find.text('Quiz page'), findsOneWidget);
  });

  testWidgets('AppBottomNav expõe semântica acessível para abas',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final router = GoRouter(
        initialLocation: '/',
        routes: <GoRoute>[
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              bottomNavigationBar: AppBottomNav(currentIndex: 0),
              body: Text('Home page'),
            ),
          ),
          GoRoute(
            path: '/quiz',
            builder: (context, state) => const Scaffold(
              bottomNavigationBar: AppBottomNav(currentIndex: 1),
              body: Text('Quiz page'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.text('Quiz')),
        matchesSemantics(
          label: 'Quiz',
          hint: 'Abrir aba Quiz',
          hasTapAction: true,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });
}
