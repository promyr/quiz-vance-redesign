import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/library/application/study_document_picker.dart';

void main() {
  test('retorna null quando o usuario cancela a selecao', () async {
    final selected = await pickStudyDocumentPdf(
      picker: () async => null,
    );

    expect(selected, isNull);
  });

  test('prepara uma unica fonte PDF reutilizavel pelo fluxo chamador',
      () async {
    final bytes = Uint8List.fromList(<int>[
      0x25,
      0x50,
      0x44,
      0x46,
      0x2D,
      ...'documento'.codeUnits,
    ]);

    final selected = await pickStudyDocumentPdf(
      picker: () async => FilePickerResult(<PlatformFile>[
        PlatformFile(
          name: 'edital.pdf',
          size: bytes.length,
          bytes: bytes,
        ),
      ]),
    );

    expect(selected, isNotNull);
    expect(selected!.displayName, 'edital.pdf');
    expect(selected.source.fileName, 'edital.pdf');
    expect(selected.source.length, bytes.length);
    expect(
      await selected.source.openRead().expand((chunk) => chunk).toList(),
      bytes,
    );

    await selected.dispose();
    expect(selected.source.openRead, throwsA(isA<Exception>()));
  });
}
