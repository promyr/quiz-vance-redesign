import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_vance_flutter/features/library/data/library_repository.dart';
import 'package:quiz_vance_flutter/features/library/presentation/library_screen.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_document.dart';

class _MockLibraryRepository extends Mock implements LibraryRepository {}

class _MockStudyPlanRepository extends Mock implements StudyPlanRepository {}

Future<void> _pumpEmptyLibrary(WidgetTester tester, {GoRouter? router}) async {
  final libraryRepository = _MockLibraryRepository();
  final documentRepository = _MockStudyPlanRepository();
  when(
    () => documentRepository.listDocuments(
      purpose: StudyDocumentPurpose.library,
    ),
  ).thenAnswer((_) async => const []);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(libraryRepository),
        libraryFilesProvider.overrideWith((ref) async => const []),
        studyPlanRepositoryProvider.overrideWithValue(documentRepository),
      ],
      child: router == null
          ? const MaterialApp(home: LibraryScreen())
          : MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menu da biblioteca abre plano de estudos e permite voltar',
      (tester) async {
    final router = GoRouter(initialLocation: '/library', routes: [
      GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
      GoRoute(
          path: '/study-plan',
          builder: (_, __) => const Scaffold(body: Text('Plano aberto'))),
    ]);
    addTearDown(router.dispose);
    await _pumpEmptyLibrary(tester, router: router);
    await tester.tap(find.byTooltip('Menu da Biblioteca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plano de estudos'));
    await tester.pumpAndSettle();
    expect(find.text('Plano aberto'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('📚 Biblioteca'), findsOneWidget);
  });

  testWidgets('biblioteca vazia exibe uma unica acao para adicionar material',
      (tester) async {
    await _pumpEmptyLibrary(tester);

    expect(find.byKey(const Key('libraryAddMaterialButton')), findsOneWidget);
    expect(find.text('+ Adicionar material'), findsNothing);
  });

  testWidgets('modo PDF exibe uma unica acao de arquivo e nenhum salvar',
      (tester) async {
    await _pumpEmptyLibrary(tester);

    await tester.tap(find.byKey(const Key('libraryAddMaterialButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Selecionar PDF'), findsOneWidget);
    expect(find.text('Salvar'), findsNothing);
    expect(find.text('Nome/Título'), findsNothing);
  });
}
