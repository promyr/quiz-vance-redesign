import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/library/application/study_document_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalizes imported text', () async {
    final text = await extractStudyDocumentText(
      bytes: Uint8List.fromList(utf8.encode('Titulo    teste\n\n\n\nTexto')),
      extension: 'txt',
    );

    expect(text, 'Titulo teste\n\nTexto');
  });

  test('rejects a document above the safe byte limit', () {
    expect(
      () => extractStudyDocumentText(
        bytes: Uint8List(maxStudyDocumentBytes + 1),
        extension: 'txt',
      ),
      throwsA(isA<StudyDocumentTooLargeException>()),
    );
  });

  test('caps extracted text kept in memory', () async {
    final text = await extractStudyDocumentText(
      bytes: Uint8List.fromList(
        utf8.encode('a' * (maxStudyDocumentCharacters + 20)),
      ),
      extension: 'md',
    );

    expect(text.length, maxStudyDocumentCharacters);
  });
}
