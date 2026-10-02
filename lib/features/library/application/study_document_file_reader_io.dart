import 'dart:io';

import 'dart:typed_data';

Future<Uint8List?> readFileBytes(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) return file.readAsBytes();
  } catch (_) {
    // Android content providers may expose paths that are not readable as
    // regular files; the picker bytes remain the primary fallback.
  }
  return null;
}
