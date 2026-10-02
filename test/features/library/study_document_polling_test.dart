import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/library/application/study_document_polling.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_document.dart';

StudyDocument _document(StudyDocumentStatus status, {String? error}) {
  return StudyDocument(
    id: 1,
    purpose: StudyDocumentPurpose.library,
    fileName: 'material.pdf',
    sizeBytes: 20,
    status: status,
    progress: status == StudyDocumentStatus.ready ? 100 : 50,
    cargos: const [],
    errorMessage: error,
  );
}

void main() {
  test('polls until the durable PDF job is ready', () async {
    final states = [
      _document(StudyDocumentStatus.extracting),
      _document(StudyDocumentStatus.ready),
    ];

    final result = await waitForStudyDocument(
      documentId: 1,
      fetch: (_) async => states.removeAt(0),
      interval: Duration.zero,
      maxAttempts: 3,
    );

    expect(result.status, StudyDocumentStatus.ready);
  });

  test('surfaces the sanitized backend failure', () async {
    await expectLater(
      () => waitForStudyDocument(
        documentId: 1,
        fetch: (_) async => _document(
          StudyDocumentStatus.failed,
          error: 'PDF protegido por senha.',
        ),
        interval: Duration.zero,
        maxAttempts: 3,
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('PDF protegido por senha'),
        ),
      ),
    );
  });
}
