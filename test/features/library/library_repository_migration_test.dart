import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:quiz_vance_flutter/features/library/data/library_repository.dart';
import 'package:quiz_vance_flutter/features/library/application/library_document_recovery.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_document.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient implements ApiClient {
  @override
  Dio get dio => Dio();

  @override
  Future<void> clearTokens() async {}

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    bool? persist,
  }) async {}
}

class _MockDocumentRepository extends Mock implements StudyPlanRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('quiz_vance_library_test_');
    await LocalStorage.instance.configureForTesting(
      databasePath: path.join(tempDir.path, 'quiz_vance.db'),
    );
    SharedPreferences.setMockInitialValues({});
    AccountScopedPreferences.instance.setActiveAccountId(null);
    await LocalStorage.instance.init();
    await LocalStorage.instance.debugExecute('DELETE FROM library_files');
    await LocalStorage.instance.debugExecute('DELETE FROM flashcards');
    await LocalStorage.instance.debugExecute('DELETE FROM quiz_sessions');
    await LocalStorage.instance.debugExecute('DELETE FROM user_cache');
  });

  tearDown(() async {
    await LocalStorage.instance.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
      'migra dados legados de SharedPreferences para SQLite de forma idempotente',
      () async {
    SharedPreferences.setMockInitialValues({
      'library_files': jsonEncode([
        {
          'id': 101,
          'nome': 'Material legado',
          'categoria': 'Historia',
          'conteudo': 'Conteudo importado',
          'criado_em': DateTime(2026, 3, 20).toIso8601String(),
        },
      ]),
    });

    final repository = LibraryRepository(_FakeApiClient());

    final firstRead = await repository.listFiles();
    final secondRead = await repository.listFiles();
    final prefs = await SharedPreferences.getInstance();

    expect(firstRead, hasLength(1));
    expect(secondRead, hasLength(1));
    expect(firstRead.first.id, equals(101));
    expect(prefs.getBool('library_files_migrated_v2'), isTrue);
    expect(prefs.getString('library_files'), isNull);
  });

  test('migracao legado nao sobrescreve biblioteca atual', () async {
    final repository = LibraryRepository(_FakeApiClient());

    final current = await repository.addFile(
      nome: 'Material atual',
      categoria: 'Direito',
      conteudo: 'Conteudo novo',
    );

    SharedPreferences.setMockInitialValues({
      'library_files': jsonEncode([
        {
          'id': 501,
          'nome': 'Material legado',
          'categoria': 'Historia',
          'conteudo': 'Conteudo antigo',
          'criado_em': DateTime(2026, 3, 1).toIso8601String(),
        },
      ]),
    });

    final migratedRepository = LibraryRepository(_FakeApiClient());
    final files = await migratedRepository.listFiles();

    expect(files.map((item) => item.id), contains(current.id));
    expect(files.map((item) => item.id), contains(501));
    expect(files, hasLength(2));
  });

  test('add e delete operam no banco local apos a migracao', () async {
    final repository = LibraryRepository(_FakeApiClient());

    final created = await repository.addFile(
      nome: 'Novo material',
      categoria: 'Biologia',
      conteudo: 'Resumo de celulas',
    );
    final listAfterInsert = await repository.listFiles();
    await repository.deleteFile(created.id);
    final listAfterDelete = await repository.listFiles();

    expect(listAfterInsert.map((item) => item.id), contains(created.id));
    expect(listAfterDelete.map((item) => item.id), isNot(contains(created.id)));
  });

  test('retomada importa documento remoto pronto de forma idempotente',
      () async {
    final repository = LibraryRepository(_FakeApiClient());
    final document = StudyDocument(
      id: 42,
      purpose: StudyDocumentPurpose.library,
      fileName: 'apostila.pdf',
      sizeBytes: 4096,
      status: StudyDocumentStatus.ready,
      progress: 100,
      cargos: const [],
    );

    await repository.importProcessedDocument(
      document: document,
      content: 'Conteudo extraido em segundo plano',
    );
    await repository.importProcessedDocument(
      document: document,
      content: 'Conteudo extraido em segundo plano',
    );

    final files = await repository.listFiles();
    expect(files, hasLength(1));
    expect(files.single.id, -42);
    expect(files.single.nome, 'apostila');
    expect(files.single.conteudo, contains('segundo plano'));
  });

  test('deleted recovered PDF stays deleted after repository recreation',
      () async {
    AccountScopedPreferences.instance.setActiveAccountId('owner');
    LocalStorage.instance.setActiveAccountId('owner');
    const document = StudyDocument(
      id: 42,
      purpose: StudyDocumentPurpose.library,
      fileName: 'apostila.pdf',
      sizeBytes: 4096,
      status: StudyDocumentStatus.ready,
      progress: 100,
      cargos: [],
    );
    final repository = LibraryRepository(_FakeApiClient());
    await repository.importProcessedDocument(
      document: document,
      content: 'Conteúdo extraído',
    );
    await repository.deleteFile(-42);
    AccountScopedPreferences.instance.setActiveAccountId(null);
    LocalStorage.instance.setActiveAccountId(null);
    AccountScopedPreferences.instance.setActiveAccountId('owner');
    LocalStorage.instance.setActiveAccountId('owner');
    final reopened = LibraryRepository(_FakeApiClient());
    await reopened.importProcessedDocument(
      document: document,
      content: 'Conteúdo extraído',
    );
    expect(await reopened.listFiles(), isEmpty);

    await reopened.importProcessedDocument(
      document: const StudyDocument(
        id: 43,
        purpose: StudyDocumentPurpose.library,
        fileName: 'apostila.pdf',
        sizeBytes: 4096,
        status: StudyDocumentStatus.ready,
        progress: 100,
        cargos: [],
      ),
      content: 'Novo envio explícito',
    );
    expect((await reopened.listFiles()).single.id, -43);

    AccountScopedPreferences.instance.setActiveAccountId('other-user');
    LocalStorage.instance.setActiveAccountId('other-user');
    await reopened.importProcessedDocument(
      document: document,
      content: 'Conteúdo da outra conta',
    );
    expect((await reopened.listFiles()).single.conteudo,
        'Conteúdo da outra conta');
  });

  test('deletion during recovery download prevents the pending upsert',
      () async {
    const document = StudyDocument(
      id: 44,
      purpose: StudyDocumentPurpose.library,
      fileName: 'em-download.pdf',
      sizeBytes: 4096,
      status: StudyDocumentStatus.ready,
      progress: 100,
      cargos: [],
    );
    final library = LibraryRepository(_FakeApiClient());
    await library.importProcessedDocument(
      document: document,
      content: 'Texto salvo',
    );
    final documents = _MockDocumentRepository();
    final downloading = Completer<void>();
    final downloaded = Completer<String>();
    when(() => documents.listDocuments(
          purpose: StudyDocumentPurpose.library,
        )).thenAnswer((_) async => [document]);
    when(() => documents.getDocumentContent(44)).thenAnswer((_) {
      downloading.complete();
      return downloaded.future;
    });
    final pendingRecovery = LibraryDocumentRecovery(
      libraryRepository: library,
      documentRepository: documents,
    ).resume();
    await downloading.future;
    await library.deleteFile(-44);
    downloaded.complete('Texto baixado após exclusão');
    await pendingRecovery;

    expect(await library.listFiles(), isEmpty);
  });
}
