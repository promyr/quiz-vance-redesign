import '../../study_plan/data/study_plan_repository.dart';
import '../../study_plan/domain/study_document.dart';
import '../data/library_repository.dart';

class LibraryDocumentRecoveryResult {
  const LibraryDocumentRecoveryResult({
    required this.documents,
    required this.importedCount,
  });

  final List<StudyDocument> documents;
  final int importedCount;

  bool get hasPending =>
      documents.any((document) => document.status.isProcessing);
}

class LibraryDocumentRecovery {
  const LibraryDocumentRecovery({
    required this.libraryRepository,
    required this.documentRepository,
  });

  final LibraryRepository libraryRepository;
  final StudyPlanRepository documentRepository;

  Future<LibraryDocumentRecoveryResult> resume() async {
    final documents = await documentRepository.listDocuments(
      purpose: StudyDocumentPurpose.library,
    );
    var importedCount = 0;
    for (final document in documents) {
      if (document.status != StudyDocumentStatus.ready) continue;
      if (await libraryRepository.isDocumentDeleted(document.id)) continue;
      final content = await documentRepository.getDocumentContent(document.id);
      if (content.trim().isEmpty) continue;
      await libraryRepository.importProcessedDocument(
        document: document,
        content: content,
      );
      importedCount++;
    }
    return LibraryDocumentRecoveryResult(
      documents: documents,
      importedCount: importedCount,
    );
  }
}
