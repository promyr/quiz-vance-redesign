import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/library/application/library_document_recovery.dart';
import 'package:quiz_vance_flutter/features/library/data/library_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_document.dart';

class _MockLibraryRepository extends Mock implements LibraryRepository {}

class _MockStudyPlanRepository extends Mock implements StudyPlanRepository {}

void main() {
  test('retoma documentos da biblioteca e importa os que terminaram', () async {
    final library = _MockLibraryRepository();
    final documents = _MockStudyPlanRepository();
    final ready = StudyDocument(
      id: 10,
      purpose: StudyDocumentPurpose.library,
      fileName: 'pronto.pdf',
      sizeBytes: 100,
      status: StudyDocumentStatus.ready,
      progress: 100,
      cargos: const [],
    );
    final extracting = StudyDocument(
      id: 11,
      purpose: StudyDocumentPurpose.library,
      fileName: 'processando.pdf',
      sizeBytes: 200,
      status: StudyDocumentStatus.extracting,
      progress: 35,
      cargos: const [],
    );
    when(
      () => documents.listDocuments(
        purpose: StudyDocumentPurpose.library,
      ),
    ).thenAnswer((_) async => [ready, extracting]);
    when(() => documents.getDocumentContent(10))
        .thenAnswer((_) async => 'Texto pronto');
    when(() => library.isDocumentDeleted(10)).thenAnswer((_) async => false);
    when(
      () => library.importProcessedDocument(
        document: ready,
        content: 'Texto pronto',
      ),
    ).thenAnswer((_) async {});

    final result = await LibraryDocumentRecovery(
      libraryRepository: library,
      documentRepository: documents,
    ).resume();

    expect(result.documents, [ready, extracting]);
    expect(result.hasPending, isTrue);
    verify(
      () => library.importProcessedDocument(
        document: ready,
        content: 'Texto pronto',
      ),
    ).called(1);
  });

  test('does not download previously deleted documents during recovery',
      () async {
    final library = _MockLibraryRepository();
    final documents = _MockStudyPlanRepository();
    const ready = StudyDocument(
      id: 10,
      purpose: StudyDocumentPurpose.library,
      fileName: 'removido.pdf',
      sizeBytes: 100,
      status: StudyDocumentStatus.ready,
      progress: 100,
      cargos: [],
    );
    when(() => documents.listDocuments(
          purpose: StudyDocumentPurpose.library,
        )).thenAnswer((_) async => [ready]);
    when(() => library.isDocumentDeleted(10)).thenAnswer((_) async => true);

    final result = await LibraryDocumentRecovery(
      libraryRepository: library,
      documentRepository: documents,
    ).resume();

    expect(result.importedCount, 0);
    expect(result.hasPending, isFalse);
    verifyNever(() => documents.getDocumentContent(10));
  });
}
