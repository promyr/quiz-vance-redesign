import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/library/domain/material_chapters.dart';
import 'package:quiz_vance_flutter/features/library/data/material_scope_store.dart';
import 'package:quiz_vance_flutter/features/library/presentation/study_package_screen.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/quiz_generation_params.dart';
import 'package:quiz_vance_flutter/shared/widgets/app_bottom_nav.dart';

void main() {
  for (final fileId in [56, -56]) {
    testWidgets('quiz do pacote preserva recorte e biblioteca ativa $fileId',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final file = LibraryFile(
          id: fileId,
          nome: 'Livro.pdf',
          conteudo:
              'Capítulo 1 - Frações\nFrações dividem inteiros em partes.\nCapítulo 2 - Porcentagens\nPorcentagens representam proporções por cem.',
          criadoEm: DateTime(2026));
      await MaterialScopeStore()
          .save(file, [detectMaterialChapters(file.conteudo).last]);
      final package = StudyPackage.fromJson({
        'titulo': 'Pacote',
        'topicos_principais': ['Porcentagens']
      });
      QuizGenerationParams? received;
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) =>
                StudyPackageScreen(package: package, file: file)),
        GoRoute(
            path: '/quiz',
            builder: (_, __) => const Text('Configuração indevida')),
        GoRoute(
            path: '/session',
            name: 'quizSession',
            builder: (_, state) {
              received = (state.extra as Map)['generationParams'];
              return const Text('Quiz direto');
            }),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      expect(
          tester.widget<AppBottomNav>(find.byType(AppBottomNav)).currentIndex,
          2);
      await tester.ensureVisible(find.text('Iniciar Quiz com este Material'));
      await tester.tap(find.text('Iniciar Quiz com este Material'));
      await tester.pumpAndSettle();
      expect(received, isNotNull);
      expect(received!.documentId, fileId < 0 ? 56 : isNull);
      expect(received!.conteudo, contains('proporções'));
      expect(received!.conteudo, isNot(contains('dividem inteiros')));
    });
  }
}
