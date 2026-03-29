import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/local_storage.dart';

const userStatsCacheKey = 'user_stats_cache';
const flashcardsTodayKey = 'flashcards_today_count';
const flashcardsTodayDateKey = 'flashcards_today_date';

class UserStatsCacheService {
  UserStatsCacheService({
    LocalStorage? storage,
  }) : _storage = storage ?? LocalStorage.instance;

  final LocalStorage _storage;

  Future<void> saveRemoteStatsPayload(Map<String, dynamic> payload) {
    return _storage.setCacheValue(userStatsCacheKey, jsonEncode(payload));
  }

  Future<Map<String, dynamic>?> readRemoteStatsPayload() async {
    final cached = await _storage.getCacheValue(userStatsCacheKey);
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
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final storedDate = prefs.getString(flashcardsTodayDateKey);
    if (storedDate != today) {
      await prefs.setString(flashcardsTodayDateKey, today);
      await prefs.setInt(flashcardsTodayKey, 0);
      return 0;
    }
    return prefs.getInt(flashcardsTodayKey) ?? 0;
  }

  Future<int> incrementFlashcardsTodayCount({int amount = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final storedDate = prefs.getString(flashcardsTodayDateKey);
    if (storedDate != today) {
      await prefs.setString(flashcardsTodayDateKey, today);
      await prefs.setInt(flashcardsTodayKey, 0);
    }

    final current = prefs.getInt(flashcardsTodayKey) ?? 0;
    final next = current + amount;
    await prefs.setInt(flashcardsTodayKey, next);
    return next;
  }

  String _todayKey() {
    return DateTime.now().toIso8601String().substring(0, 10);
  }
}

final userStatsCacheServiceProvider = Provider<UserStatsCacheService>(
  (ref) => UserStatsCacheService(),
);
