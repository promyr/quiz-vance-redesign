import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Loads the Flutter SDK fonts on every platform instead of the Ahem test font.
Future<void> loadTestFonts({String fontFamily = 'VisualTestFont'}) async {
  final flutterLibrary = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter/material.dart'),
  );
  if (flutterLibrary == null || flutterLibrary.scheme != 'file') {
    throw StateError(
      'Cannot locate the Flutter SDK to load required test fonts.',
    );
  }
  final fontDirectory = flutterLibrary.resolve(
    '../../../bin/cache/artifacts/material_fonts/',
  );

  Future<ByteData> readFont(String fileName) async {
    final bytes = await File.fromUri(
      fontDirectory.resolve(fileName),
    ).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  final font = FontLoader(fontFamily)..addFont(readFont('roboto-regular.ttf'));
  await font.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(readFont('materialicons-regular.otf'));
  await icons.load();
}
