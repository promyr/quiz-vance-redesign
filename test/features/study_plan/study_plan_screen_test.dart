import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_document.dart';
import 'package:quiz_vance_flutter/features/study_plan/presentation/study_plan_screen.dart';

class _MockStudyPlanRepository extends Mock implements StudyPlanRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('edital without cargos offers manual review', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _MockStudyPlanRepository();
    const document = StudyDocument(
        id: 55,
        purpose: StudyDocumentPurpose.studyPlan,
        fileName: 'quadro-vagas.pdf',
        sizeBytes: 200,
        status: StudyDocumentStatus.needsReview,
        progress: 55,
        cargos: []);
    when(repository.getActivePlan).thenAnswer((_) async => null);
    when(() =>
            repository.listDocuments(purpose: StudyDocumentPurpose.studyPlan))
        .thenAnswer((_) async => [document]);
    when(() => repository.getDocument(55)).thenAnswer((_) async => document);
    await tester.pumpWidget(ProviderScope(overrides: [
      studyPlanRepositoryProvider.overrideWithValue(repository),
    ], child: const MaterialApp(home: StudyPlanScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Revisar edital'), findsOneWidget);
    await tester.tap(find.text('Revisar edital'));
    await tester.pumpAndSettle();
    expect(find.text('Cargo desejado'), findsOneWidget);
    expect(find.text('Continuar análise'), findsOneWidget);
    when(() => repository.selectDocumentCargo(
            documentId: 55, cargoId: 'manual', cargoTitle: 'Analista'))
        .thenAnswer((_) async => const StudyDocument(
            id: 55,
            purpose: StudyDocumentPurpose.studyPlan,
            fileName: 'quadro-vagas.pdf',
            sizeBytes: 200,
            status: StudyDocumentStatus.analyzing,
            progress: 60,
            cargos: []));
    when(() => repository.getDocument(55)).thenAnswer((_) async =>
        const StudyDocument(
            id: 55,
            purpose: StudyDocumentPurpose.studyPlan,
            fileName: 'quadro-vagas.pdf',
            sizeBytes: 200,
            status: StudyDocumentStatus.analyzing,
            progress: 60,
            cargos: []));
    await tester.enterText(find.byType(TextField), 'Analista');
    await tester.tap(find.text('Continuar análise'));
    await tester.pumpAndSettle();
    verify(() => repository.selectDocumentCargo(
        documentId: 55, cargoId: 'manual', cargoTitle: 'Analista')).called(1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('study plan date helpers', () {
    test('formatStudyPlanDate returns dd/MM/yyyy', () {
      expect(
        formatStudyPlanDate(DateTime(2027, 4, 5)),
        '05/04/2027',
      );
    });

    test('parseStudyPlanDateOrNull parses a valid date', () {
      final parsed = parseStudyPlanDateOrNull('25/03/2026');

      expect(parsed, isNotNull);
      expect(parsed!.day, 25);
      expect(parsed.month, 3);
      expect(parsed.year, 2026);
    });

    test('parseStudyPlanDateOrNull rejects invalid dates', () {
      expect(parseStudyPlanDateOrNull('31/02/2026'), isNull);
      expect(parseStudyPlanDateOrNull('2204'), isNull);
      expect(parseStudyPlanDateOrNull('2026-03-25'), isNull);
    });
  });

  testWidgets('config flow requests only a PDF edital', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: StudyPlanScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enviar novo edital em PDF'), findsOneWidget);
    expect(find.byKey(const Key('studyPlanNoticePdfButton')), findsOneWidget);
    expect(find.text('Analisar edital'), findsNothing);
    expect(find.text('Central de Editais'), findsOneWidget);
    expect(
      find.textContaining('processado em segundo plano'),
      findsOneWidget,
    );
    expect(find.textContaining('lido no aparelho'), findsNothing);
    expect(find.text('Data da Prova (Opcional)'), findsNothing);
    expect(find.text('Tópicos (Opcional)'), findsNothing);
  });

  testWidgets('failed edital exposes the reason and retry action',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _MockStudyPlanRepository();
    final failed = StudyDocument(
      id: 42,
      purpose: StudyDocumentPurpose.studyPlan,
      fileName: 'edital.pdf',
      sizeBytes: 200,
      status: StudyDocumentStatus.failed,
      progress: 62,
      cargos: const [],
      selectedCargoId: 'cargo-2',
      selectedCargoTitle: 'Analista',
      errorCode: 'payload_too_large',
      errorMessage: 'O segmento excedeu o limite do provedor.',
      canRetry: true,
    );
    when(repository.getActivePlan).thenAnswer((_) async => null);
    when(
      () => repository.listDocuments(
        purpose: StudyDocumentPurpose.studyPlan,
      ),
    ).thenAnswer((_) async => [failed]);
    when(() => repository.retryDocumentAnalysis(42)).thenAnswer(
      (_) async => StudyDocument(
        id: 42,
        purpose: StudyDocumentPurpose.studyPlan,
        fileName: 'edital.pdf',
        sizeBytes: 200,
        status: StudyDocumentStatus.analyzing,
        progress: 62,
        cargos: const [],
        selectedCargoId: 'cargo-2',
        selectedCargoTitle: 'Analista',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studyPlanRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: StudyPlanScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('O segmento excedeu o limite do provedor.'),
      findsOneWidget,
    );
    expect(find.text('Tentar análise novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar análise novamente'));
    await tester.pump();

    verify(() => repository.retryDocumentAnalysis(42)).called(1);
  });

  testWidgets('reopened ready document loads its detail before review',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = _MockStudyPlanRepository();
    const summary = StudyDocument(
      id: 43,
      purpose: StudyDocumentPurpose.studyPlan,
      fileName: 'concluido.pdf',
      sizeBytes: 200,
      status: StudyDocumentStatus.ready,
      progress: 100,
      cargos: [],
    );
    final detail = StudyDocument.fromJson({
      'id': 43,
      'purpose': 'study_plan',
      'file_name': 'concluido.pdf',
      'status': 'ready',
      'progress': 100,
      'analysis_result': {
        'cargo_id': 'analista',
        'cargo': 'Analista',
        'data_prova': '2027-03-20',
        'disciplinas': [
          {
            'nome': 'Matemática',
            'topicos': ['Porcentagem'],
            'evidencias': [
              {'pagina': 10, 'trecho': 'Matemática: Porcentagem'},
            ],
          },
        ],
      },
    });
    when(repository.getActivePlan).thenAnswer((_) async => null);
    when(() => repository.listDocuments(
          purpose: StudyDocumentPurpose.studyPlan,
        )).thenAnswer((_) async => [summary]);
    when(() => repository.getDocument(43)).thenAnswer((_) async => detail);

    await tester.pumpWidget(ProviderScope(
      overrides: [studyPlanRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: StudyPlanScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('concluido.pdf'));
    await tester.pumpAndSettle();

    verify(() => repository.getDocument(43)).called(1);
    expect(find.text('Matemática'), findsOneWidget);
    expect(find.textContaining('Porcentagem'), findsWidgets);
    expect(find.text('O edital terminou sem disciplinas confirmadas.'),
        findsNothing);
  });
}
