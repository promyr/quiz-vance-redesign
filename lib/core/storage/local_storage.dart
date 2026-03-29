import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

const _databaseFileName = 'quiz_vance.db';
const _databaseKeyStorageKey = 'local_db_encryption_key_v1';
const _legacyBackupSuffix = '.plaintext.bak';

abstract class LocalStorageKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemoryLocalStorageKeyStore implements LocalStorageKeyStore {
  MemoryLocalStorageKeyStore([Map<String, String>? seed])
      : _values = <String, String>{...?seed};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _FlutterSecureKeyStore implements LocalStorageKeyStore {
  const _FlutterSecureKeyStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class LocalStorageTransaction {
  LocalStorageTransaction._(this._storage);

  final LocalStorage _storage;

  Future<int> delete(
    String table, {
    String? where,
    List<Object?> whereArgs = const [],
  }) {
    return _storage._delete(table, where: where, whereArgs: whereArgs);
  }

  Future<int> insert(
    String table,
    Map<String, dynamic> values, {
    bool replace = false,
  }) {
    return _storage._insert(table, values, replace: replace);
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    required String where,
    List<Object?> whereArgs = const [],
  }) {
    return _storage._update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
    );
  }
}

class LocalStorage {
  LocalStorage._();

  static final LocalStorage instance = LocalStorage._();

  static const int _version = 3;
  static const List<String> _trackedTables = <String>[
    'flashcards',
    'quiz_sessions',
    'user_cache',
    'library_files',
  ];

  Database? _db;
  String? _openedPath;
  String? _databasePathOverride;
  LocalStorageKeyStore _keyStore = const _FlutterSecureKeyStore();
  bool _allowPlaintextFallback = false;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('LocalStorage.init() must be called before use.');
    }
    return db;
  }

  Future<void> init() async {
    if (kIsWeb) {
      throw UnsupportedError('LocalStorage does not support web.');
    }

    await close();

    final databasePath = await _resolveDatabasePath();
    final encryptionKey = await _loadOrCreateEncryptionKey();
    final db = await _openOrMigrateDatabase(
      databasePath: databasePath,
      encryptionKey: encryptionKey,
    );

    _applyConnectionPragmas(db);
    _ensureSchema(db);

    _db = db;
    _openedPath = databasePath;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    _openedPath = null;
    db?.dispose();
  }

  Future<T> transaction<T>(
    Future<T> Function(LocalStorageTransaction txn) action,
  ) async {
    final db = _database;
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = await action(LocalStorageTransaction._(this));
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getDueFlashcards() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _select(
      'SELECT * FROM flashcards WHERE due_date <= ? ORDER BY due_date ASC, id ASC',
      [today],
    );
  }

  Future<int> upsertFlashcard(Map<String, dynamic> card) async {
    final payload = <String, dynamic>{
      'remote_id': _trimmedString(card['remote_id']),
      'front': card['front'] ?? '',
      'back': card['back'] ?? '',
      'topic': card['topic'] ?? '',
      'interval_days': _asInt(card['interval_days'], fallback: 1),
      'easiness': _asDouble(card['easiness'], fallback: 2.5),
      'due_date': card['due_date'],
      'repetitions': _asInt(card['repetitions'], fallback: 0),
      'last_reviewed': card['last_reviewed'],
      'synced': _normalizeBoolInt(card['synced']),
      'created_at': card['created_at'],
    };

    final remoteId = payload['remote_id'] as String?;
    if (remoteId == null || remoteId.isEmpty) {
      return _insert('flashcards', payload);
    }

    const sql = '''
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
      ON CONFLICT(remote_id) DO UPDATE SET
        front = excluded.front,
        back = excluded.back,
        topic = excluded.topic,
        interval_days = excluded.interval_days,
        easiness = excluded.easiness,
        due_date = excluded.due_date,
        repetitions = excluded.repetitions,
        last_reviewed = excluded.last_reviewed,
        synced = excluded.synced
    ''';

    _database.execute(sql, [
      payload['remote_id'],
      payload['front'],
      payload['back'],
      payload['topic'],
      payload['interval_days'],
      payload['easiness'],
      payload['due_date'],
      payload['repetitions'],
      payload['last_reviewed'],
      payload['synced'],
      payload['created_at'],
    ]);
    return _database.lastInsertRowId;
  }

  Future<int> updateFlashcard(int id, Map<String, dynamic> values) {
    final payload = <String, dynamic>{};
    for (final entry in values.entries) {
      switch (entry.key) {
        case 'interval_days':
        case 'repetitions':
          payload[entry.key] = _asInt(entry.value, fallback: 0);
          break;
        case 'easiness':
          payload[entry.key] = _asDouble(entry.value, fallback: 2.5);
          break;
        case 'synced':
          payload[entry.key] = _normalizeBoolInt(entry.value);
          break;
        default:
          payload[entry.key] = entry.value;
      }
    }
    return _update('flashcards', payload, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteFlashcardsByRemoteIdPrefix(String prefix) {
    return _delete(
      'flashcards',
      where: 'remote_id LIKE ?',
      whereArgs: ['$prefix%'],
    );
  }

  Future<List<Map<String, dynamic>>> listLibraryFiles() async {
    final rows = await _select(
      'SELECT id, remote_id, data_json FROM library_files ORDER BY id DESC',
    );

    return rows
        .map((row) {
          final rawJson = row['data_json'] as String? ?? '{}';
          final decoded = jsonDecode(rawJson);
          if (decoded is! Map) return null;

          final file = Map<String, dynamic>.from(decoded);
          file['id'] = _asInt(file['id'] ?? row['id']);
          final remoteId = _trimmedString(file['remote_id'] ?? row['remote_id']);
          if (remoteId != null) {
            file['remote_id'] = remoteId;
          }
          return file;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<int> upsertLibraryFile(Map<String, dynamic> file) {
    final payload = Map<String, dynamic>.from(file);
    final id = _asInt(payload['id']);
    payload['id'] = id;
    payload['remote_id'] = _trimmedString(payload['remote_id']);

    return _insert(
      'library_files',
      <String, dynamic>{
        'id': id,
        'remote_id': payload['remote_id'],
        'data_json': jsonEncode(payload),
      },
      replace: true,
    );
  }

  Future<int> deleteLibraryFile(int id) {
    return _delete('library_files', where: 'id = ?', whereArgs: [id]);
  }

  Future<String?> getCacheValue(String key) async {
    final rows = await _select(
      'SELECT value FROM user_cache WHERE key = ?',
      [key],
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  Future<void> setCacheValue(String key, String value) async {
    await _insert('user_cache', {'key': key, 'value': value}, replace: true);
  }

  Future<void> deleteCacheValue(String key) async {
    await _delete('user_cache', where: 'key = ?', whereArgs: [key]);
  }

  @visibleForTesting
  Future<void> configureForTesting({
    String? databasePath,
    LocalStorageKeyStore? keyStore,
    bool allowPlaintextFallback = true,
  }) async {
    await close();
    _databasePathOverride = databasePath;
    if (keyStore != null) {
      _keyStore = keyStore;
    } else if (allowPlaintextFallback) {
      _keyStore = MemoryLocalStorageKeyStore();
    }
    _allowPlaintextFallback = allowPlaintextFallback;
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    final pathsToDelete = <String>{
      if (_openedPath != null) _openedPath!,
      if (_databasePathOverride != null) _databasePathOverride!,
    };

    await close();

    for (final basePath in pathsToDelete) {
      await _deleteSidecarFiles(basePath);
    }

    _databasePathOverride = null;
    _keyStore = const _FlutterSecureKeyStore();
    _allowPlaintextFallback = false;
  }

  @visibleForTesting
  Future<void> debugExecute(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    _database.execute(sql, args);
  }

  @visibleForTesting
  Future<List<Map<String, dynamic>>> debugSelect(
    String sql, [
    List<Object?> args = const [],
  ]) {
    return _select(sql, args);
  }

  @visibleForTesting
  Future<bool> debugCipherAvailable() async {
    return _isCipherAvailable();
  }

  Future<List<Map<String, dynamic>>> _select(
    String sql, [
    List<Object?> args = const [],
  ]) {
    return Future.sync(() {
      final result = _database.select(sql, args);
      return result
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    });
  }

  Future<int> _insert(
    String table,
    Map<String, dynamic> values, {
    bool replace = false,
  }) {
    return Future.sync(() {
      return _insertIntoDatabase(
        _database,
        table,
        values,
        replace: replace,
      );
    });
  }

  Future<int> _update(
    String table,
    Map<String, dynamic> values, {
    required String where,
    List<Object?> whereArgs = const [],
  }) {
    return Future.sync(() {
      if (values.isEmpty) {
        return 0;
      }

      final keys = values.keys.toList(growable: false);
      final assignments = keys.map((key) => '$key = ?').join(', ');
      final sql = 'UPDATE $table SET $assignments WHERE $where';
      final args = <Object?>[
        for (final key in keys) values[key],
        ...whereArgs,
      ];
      _database.execute(sql, args);
      return _database.updatedRows;
    });
  }

  Future<int> _delete(
    String table, {
    String? where,
    List<Object?> whereArgs = const [],
  }) {
    return Future.sync(() {
      final whereSql = where != null ? ' WHERE $where' : '';
      _database.execute('DELETE FROM $table$whereSql', whereArgs);
      return _database.updatedRows;
    });
  }

  void _applyConnectionPragmas(Database db) {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA temp_store = MEMORY');
  }

  void _ensureSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS flashcards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_id TEXT UNIQUE,
        front TEXT NOT NULL DEFAULT '',
        back TEXT NOT NULL DEFAULT '',
        topic TEXT NOT NULL DEFAULT '',
        interval_days INTEGER NOT NULL DEFAULT 1,
        easiness REAL NOT NULL DEFAULT 2.5,
        due_date TEXT,
        repetitions INTEGER NOT NULL DEFAULT 0,
        last_reviewed TEXT,
        synced INTEGER NOT NULL DEFAULT 0,
        created_at TEXT
      )
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS ix_flashcards_due_date ON flashcards (due_date)
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS quiz_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remote_id TEXT UNIQUE,
        data_json TEXT NOT NULL DEFAULT '{}'
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS user_cache (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS library_files (
        id INTEGER PRIMARY KEY,
        remote_id TEXT UNIQUE,
        data_json TEXT NOT NULL DEFAULT '{}'
      )
    ''');

    db.execute('PRAGMA user_version = $_version');
  }

  Future<String> _resolveDatabasePath() async {
    if (_databasePathOverride != null) {
      return _databasePathOverride!;
    }

    if (Platform.isAndroid) {
      final dbPath = await getDatabasesPath();
      return path.join(dbPath, _databaseFileName);
    }

    final dir = await getApplicationDocumentsDirectory();
    return path.join(dir.path, _databaseFileName);
  }

  Future<String> _loadOrCreateEncryptionKey() async {
    final existingKey = await _keyStore.read(_databaseKeyStorageKey);
    if (existingKey != null && existingKey.isNotEmpty) {
      return existingKey;
    }

    final keyBytes = List<int>.generate(
      32,
      (_) => Random.secure().nextInt(256),
    );
    final keyHex = keyBytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await _keyStore.write(_databaseKeyStorageKey, keyHex);
    return keyHex;
  }

  Future<Database> _openOrMigrateDatabase({
    required String databasePath,
    required String encryptionKey,
  }) async {
    final cipherAvailable = _isCipherAvailable();
    final databaseFile = File(databasePath);

    if (!await databaseFile.exists()) {
      if (!cipherAvailable && !_allowPlaintextFallback) {
        throw StateError(
          'Encrypted local storage is unavailable in this runtime.',
        );
      }
      return _openDatabase(
        databasePath,
        encryptionKey: cipherAvailable ? encryptionKey : null,
      );
    }

    if (!cipherAvailable) {
      if (_allowPlaintextFallback) {
        return _openDatabase(databasePath);
      }
      throw StateError(
        'Encrypted local storage is unavailable in this runtime.',
      );
    }

    try {
      return _openDatabase(databasePath, encryptionKey: encryptionKey);
    } catch (_) {
      if (await _looksLikePlaintextSQLiteFile(databaseFile)) {
        return _migratePlaintextDatabase(
          databasePath: databasePath,
          encryptionKey: encryptionKey,
        );
      }
      rethrow;
    }
  }

  Database _openDatabase(String databasePath, {String? encryptionKey}) {
    final db = sqlite3.open(databasePath);
    try {
      if (encryptionKey != null && encryptionKey.isNotEmpty) {
        db.execute("PRAGMA key = '$encryptionKey'");
      }
      db.select('SELECT count(*) FROM sqlite_master');
      return db;
    } catch (_) {
      db.dispose();
      rethrow;
    }
  }

  Future<Database> _migratePlaintextDatabase({
    required String databasePath,
    required String encryptionKey,
  }) async {
    final sourcePath = '$databasePath$_legacyBackupSuffix';
    final sourceFile = File(databasePath);
    final backupFile = File(sourcePath);

    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    await sourceFile.rename(sourcePath);

    final sourceDb = sqlite3.open(sourcePath);
    final targetDb = _openDatabase(databasePath, encryptionKey: encryptionKey);

    try {
      _applyConnectionPragmas(targetDb);
      _ensureSchema(targetDb);
      _copyTrackedTables(sourceDb: sourceDb, targetDb: targetDb);
      return targetDb;
    } catch (_) {
      targetDb.dispose();
      rethrow;
    } finally {
      sourceDb.dispose();
    }
  }

  void _copyTrackedTables({
    required Database sourceDb,
    required Database targetDb,
  }) {
    for (final table in _trackedTables) {
      if (!_tableExists(sourceDb, table)) {
        continue;
      }

      final rows = sourceDb.select('SELECT * FROM $table');
      if (rows.isEmpty) {
        continue;
      }

      final targetColumns = _tableColumns(targetDb, table);
      for (final row in rows) {
        final values = <String, dynamic>{};
        for (final entry in row.entries) {
          if (targetColumns.contains(entry.key)) {
            values[entry.key] = entry.value;
          }
        }
        if (values.isNotEmpty) {
          _insertIntoDatabase(targetDb, table, values, replace: true);
        }
      }
    }
  }

  int _insertIntoDatabase(
    Database db,
    String table,
    Map<String, dynamic> values, {
    bool replace = false,
  }) {
    final keys = values.keys.toList(growable: false);
    final placeholders = List<String>.filled(keys.length, '?').join(', ');
    final orReplace = replace ? 'OR REPLACE ' : '';
    final sql =
        'INSERT $orReplace INTO $table (${keys.join(', ')}) VALUES ($placeholders)';
    db.execute(sql, [for (final key in keys) values[key]]);
    return db.lastInsertRowId;
  }

  bool _tableExists(Database db, String table) {
    final rows = db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  Set<String> _tableColumns(Database db, String table) {
    final rows = db.select("PRAGMA table_info('$table')");
    return rows
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
  }

  bool _isCipherAvailable() {
    final db = sqlite3.openInMemory();
    try {
      final rows = db.select('PRAGMA cipher_version');
      if (rows.isEmpty) {
        return false;
      }
      final value = rows.first.values.first;
      return value is String && value.trim().isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      db.dispose();
    }
  }

  Future<bool> _looksLikePlaintextSQLiteFile(File file) async {
    if (!await file.exists()) {
      return false;
    }
    final header = await file.openRead(0, 16).fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (header.length < 16) {
      return false;
    }
    return ascii.decode(header) == 'SQLite format 3\x00';
  }

  Future<void> _deleteSidecarFiles(String basePath) async {
    final candidates = <String>[
      basePath,
      '$basePath-wal',
      '$basePath-shm',
      '$basePath$_legacyBackupSuffix',
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  static int _normalizeBoolInt(dynamic value) {
    if (value is bool) {
      return value ? 1 : 0;
    }
    return _asInt(value, fallback: 0);
  }

  static String? _trimmedString(dynamic value) {
    if (value == null) {
      return null;
    }
    final stringValue = value.toString().trim();
    if (stringValue.isEmpty) {
      return null;
    }
    return stringValue;
  }
}
