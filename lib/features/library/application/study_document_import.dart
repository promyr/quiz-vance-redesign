import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'study_document_pdf_format.dart';

// Timeout para extração de PDF — evita travar infinitamente em PDFs corrompidos
const Duration _kPdfExtractTimeout = Duration(seconds: 90);

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
}) async {
  final normalizedExtension = extension.toLowerCase().replaceFirst('.', '');
  final normalizedMime = mimeType?.toLowerCase().split(';').first.trim();
  final effectiveExtension =
      normalizedExtension == 'pdf' || normalizedMime == 'application/pdf'
          ? 'pdf'
          : normalizedExtension;
  _validateDocumentType(
    bytes: bytes,
    extension: effectiveExtension,
    mimeType: mimeType,
  );

  _StudyDocumentResult result;
  try {
    // Roda em isolate com timeout — evita travar em PDFs corrompidos/com senha
    result = await compute(
      _extractTextIsolate,
      _StudyDocumentInput(bytes, effectiveExtension),
    ).timeout(
      _kPdfExtractTimeout,
      onTimeout: () => const _StudyDocumentResult(
        errorType: 'parse',
        errorMessage:
            'A extração do PDF ultrapassou 90 segundos. Tente novamente ou use uma versão otimizada do PDF.',
      ),
    );
  } catch (e) {
    // Nunca re-executa na main thread (evitava travar a UI)
    result = _StudyDocumentResult(
      errorType: 'parse',
      errorMessage: e.toString(),
    );
  }

  if (result.errorType == 'empty') {
    throw const StudyDocumentEmptyException();
  }
  if (result.errorType == 'type') {
    throw const StudyDocumentTypeException();
  }
  if (result.errorType == 'parse') {
    throw StudyDocumentParseException(
        result.errorMessage ?? 'Não foi possível ler o PDF.');
  }

  return result.text ?? '';
}

void _validateDocumentType({
  required Uint8List bytes,
  required String extension,
  required String? mimeType,
}) {
  final normalizedMime = mimeType?.toLowerCase().split(';').first.trim();
  final extensionIsPdf = extension == 'pdf';
  final mimeIsPdf = normalizedMime == 'application/pdf';

  // Android document providers occasionally omit the extension. In that
  // case the MIME type plus the binary signature are authoritative.
  if ((!extensionIsPdf && !mimeIsPdf) || bytes.isEmpty) {
    throw const StudyDocumentTypeException();
  }

  if (normalizedMime != null &&
      normalizedMime.isNotEmpty &&
      normalizedMime != 'application/octet-stream') {
    final validMime = normalizedMime == 'application/pdf';
    if (!validMime) throw const StudyDocumentTypeException();
  }

  if (extensionIsPdf || mimeIsPdf) {
    if (hasPdfSignature(bytes)) return;
    throw const StudyDocumentTypeException();
  }
}

class _StudyDocumentResult {
  const _StudyDocumentResult({
    this.text,
    this.errorType,
    this.errorMessage,
  });

  final String? text;
  final String? errorType;
  final String? errorMessage;
}

_StudyDocumentResult _extractTextIsolate(_StudyDocumentInput input) {
  try {
    late String extracted;
    if (input.extension == 'pdf') {
      try {
        final document = PdfDocument(inputBytes: input.bytes);
        try {
          extracted = PdfTextExtractor(document).extractText();
        } finally {
          document.dispose();
        }
      } catch (e) {
        return _StudyDocumentResult(
          errorType: 'parse',
          errorMessage: e.toString(),
        );
      }

      // Normaliza espaços excessivos preservando estrutura de linhas
    }

    final normalized = extracted
        .replaceAll(RegExp(r'[ \t]{3,}'), ' ')
        .replaceAll(RegExp(r'\n{4,}'), '\n\n')
        .trim();

    if (normalized.isEmpty) {
      return const _StudyDocumentResult(errorType: 'empty');
    }

    return _StudyDocumentResult(text: normalized);
  } catch (e) {
    return _StudyDocumentResult(
      errorType: 'parse',
      errorMessage: e.toString(),
    );
  }
}

class _StudyDocumentInput {
  const _StudyDocumentInput(this.bytes, this.extension);

  final Uint8List bytes;
  final String extension;
}
