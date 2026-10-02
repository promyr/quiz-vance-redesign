import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/library/application/study_document_import.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('extracts text from a valid PDF', () async {
    final document = PdfDocument();
    document.pages.add().graphics.drawString(
          'Titulo teste Texto',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
        );
    final bytes = Uint8List.fromList(await document.save());
    document.dispose();

    final text = await extractStudyDocumentText(
      bytes: bytes,
      extension: 'pdf',
      mimeType: 'application/pdf',
    );

    expect(text, contains('Titulo teste'));
  });

  test('accepts a PDF header with a provider prefix', () async {
    final document = PdfDocument();
    document.pages.add().graphics.drawString(
          'PDF com prefixo',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
        );
    final original = Uint8List.fromList(await document.save());
    document.dispose();

    final bytes = Uint8List.fromList(<int>[0, 1, 2, ...original]);
    final text = await extractStudyDocumentText(
      bytes: bytes,
      extension: '',
      mimeType: 'application/pdf',
    );

    expect(text, contains('PDF com prefixo'));
  });

  test('rejects text files because the library accepts PDF only', () {
    expect(
      () => extractStudyDocumentText(
        bytes: Uint8List.fromList(utf8.encode('texto')),
        extension: 'txt',
      ),
      throwsA(isA<StudyDocumentTypeException>()),
    );
  });

  test('rejects a file renamed to pdf without a PDF signature', () {
    expect(
      () => extractStudyDocumentText(
        bytes: Uint8List.fromList(utf8.encode('not really a pdf')),
        extension: 'pdf',
        mimeType: 'application/pdf',
      ),
      throwsA(isA<StudyDocumentTypeException>()),
    );
  });

  test('rejects binary content renamed to txt', () {
    expect(
      () => extractStudyDocumentText(
        bytes: Uint8List.fromList([0, 1, 2, 3, 0, 255]),
        extension: 'txt',
        mimeType: 'text/plain',
      ),
      throwsA(isA<StudyDocumentTypeException>()),
    );
  });
}
