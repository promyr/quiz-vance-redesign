import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:sqlite3/sqlite3.dart';

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

  test('init cria schema cifrado e indice em due_date', () async {
    await LocalStorage.instance.init();

    final versionRows = await LocalStorage.instance.debugSelect(
      'PRAGMA user_version',
    );
    final indexRows = await LocalStorage.instance.debugSelect(
      "PRAGMA index_list('flashcards')",
    );

    expect(versionRows.first.values.first, equals(3));
    expect(
      indexRows.any((row) => row['name'] == 'ix_flashcards_due_date'),
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
}
