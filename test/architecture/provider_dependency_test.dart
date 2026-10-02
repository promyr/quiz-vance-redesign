import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth provider nao depende de providers de dados da conta', () {
    final source =
        File('lib/shared/providers/auth_provider.dart').readAsStringSync();

    expect(source, isNot(contains("import 'user_provider.dart';")));
    expect(source, isNot(contains("import 'gamification_provider.dart';")));
  });

  test('assinatura PDF possui uma unica implementacao compartilhada', () {
    const signatureLiteral = '0x25, 0x50, 0x44, 0x46, 0x2D';
    final sources = Directory('lib/features/library/application')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final occurrences = sources
        .map((file) => file.readAsStringSync())
        .where((source) => source.contains(signatureLiteral))
        .length;

    expect(occurrences, 1);
  });

  test('telas nao acessam diretamente o seletor de arquivos PDF', () {
    final presentationSources = <String>[
      'lib/features/library/presentation/library_screen.dart',
      'lib/features/study_plan/presentation/study_plan_screen.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(
        presentationSources, isNot(contains('FilePicker.platform.pickFiles')));
  });
}
