import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

const int maxStudyDocumentBytes = 10 * 1024 * 1024;
const int maxStudyDocumentCharacters = 350000;

class StudyDocumentTooLargeException implements Exception {
  const StudyDocumentTooLargeException();
}

class StudyDocumentEmptyException implements Exception {
  const StudyDocumentEmptyException();
}

class StudyDocumentTypeException implements Exception {
  const StudyDocumentTypeException();
}

class StudyDocumentParseException implements Exception {
  final String details;
  const StudyDocumentParseException(this.details);

  @override
  String toString() => 'StudyDocumentParseException: $details';
}

Future<String> extractStudyDocumentText({
  required Uint8List bytes,
  required String extension,
  String? mimeType,
}) {
  if (bytes.length > maxStudyDocumentBytes) {
    throw const StudyDocumentTooLargeException();
  }
  final normalizedExtension = extension.toLowerCase().replaceFirst('.', '');
  _validateDocumentType(
    bytes: bytes,
    extension: normalizedExtension,
    mimeType: mimeType,
  );
  return compute(
    _extractText,
    _StudyDocumentInput(bytes, normalizedExtension),
  );
}

void _validateDocumentType({
  required Uint8List bytes,
  required String extension,
  required String? mimeType,
}) {
  if (!const {'pdf', 'txt', 'md'}.contains(extension) || bytes.isEmpty) {
    throw const StudyDocumentTypeException();
  }

  final normalizedMime = mimeType?.toLowerCase().split(';').first.trim();
  if (normalizedMime != null &&
      normalizedMime.isNotEmpty &&
      normalizedMime != 'application/octet-stream') {
    final validMime = extension == 'pdf'
        ? normalizedMime == 'application/pdf'
        : normalizedMime == 'text/plain' || normalizedMime == 'text/markdown';
    if (!validMime) throw const StudyDocumentTypeException();
  }

  if (extension == 'pdf') {
    const signature = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
    if (bytes.length < signature.length) {
      throw const StudyDocumentTypeException();
    }
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) {
        throw const StudyDocumentTypeException();
      }
    }
    return;
  }

  final sampleLength = bytes.length.clamp(0, 4096);
  var suspicious = 0;
  for (var index = 0; index < sampleLength; index++) {
    final byte = bytes[index];
    if (byte == 0) throw const StudyDocumentTypeException();
    if (byte < 0x09 || (byte > 0x0D && byte < 0x20)) suspicious++;
  }
  if (sampleLength > 0 && suspicious / sampleLength > 0.05) {
    throw const StudyDocumentTypeException();
  }
}

String _extractText(_StudyDocumentInput input) {
  final String extracted;
  if (input.extension == 'pdf') {
    try {
      final document = PdfDocument(inputBytes: input.bytes);
      try {
        extracted = PdfTextExtractor(document).extractText();
      } finally {
        document.dispose();
      }
    } catch (e) {
      throw StudyDocumentParseException(e.toString());
    }
  } else {
    extracted = utf8.decode(input.bytes, allowMalformed: true);
  }

  final normalized = extracted
      .replaceAll(RegExp(r'[ \t]{3,}'), ' ')
      .replaceAll(RegExp(r'\n{4,}'), '\n\n')
      .trim();

  if (normalized.isEmpty) {
    throw const StudyDocumentEmptyException();
  }

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
