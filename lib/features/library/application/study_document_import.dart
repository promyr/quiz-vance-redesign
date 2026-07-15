import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

const int maxStudyDocumentBytes = 10 * 1024 * 1024;
const int maxStudyDocumentCharacters = 250000;

class StudyDocumentTooLargeException implements Exception {
  const StudyDocumentTooLargeException();
}

Future<String> extractStudyDocumentText({
  required Uint8List bytes,
  required String extension,
}) {
  if (bytes.length > maxStudyDocumentBytes) {
    throw const StudyDocumentTooLargeException();
  }
  return compute(
    _extractText,
    _StudyDocumentInput(bytes, extension.toLowerCase()),
  );
}

String _extractText(_StudyDocumentInput input) {
  final String extracted;
  if (input.extension == 'pdf') {
    final document = PdfDocument(inputBytes: input.bytes);
    try {
      extracted = PdfTextExtractor(document).extractText();
    } finally {
      document.dispose();
    }
  } else {
    extracted = utf8.decode(input.bytes, allowMalformed: true);
  }

  final normalized = extracted
      .replaceAll(RegExp(r'[ \t]{3,}'), ' ')
      .replaceAll(RegExp(r'\n{4,}'), '\n\n')
      .trim();
  if (normalized.length <= maxStudyDocumentCharacters) {
    return normalized;
  }
  return normalized.substring(0, maxStudyDocumentCharacters);
}

class _StudyDocumentInput {
  const _StudyDocumentInput(this.bytes, this.extension);

  final Uint8List bytes;
  final String extension;
}
