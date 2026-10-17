import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the Flutter SDK fonts on every platform instead of the Ahem test font.
Future<void> loadTestFonts({String fontFamily = 'VisualTestFont'}) async {
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  final Uri sdkRoot;
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    sdkRoot = Directory(configuredRoot).absolute.uri;
  } else {
    // Flutter's test engine does not implement Isolate.resolvePackageUri.
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        (jsonDecode(await config.readAsString())
                as Map<String, dynamic>)['packages']
            as List<dynamic>;
    final flutter = packages.cast<Map<String, dynamic>>().firstWhere(
      (package) => package['name'] == 'flutter',
    );
    final packageRoot = Directory.fromUri(
      config.uri.resolve(flutter['rootUri'] as String),
    ).uri;
    sdkRoot = packageRoot.resolve('../../');
  }
  final fontDirectory = sdkRoot.resolve('bin/cache/artifacts/material_fonts/');

  Future<ByteData> readFont(String fileName) async {
    final bytes = await File.fromUri(
      fontDirectory.resolve(fileName),
    ).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  final font = FontLoader(fontFamily)..addFont(readFont('Roboto-Regular.ttf'));
  await font.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(readFont('MaterialIcons-Regular.otf'));
  await icons.load();
}
