import '../../study_plan/domain/study_document.dart';

class StudyDocumentPollingException implements Exception {
  const StudyDocumentPollingException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<StudyDocument> waitForStudyDocument({
  required int documentId,
  required Future<StudyDocument> Function(int documentId) fetch,
  Duration interval = const Duration(seconds: 2),
  int maxAttempts = 300,
  void Function(StudyDocument document)? onUpdate,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final document = await fetch(documentId);
    onUpdate?.call(document);
    if (document.status == StudyDocumentStatus.ready ||
        document.status == StudyDocumentStatus.awaitingSelection ||
        document.status == StudyDocumentStatus.needsReview) {
      return document;
    }
    if (document.status == StudyDocumentStatus.failed) {
      throw StudyDocumentPollingException(
        document.errorMessage ?? 'Falha ao processar o PDF.',
      );
    }
    if (attempt + 1 < maxAttempts && interval > Duration.zero) {
      await Future<void>.delayed(interval);
    }
  }
  throw const StudyDocumentPollingException(
    'O PDF continua em processamento. Ele permanecera salvo para retomada.',
  );
}
