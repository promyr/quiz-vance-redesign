import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_storage.dart';
import 'account_scoped_preferences.dart';

const userStatsCacheKey = 'user_stats_cache';
const flashcardsTodayKey = 'flashcards_today_count';
const flashcardsTodayDateKey = 'flashcards_today_date';

class UserStatsCacheService {
  UserStatsCacheService({
    LocalStorage? storage,
    AccountScopedPreferences? preferences,
  })  : _storage = storage ?? LocalStorage.instance,
        _preferences = preferences ?? AccountScopedPreferences.instance;

  final LocalStorage _storage;
  final AccountScopedPreferences _preferences;

  Future<void> saveRemoteStatsPayload(Map<String, dynamic> payload) {
    return _storage.setCacheValue(userStatsCacheKey, jsonEncode(payload),
        scoped: true);
  }

  Future<Map<String, dynamic>?> readRemoteStatsPayload() async {
    final cached =
        await _storage.getCacheValue(userStatsCacheKey, scoped: true);
    if (cached == null || cached == '{}') {
      return null;
    }

    final decoded = jsonDecode(cached);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return null;
  }

  Future<int> readFlashcardsTodayCount() async {
    final today = _todayKey();
    final storedDate = await _preferences.getString(flashcardsTodayDateKey);
    if (storedDate != today) {
      await _preferences.setString(flashcardsTodayDateKey, today);
      await _preferences.setInt(flashcardsTodayKey, 0);
      return 0;
    }
    return await _preferences.getInt(flashcardsTodayKey) ?? 0;
  }

  Future<int> incrementFlashcardsTodayCount({int amount = 1}) async {
    final today = _todayKey();
    final storedDate = await _preferences.getString(flashcardsTodayDateKey);
    if (storedDate != today) {
      await _preferences.setString(flashcardsTodayDateKey, today);
      await _preferences.setInt(flashcardsTodayKey, 0);
    }

    final current = await _preferences.getInt(flashcardsTodayKey) ?? 0;
    final next = current + amount;
    await _preferences.setInt(flashcardsTodayKey, next);
    return next;
  }

  String _todayKey() {
    return DateTime.now().toIso8601String().substring(0, 10);
  }
}

final userStatsCacheServiceProvider = Provider<UserStatsCacheService>(
  (ref) => UserStatsCacheService(),
);
