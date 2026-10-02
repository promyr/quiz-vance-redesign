import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'study_document_pdf_format.dart';

const int maxStudyDocumentUploadBytes = 100 * 1024 * 1024;

class StudyDocumentUploadException implements Exception {
  const StudyDocumentUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StudyDocumentUploadSource {
  StudyDocumentUploadSource._({
    required this.fileName,
    required this.length,
    required Stream<List<int>> Function() openRead,
    this.temporaryPath,
  }) : _openRead = openRead;

  final String fileName;
  final int length;
  final String? temporaryPath;
  final Stream<List<int>> Function() _openRead;
  bool _disposed = false;

  Stream<List<int>> openRead() {
    if (_disposed) {
      throw const StudyDocumentUploadException(
        'O arquivo temporario ja foi liberado.',
      );
    }
    return _openRead();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final path = temporaryPath;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // A limpeza temporaria nao deve esconder o resultado do upload.
    }
  }
}

void _validateMetadata(String fileName, int declaredSize) {
  if (!fileName.trim().toLowerCase().endsWith('.pdf')) {
    throw const StudyDocumentUploadException('Selecione somente um PDF.');
  }
  if (declaredSize > maxStudyDocumentUploadBytes) {
    throw const StudyDocumentUploadException(
      'O PDF excede o limite operacional de 100 MiB.',
    );
  }
}

Future<StudyDocumentUploadSource> prepareStudyDocumentUpload({
  required String fileName,
  required int declaredSize,
  String? path,
  Uint8List? bytes,
  Stream<List<int>>? readStream,
  Directory? tempDirectory,
}) async {
  _validateMetadata(fileName, declaredSize);

  final regularPath = path?.trim();
  if (regularPath != null && regularPath.isNotEmpty) {
    try {
      final file = File(regularPath);
      if (await file.exists()) {
        final length = await file.length();
        _validateMetadata(fileName, length);
        final header =
            await file.openRead(0, length.clamp(0, 1024)).fold<List<int>>(
          <int>[],
          (buffer, chunk) => buffer..addAll(chunk),
        );
        if (!hasPdfSignature(header)) {
          throw const StudyDocumentUploadException(
            'O arquivo selecionado nao e um PDF valido.',
          );
        }
        return StudyDocumentUploadSource._(
          fileName: fileName,
          length: length,
          openRead: file.openRead,
        );
      }
    } on StudyDocumentUploadException {
      rethrow;
    } catch (_) {
      // content:// e caminhos virtuais seguem para readStream/bytes.
    }
  }

  if (readStream != null) {
    final directory = tempDirectory ?? await getTemporaryDirectory();
    final safeStem = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final staged = File(
      '${directory.path}${Platform.pathSeparator}'
      'quiz-vance-${DateTime.now().microsecondsSinceEpoch}-$safeStem.pdf',
    );
    final sink = staged.openWrite();
    final header = <int>[];
    var length = 0;
    try {
      await for (final chunk in readStream) {
        length += chunk.length;
        if (length > maxStudyDocumentUploadBytes) {
          throw const StudyDocumentUploadException(
            'O PDF excede o limite operacional de 100 MiB.',
          );
        }
        if (header.length < 1024) {
          final missing = 1024 - header.length;
          header.addAll(chunk.take(missing));
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await staged.exists()) await staged.delete();
      rethrow;
    }
    if (length <= 0 || !hasPdfSignature(header)) {
      if (await staged.exists()) await staged.delete();
      throw const StudyDocumentUploadException(
        'O arquivo selecionado nao e um PDF valido.',
      );
    }
    return StudyDocumentUploadSource._(
      fileName: fileName,
      length: length,
      openRead: staged.openRead,
      temporaryPath: staged.path,
    );
  }

  if (bytes != null && bytes.isNotEmpty) {
    _validateMetadata(fileName, bytes.length);
    if (!hasPdfSignature(bytes)) {
      throw const StudyDocumentUploadException(
        'O arquivo selecionado nao e um PDF valido.',
      );
    }
    return StudyDocumentUploadSource._(
      fileName: fileName,
      length: bytes.length,
      openRead: () => Stream<List<int>>.value(bytes),
    );
  }

  throw const StudyDocumentUploadException(
    'Nao foi possivel ler o PDF selecionado.',
  );
}
