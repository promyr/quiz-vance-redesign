import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_storage.dart';

const userStatsCacheKey = 'user_stats_cache';

class UserStatsCacheService {
  UserStatsCacheService({
    LocalStorage? storage,
  }) : _storage = storage ?? LocalStorage.instance;

  final LocalStorage _storage;

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
}

final userStatsCacheServiceProvider = Provider<UserStatsCacheService>(
  (ref) => UserStatsCacheService(),
);
