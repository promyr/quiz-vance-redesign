import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/library/domain/material_chapters.dart';
import 'package:quiz_vance_flutter/features/library/data/material_scope_store.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';

void main() {
  const text =
      'Prefácio\nCapítulo 1 - Direito\nCONTEUDO_DIREITO\nCapítulo 2 - Matemática\nCONTEUDO_MATEMATICA\nCapítulo 3 - Física\nCONTEUDO_FISICA';
  final file = LibraryFile(
      id: 7, nome: 'Livro', conteudo: text, criadoEm: DateTime(2026));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AccountScopedPreferences.instance.setActiveAccountId('alice');
  });
  test('detecta capítulos e recorta apenas o capítulo escolhido', () {
    final chapters = detectMaterialChapters(text);
    expect(chapters.length, 4);
    final selected = extractSelectedChapters(text, [chapters[2]]);
    expect(selected, contains('CONTEUDO_MATEMATICA'));
    expect(selected, isNot(contains('CONTEUDO_DIREITO')));
    expect(selected, isNot(contains('CONTEUDO_FISICA')));
  });
  test('recorte vazio é rejeitado', () {
    expect(() => extractSelectedChapters(text, []), throwsArgumentError);
  });
  test('seleção salva é reutilizada e isolada da outra conta', () async {
    final store = MaterialScopeStore();
    final chapters = detectMaterialChapters(text);
    await store.save(file, [chapters[2]]);
    expect((await store.resolve(file)).file.conteudo,
        contains('CONTEUDO_MATEMATICA'));
    expect((await store.resolve(file)).file.conteudo,
        isNot(contains('CONTEUDO_DIREITO')));
    AccountScopedPreferences.instance.setActiveAccountId('bob');
    expect((await store.resolve(file)).restricted, false);
    expect((await store.resolve(file)).file.conteudo, text);
  });
  test('texto alterado não reaproveita offsets antigos silenciosamente',
      () async {
    final store = MaterialScopeStore();
    await store.save(file, [detectMaterialChapters(text)[2]]);
    final changed = LibraryFile(
        id: 7,
        nome: 'Livro',
        conteudo: 'texto alterado',
        criadoEm: DateTime(2026));
    await expectLater(store.resolve(changed), throwsStateError);
  });
  test('restaurar documento inteiro preserva original', () async {
    final store = MaterialScopeStore();
    await store.save(file, [detectMaterialChapters(text)[2]]);
    await store.clear(file);
    expect((await store.resolve(file)).file.conteudo, text);
  });
  test('contexto limitado representa capítulos distantes selecionados',
      () async {
    final a = List.filled(
            150, 'A álgebra permite calcular produtos e resolver equações.')
        .join(' ');
    final b = List.filled(
            150, 'A geometria descreve medidas, áreas e formas espaciais.')
        .join(' ');
    final raw = 'Capítulo 1 - Álgebra\n$a\nCapítulo 2 - Geometria\n$b';
    final material = LibraryFile(
        id: 88, nome: 'Matemática', conteudo: raw, criadoEm: DateTime(2026));
    final store = MaterialScopeStore();
    await store.save(material, detectMaterialChapters(raw));
    final scope = await store.resolve(material);
    final context = scope.promptContext(2200);
    expect(context.length, lessThanOrEqualTo(2200));
    expect(context, contains('álgebra'));
    expect(context, contains('geometria'));
  });
}
