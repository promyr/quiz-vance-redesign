import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class RankingEntry {
  const RankingEntry({
    required this.userId,
    required this.name,
    required this.xp,
    required this.position,
    this.avatarUrl,
    this.isCurrentUser = false,
    this.accuracy = 0.0,
    this.totalQuestoes = 0,
    this.streakDays = 0,
    this.clientApp,
    this.rankingNamespace,
  });

  factory RankingEntry.fromJson(Map<String, dynamic> json) => RankingEntry(
        userId: json['user_id']?.toString() ?? json['id']?.toString() ?? '',
        name: json['name'] as String? ?? 'Usuario',
        xp: (json['period_xp'] as num?)?.toInt() ??
            (json['xp'] as num?)?.toInt() ??
            0,
        position: (json['position'] as num?)?.toInt() ?? 0,
        avatarUrl: json['avatar_url'] as String?,
        isCurrentUser: (json['is_current_user'] as bool?) ?? false,
        accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
        totalQuestoes: (json['total_questoes'] as num?)?.toInt() ?? 0,
        streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
        clientApp: json['client_app'] as String? ??
            json['source_app'] as String? ??
            json['app_id'] as String?,
        rankingNamespace: json['ranking_namespace'] as String? ??
            json['app_namespace'] as String? ??
            json['client_namespace'] as String?,
      );

  final String userId;
  final String name;
  final int xp;
  final int position;
  final String? avatarUrl;
  final bool isCurrentUser;

  /// Taxa de acertos no período (0–100).
  final double accuracy;

  /// Total de questões respondidas no período.
  final int totalQuestoes;

  /// Sequência de dias de estudo atual do usuário.
  final int streakDays;
  final String? clientApp;
  final String? rankingNamespace;
}

List<RankingEntry> sanitizeRankingEntries(
  List<RankingEntry> entries, {
  String? currentUserId,
  String? currentUserName,
}) {
  final supportsVersionSegmentation = entries.any(_hasVersionMarker);
  final filtered = entries.where((entry) {
    final isCurrentUser = entry.isCurrentUser ||
        (currentUserId != null &&
            currentUserId.isNotEmpty &&
            entry.userId == currentUserId);
    if (isCurrentUser) {
      return true;
    }

    if (isOperationalRankingEntry(entry)) {
      return false;
    }

    if (!supportsVersionSegmentation) {
      return true;
    }

    return belongsToCurrentRankingNamespace(entry);
  }).toList(growable: false);

  final deduped = _dedupeRankingEntries(
    filtered,
    currentUserId: currentUserId,
    currentUserName: currentUserName,
  );
  deduped.sort(_compareRankingEntries);
  return deduped;
}

bool hasReliableRankingPodium(List<RankingEntry> entries) {
  if (entries.length < 3) return false;
  final top3 = entries.take(3);
  return top3.any(
    (entry) => entry.xp > 0 || entry.totalQuestoes > 0 || entry.streakDays > 0,
  );
}

bool isOperationalRankingEntry(RankingEntry entry) {
  final normalizedUserId = entry.userId.trim().toLowerCase();
  final normalizedName = entry.name.trim().toLowerCase();

  const blockedNameFragments = [
    'smoke',
    'smoke test',
    'shadow',
    'shadow test',
    'qa login',
    'qa ',
    'app version smoke',
  ];

  if (normalizedUserId.isEmpty) {
    return blockedNameFragments.any(normalizedName.contains);
  }

  return blockedNameFragments.any(normalizedName.contains);
}

bool belongsToCurrentRankingNamespace(RankingEntry entry) {
  final normalizedNamespace = entry.rankingNamespace?.trim().toLowerCase();
  if (normalizedNamespace != null && normalizedNamespace.isNotEmpty) {
    return normalizedNamespace == AppConfig.rankingNamespace;
  }

  final normalizedClientApp = entry.clientApp?.trim().toLowerCase();
  if (normalizedClientApp != null && normalizedClientApp.isNotEmpty) {
    return normalizedClientApp == AppConfig.clientAppId;
  }

  return false;
}

bool _hasVersionMarker(RankingEntry entry) {
  final normalizedNamespace = entry.rankingNamespace?.trim();
  if (normalizedNamespace != null && normalizedNamespace.isNotEmpty) {
    return true;
  }

  final normalizedClientApp = entry.clientApp?.trim();
  return normalizedClientApp != null && normalizedClientApp.isNotEmpty;
}

List<RankingEntry> _dedupeRankingEntries(
  List<RankingEntry> entries, {
  String? currentUserId,
  String? currentUserName,
}) {
  final merged = <String, RankingEntry>{};

  for (final entry in entries) {
    final key = _dedupeKey(
      entry,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
    );
    final existing = merged[key];
    if (existing == null) {
      merged[key] = entry;
      continue;
    }

    merged[key] = _mergeRankingEntries(
      existing,
      entry,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
    );
  }

  return merged.values.toList(growable: false);
}

String _dedupeKey(
  RankingEntry entry, {
  String? currentUserId,
  String? currentUserName,
}) {
  if (_isCurrentUserEntry(
    entry,
    currentUserId: currentUserId,
    currentUserName: currentUserName,
  )) {
    return 'current-user';
  }

  final userId = entry.userId.trim().toLowerCase();
  if (userId.isNotEmpty) {
    return 'id:$userId';
  }

  return 'name:${_normalizeRankingText(entry.name)}';
}

bool _isCurrentUserEntry(
  RankingEntry entry, {
  String? currentUserId,
  String? currentUserName,
}) {
  if (entry.isCurrentUser) return true;

  if (currentUserId != null &&
      currentUserId.isNotEmpty &&
      entry.userId == currentUserId) {
    return true;
  }

  if (currentUserName == null || currentUserName.trim().isEmpty) {
    return false;
  }

  return _isNameVariant(entry.name, currentUserName);
}

bool _isNameVariant(String a, String b) {
  final normalizedA = _normalizeRankingText(a);
  final normalizedB = _normalizeRankingText(b);
  if (normalizedA.isEmpty || normalizedB.isEmpty) return false;
  if (normalizedA == normalizedB) return true;
  if (normalizedA.startsWith('$normalizedB ') ||
      normalizedB.startsWith('$normalizedA ')) {
    return true;
  }
  return false;
}

String _normalizeRankingText(String value) {
  final lower = value.trim().toLowerCase();
  if (lower.isEmpty) return '';

  const replacements = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };

  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final replaced = replacements[char] ?? char;
    if (RegExp(r'[a-z0-9 ]').hasMatch(replaced)) {
      buffer.write(replaced);
      continue;
    }
    if (RegExp(r'[_\-.]').hasMatch(replaced)) {
      buffer.write(' ');
    }
  }

  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

RankingEntry _mergeRankingEntries(
  RankingEntry left,
  RankingEntry right, {
  String? currentUserId,
  String? currentUserName,
}) {
  final preferredName = _preferredDisplayName(
    left.name,
    right.name,
    currentUserName: currentUserName,
  );

  return RankingEntry(
    userId: _preferCurrentUserId(
      left.userId,
      right.userId,
      currentUserId: currentUserId,
    ),
    name: preferredName,
    xp: left.xp >= right.xp ? left.xp : right.xp,
    position: left.position <= right.position ? left.position : right.position,
    avatarUrl: left.avatarUrl ?? right.avatarUrl,
    isCurrentUser: left.isCurrentUser || right.isCurrentUser,
    accuracy: left.accuracy >= right.accuracy ? left.accuracy : right.accuracy,
    totalQuestoes: left.totalQuestoes >= right.totalQuestoes
        ? left.totalQuestoes
        : right.totalQuestoes,
    streakDays: left.streakDays >= right.streakDays
        ? left.streakDays
        : right.streakDays,
    clientApp: left.clientApp ?? right.clientApp,
    rankingNamespace: left.rankingNamespace ?? right.rankingNamespace,
  );
}

String _preferCurrentUserId(
  String left,
  String right, {
  String? currentUserId,
}) {
  if (currentUserId != null && currentUserId.isNotEmpty) {
    if (left == currentUserId) return left;
    if (right == currentUserId) return right;
  }
  if (left.trim().isNotEmpty) return left;
  return right;
}

String _preferredDisplayName(
  String left,
  String right, {
  String? currentUserName,
}) {
  if (currentUserName != null && currentUserName.trim().isNotEmpty) {
    if (_isNameVariant(left, currentUserName) ||
        _isNameVariant(right, currentUserName)) {
      return currentUserName.trim();
    }
  }

  final trimmedLeft = left.trim();
  final trimmedRight = right.trim();
  if (trimmedLeft.length == trimmedRight.length) {
    return trimmedLeft.compareTo(trimmedRight) <= 0
        ? trimmedLeft
        : trimmedRight;
  }
  return trimmedLeft.length >= trimmedRight.length ? trimmedLeft : trimmedRight;
}

int _compareRankingEntries(RankingEntry a, RankingEntry b) {
  final xpCompare = b.xp.compareTo(a.xp);
  if (xpCompare != 0) return xpCompare;

  final totalCompare = b.totalQuestoes.compareTo(a.totalQuestoes);
  if (totalCompare != 0) return totalCompare;

  final accuracyCompare = b.accuracy.compareTo(a.accuracy);
  if (accuracyCompare != 0) return accuracyCompare;

  final streakCompare = b.streakDays.compareTo(a.streakDays);
  if (streakCompare != 0) return streakCompare;

  final positionCompare = a.position.compareTo(b.position);
  if (positionCompare != 0) return positionCompare;

  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

class RankingRepository {
  const RankingRepository(this._client);

  final ApiClient _client;

  Future<List<RankingEntry>> getWeekly() => _fetch(ApiEndpoints.rankingWeekly);
  Future<List<RankingEntry>> getMonthly() =>
      _fetch(ApiEndpoints.rankingMonthly);
  Future<List<RankingEntry>> getGlobal() => _fetch(ApiEndpoints.rankingGlobal);

  Future<List<RankingEntry>> _fetch(String endpoint) async {
    try {
      final response = await _client.dio.get(endpoint);
      final data = response.data;
      if (data == null || data is! Map) {
        throw const RemoteServiceException(
          'O ranking retornou um formato invalido.',
        );
      }
      final list = ((data['ranking'] as List<dynamic>?) ?? const [])
          .cast<Map<String, dynamic>>();
      return list.map(RankingEntry.fromJson).toList();
    } on RemoteServiceException {
      rethrow;
    } catch (_) {
      throw const RemoteServiceException(
        'Não foi possível carregar o ranking agora.',
      );
    }
  }
}

final rankingRepositoryProvider = Provider<RankingRepository>(
  (ref) => RankingRepository(ref.watch(apiClientProvider)),
);

final weeklyRankingProvider =
    FutureProvider.autoDispose<List<RankingEntry>>((ref) {
  return ref.watch(rankingRepositoryProvider).getWeekly();
});

final monthlyRankingProvider =
    FutureProvider.autoDispose<List<RankingEntry>>((ref) {
  return ref.watch(rankingRepositoryProvider).getMonthly();
});

final globalRankingProvider =
    FutureProvider.autoDispose<List<RankingEntry>>((ref) {
  return ref.watch(rankingRepositoryProvider).getGlobal();
});
