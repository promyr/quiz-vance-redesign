import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/features/library/presentation/material_chapter_picker.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/library/data/material_scope_store.dart';

void main() {
  final file = LibraryFile(
      id: 123,
      nome: 'Livro',
      conteudo:
          'Capítulo 1 - Direito\nOs contratos estabelecem obrigações entre as partes.\nCapítulo 2 - Matemática\nA soma reúne parcelas e a multiplicação calcula produtos.',
      criadoEm: DateTime(2026));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (ctx) => TextButton(
                    onPressed: () => showMaterialChapterPicker(ctx, file),
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('escolha de capítulo permanece salva sem alterar original',
      (tester) async {
    await open(tester);
    await tester
        .tap(find.widgetWithText(CheckboxListTile, 'Capítulo 1 - Direito'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar seleção'));
    await tester.pumpAndSettle();
    final scoped = await MaterialScopeStore().resolve(file);
    expect(scoped.file.conteudo, isNot(contains('contratos')));
    expect(scoped.file.conteudo, contains('multiplicação'));
    expect(file.conteudo, contains('contratos'));
  });
  testWidgets('seleção cabe em tela estreita com fonte ampliada', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Aplicar seleção'), findsOneWidget);
  });
  testWidgets('seleção vazia não fecha modal nem grava recorte',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Desmarcar todos'));
    await tester.pump();
    await tester.tap(find.text('Aplicar seleção'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Selecione pelo menos um capítulo ou trecho.'),
        findsOneWidget);
    expect(await MaterialScopeStore().load(file), isNull);
  });
  testWidgets('intervalo manual permite escolher conteúdo sem capítulos',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Definir trecho por linhas'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Linha inicial'), '3');
    await tester.enterText(
        find.widgetWithText(TextField, 'Linha final (incluída)'), '4');
    await tester.tap(find.text('Aplicar seleção'));
    await tester.pumpAndSettle();
    expect((await MaterialScopeStore().resolve(file)).file.conteudo,
        isNot(contains('contratos')));
  });
}
