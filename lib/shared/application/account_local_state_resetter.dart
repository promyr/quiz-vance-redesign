import '../../core/storage/local_storage.dart';
import 'account_scoped_preferences.dart';
import 'user_stats_cache_service.dart';

const List<String> _accountScopedPreferenceKeys = <String>[
  'study_plan_active',
  'flashcards_today_count',
  'flashcards_today_date',
  'gamif_xp',
  'gamif_level',
  'gamif_streak',
  'gamif_longest_streak',
  'gamif_total_quizzes',
  'gamif_achievements',
  'gamif_processed_quiz_events',
  'gamif_last_streak_date',
  'ai_provider',
  'ai_config_sync_pending',
  'ai_config_synced_provider',
];

class AccountLocalStateResetter {
  AccountLocalStateResetter({
    LocalStorage? storage,
    AccountScopedPreferences? preferences,
  })  : _storage = storage ?? LocalStorage.instance,
        _preferences = preferences ?? AccountScopedPreferences.instance;

  final LocalStorage _storage;
  final AccountScopedPreferences _preferences;

  Future<void> clearAccountState() async {
    await _storage.clearAccountScopedData();
    await _storage.deleteCacheValue(userStatsCacheKey);
    await _preferences.removeMany(
      _accountScopedPreferenceKeys,
      removeLegacyFallback: true,
    );
  }
}
