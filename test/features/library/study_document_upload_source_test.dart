import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/library/application/study_document_upload_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('spools Android content stream to a replayable temporary PDF', () async {
    final temp =
        await Directory.systemTemp.createTemp('quiz-vance-upload-test-');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    final bytes = Uint8List.fromList('%PDF-1.7\nconteudo'.codeUnits);

    final source = await prepareStudyDocumentUpload(
      fileName: 'edital.PDF',
      declaredSize: bytes.length,
      readStream: Stream<List<int>>.fromIterable([
        bytes.sublist(0, 5),
        bytes.sublist(5),
      ]),
      tempDirectory: temp,
    );

    expect(source.fileName, 'edital.PDF');
    expect(source.length, bytes.length);
    expect(await source.openRead().expand((chunk) => chunk).toList(), bytes);
    expect(await source.openRead().expand((chunk) => chunk).toList(), bytes);
    final stagedPath = source.temporaryPath;
    expect(stagedPath, isNotNull);

    await source.dispose();
    expect(await File(stagedPath!).exists(), isFalse);
  });

  test('rejects non-PDF names before upload', () async {
    await expectLater(
      () => prepareStudyDocumentUpload(
        fileName: 'edital.txt',
        declaredSize: 8,
        bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
      ),
      throwsA(isA<StudyDocumentUploadException>()),
    );
  });

  test('rejects a PDF larger than the operational 100 MiB limit', () async {
    await expectLater(
      () => prepareStudyDocumentUpload(
        fileName: 'grande.pdf',
        declaredSize: maxStudyDocumentUploadBytes + 1,
        bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().toLowerCase().contains('100 mib'),
        ),
      ),
    );
  });
}
