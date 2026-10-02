import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

class _UnavailableKeyStore implements LocalStorageKeyStore {
  var writes = 0;
  var deletes = 0;

  @override
  Future<String?> read(String key) => throw StateError('keystore unavailable');

  @override
  Future<void> write(String key, String value) async {
    writes++;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String databasePath;
  late MemoryLocalStorageKeyStore keyStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('quiz_vance_storage_test_');
    databasePath = path.join(tempDir.path, 'quiz_vance.db');
    keyStore = MemoryLocalStorageKeyStore();
    await LocalStorage.instance.configureForTesting(
      databasePath: databasePath,
      keyStore: keyStore,
    );
  });

  tearDown(() async {
    await LocalStorage.instance.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('singleton retorna sempre a mesma instancia', () {
    expect(LocalStorage.instance, same(LocalStorage.instance));
  });

  test('keystore indisponivel falha fechado sem substituir a chave', () async {
    final unavailable = _UnavailableKeyStore();
    await LocalStorage.instance.configureForTesting(
      databasePath: databasePath,
      keyStore: unavailable,
    );

    await expectLater(LocalStorage.instance.init(), throwsStateError);
    expect(unavailable.writes, 0);
    expect(unavailable.deletes, 0);
  });

  test('init cria schema cifrado e indice em due_date', () async {
    await LocalStorage.instance.init();

    final versionRows = await LocalStorage.instance.debugSelect(
      'PRAGMA user_version',
    );
    final indexRows = await LocalStorage.instance.debugSelect(
      "PRAGMA index_list('flashcards')",
    );

    expect(versionRows.first.values.first, equals(4));
    expect(
      indexRows.any((row) => row['name'] == 'ix_flashcards_account_due_date'),
      isTrue,
    );
  });

  test('migra banco legado preservando os dados existentes', () async {
    final cipherAvailable = await LocalStorage.instance.debugCipherAvailable();
    final legacyDb = sqlite3.open(databasePath);
    legacyDb.execute('''
      CREATE TABLE flashcards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_id TEXT UNIQUE,
        front TEXT NOT NULL,
        back TEXT NOT NULL,
        topic TEXT,
        interval_days INTEGER DEFAULT 1,
        easiness REAL DEFAULT 2.5,
        due_date TEXT NOT NULL,
        repetitions INTEGER DEFAULT 0,
        last_reviewed TEXT,
        synced INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    legacyDb.execute('''
      INSERT INTO flashcards (
        remote_id,
        front,
        back,
        topic,
        interval_days,
        easiness,
        due_date,
        repetitions,
        last_reviewed,
        synced,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      'legacy-1',
      'Frente',
      'Verso',
      'Historia',
      1,
      2.5,
      '2026-03-28',
      0,
      null,
      0,
      DateTime(2026, 3, 28).toIso8601String(),
    ]);
    legacyDb.dispose();

    await LocalStorage.instance.init();

    final due = await LocalStorage.instance.getDueFlashcards();
    final backupFile = File('$databasePath.plaintext.bak');

    expect(due, hasLength(1));
    expect(due.first['remote_id'], equals('legacy-1'));

    if (cipherAvailable) {
      expect(await backupFile.exists(), isTrue);

      final reopenedWithoutKey = sqlite3.open(databasePath);
      try {
        expect(
          () => reopenedWithoutKey.select('SELECT COUNT(*) FROM flashcards'),
          throwsA(isA<Object>()),
        );
      } finally {
        reopenedWithoutKey.dispose();
      }
    } else {
      expect(await backupFile.exists(), isFalse);
    }
  });

  test('isola dados locais por conta ativa', () async {
    await LocalStorage.instance.init();

    LocalStorage.instance.setActiveAccountId('user-a');
    await LocalStorage.instance.upsertFlashcard({
      'remote_id': 'fc-a',
      'front': 'Frente A',
      'back': 'Verso A',
      'topic': 'Historia',
      'due_date': '2026-03-31',
      'created_at': DateTime(2026, 3, 31).toIso8601String(),
    });
    await LocalStorage.instance.upsertLibraryFile({
      'id': 101,
      'remote_id': 'lib-a',
      'name': 'Arquivo A',
    });

    LocalStorage.instance.setActiveAccountId('user-b');
    await LocalStorage.instance.upsertFlashcard({
      'remote_id': 'fc-b',
      'front': 'Frente B',
      'back': 'Verso B',
      'topic': 'Direito',
      'due_date': '2026-03-31',
      'created_at': DateTime(2026, 3, 31).toIso8601String(),
    });
    await LocalStorage.instance.upsertLibraryFile({
      'id': 202,
      'remote_id': 'lib-b',
      'name': 'Arquivo B',
    });

    LocalStorage.instance.setActiveAccountId('user-a');
    final flashcardsA = await LocalStorage.instance.getDueFlashcards();
    final libraryA = await LocalStorage.instance.listLibraryFiles();

    LocalStorage.instance.setActiveAccountId('user-b');
    final flashcardsB = await LocalStorage.instance.getDueFlashcards();
    final libraryB = await LocalStorage.instance.listLibraryFiles();

    expect(flashcardsA.map((row) => row['remote_id']), contains('fc-a'));
    expect(flashcardsA.map((row) => row['remote_id']), isNot(contains('fc-b')));
    expect(libraryA.map((row) => row['remote_id']), contains('lib-a'));
    expect(libraryA.map((row) => row['remote_id']), isNot(contains('lib-b')));

    expect(flashcardsB.map((row) => row['remote_id']), contains('fc-b'));
    expect(flashcardsB.map((row) => row['remote_id']), isNot(contains('fc-a')));
    expect(libraryB.map((row) => row['remote_id']), contains('lib-b'));
    expect(libraryB.map((row) => row['remote_id']), isNot(contains('lib-a')));
  });
}
