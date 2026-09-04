import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fontes Dart nao contem texto com codificacao corrompida', () {
    final suspiciousText = RegExp(
      r'Ã(?:[\u0080-\u00BF]| )|Â[\u0080-\u00BF]|â(?:€|†|œ|”)|ðŸ|ï¸|�',
    );
    final corruptedFiles = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (suspiciousText.hasMatch(entity.readAsStringSync())) {
        corruptedFiles.add(entity.path);
      }
    }

    expect(
      corruptedFiles,
      isEmpty,
      reason: 'Arquivos com possivel mojibake: ${corruptedFiles.join(', ')}',
    );
  });
}
