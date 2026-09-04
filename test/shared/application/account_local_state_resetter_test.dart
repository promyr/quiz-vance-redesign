import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:quiz_vance_flutter/shared/application/account_local_state_resetter.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String databasePath;
  late MemoryLocalStorageKeyStore keyStore;
  late LocalStorage storage;
  late AccountLocalStateResetter resetter;
  late AccountScopedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'study_plan_active': '{"objetivo":"Concurso"}',
      'flashcards_today_count': 4,
      'flashcards_today_date': '2026-03-31',
      'gamif_xp': 150,
      'gamif_level': 2,
      'gamif_streak': 3,
      'gamif_longest_streak': 5,
      'gamif_total_quizzes': 10,
      'gamif_achievements': <String>['Primeiro quiz'],
      'gamif_processed_quiz_events': <String>['quiz-1'],
      'gamif_last_streak_date': '2026-03-31',
      'ai_provider': 'groq',
      'ai_config_sync_pending': true,
      'ai_config_synced_provider': 'groq',
    });

    tempDir = await Directory.systemTemp.createTemp('quiz_vance_account_reset_');
    databasePath = path.join(tempDir.path, 'quiz_vance.db');
    keyStore = MemoryLocalStorageKeyStore();

    storage = LocalStorage.instance;
    await storage.configureForTesting(
      databasePath: databasePath,
      keyStore: keyStore,
    );
    await storage.init();
    preferences = AccountScopedPreferences.instance;
    preferences.setActiveAccountId(null);

    resetter = AccountLocalStateResetter(storage: storage);
  });

  tearDown(() async {
    await storage.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('clearAccountState remove apenas o estado da conta ativa', () async {
    storage.setActiveAccountId('user-1');
    preferences.setActiveAccountId('user-1');

    await storage.upsertFlashcard({
      'remote_id': 'fc-1',
      'front': 'Frente',
      'back': 'Verso',
      'topic': 'Direito',
      'due_date': '2026-03-31',
      'created_at': DateTime(2026, 3, 31).toIso8601String(),
    });
    await storage.upsertLibraryFile({
      'id': 1,
      'remote_id': 'lib-1',
      'name': 'Arquivo',
    });
    await storage.setCacheValue('user_stats_cache', '{"xp":150}');
    await storage.debugExecute(
      "INSERT INTO quiz_sessions (remote_id, account_id, data_json) VALUES (?, ?, ?)",
      ['sess-1', 'user-1', '{"score":10}'],
    );
    await preferences.setString('study_plan_active', '{"objetivo":"Concurso A"}');
    await preferences.setInt('gamif_xp', 150);
    await preferences.setString('ai_provider', 'groq');

    storage.setActiveAccountId('user-2');
    preferences.setActiveAccountId('user-2');
    await storage.upsertFlashcard({
      'remote_id': 'fc-2',
      'front': 'Outra frente',
      'back': 'Outro verso',
      'topic': 'Matematica',
      'due_date': '2026-03-31',
      'created_at': DateTime(2026, 3, 31).toIso8601String(),
    });
    await storage.upsertLibraryFile({
      'id': 2,
      'remote_id': 'lib-2',
      'name': 'Arquivo 2',
    });
    await storage.setCacheValue('user_stats_cache', '{"xp":999}');
    await storage.debugExecute(
      "INSERT INTO quiz_sessions (remote_id, account_id, data_json) VALUES (?, ?, ?)",
      ['sess-2', 'user-2', '{"score":20}'],
    );
    await preferences.setString('study_plan_active', '{"objetivo":"Concurso B"}');
    await preferences.setInt('gamif_xp', 999);
    await preferences.setString('ai_provider', 'openai');

    storage.setActiveAccountId('user-1');
    preferences.setActiveAccountId('user-1');

    await resetter.clearAccountState();

    expect(await storage.getDueFlashcards(), isEmpty);
    expect(await storage.listLibraryFiles(), isEmpty);
    expect(await storage.getCacheValue('user_stats_cache'), isNull);
    expect(
      await storage.debugSelect(
        "SELECT * FROM quiz_sessions WHERE account_id = 'user-1'",
      ),
      isEmpty,
    );
    expect(await preferences.getString('study_plan_active'), isNull);
    expect(await preferences.getInt('gamif_xp'), isNull);
    expect(await preferences.getString('ai_provider'), isNull);

    storage.setActiveAccountId('user-2');
    preferences.setActiveAccountId('user-2');
    expect(await storage.getDueFlashcards(), hasLength(1));
    expect(await storage.listLibraryFiles(), hasLength(1));
    expect(await storage.getCacheValue('user_stats_cache'), '{"xp":999}');
    expect(
      await storage.debugSelect(
        "SELECT * FROM quiz_sessions WHERE account_id = 'user-2'",
      ),
      hasLength(1),
    );
    expect(
      await preferences.getString('study_plan_active'),
      '{"objetivo":"Concurso B"}',
    );
    expect(await preferences.getInt('gamif_xp'), 999);
    expect(await preferences.getString('ai_provider'), 'openai');
  });
}
