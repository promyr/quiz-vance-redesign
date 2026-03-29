import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/ranking/data/ranking_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;

  setUp(() {
    apiClient = _MockApiClient();
    dio = _MockDio();
    when(() => apiClient.dio).thenReturn(dio);
  });

  test('sanitizeRankingEntries keeps real zero-xp users', () {
    final entries = [
      const RankingEntry(userId: 'u1', name: 'Alice', xp: 120, position: 1),
      const RankingEntry(userId: 'u2', name: 'Bob', xp: 0, position: 2),
    ];

    final sanitized = sanitizeRankingEntries(entries, currentUserId: 'u1');

    expect(sanitized.map((entry) => entry.userId), ['u1', 'u2']);
  });

  test('sanitizeRankingEntries removes known operational accounts', () {
    final entries = [
      const RankingEntry(userId: 'u1', name: 'Alice', xp: 120, position: 1),
      const RankingEntry(userId: 'u2', name: 'Smoke Test', xp: 0, position: 2),
      const RankingEntry(userId: 'u3', name: 'QA Login ID', xp: 0, position: 3),
    ];

    final sanitized = sanitizeRankingEntries(entries, currentUserId: 'u1');

    expect(sanitized.map((entry) => entry.userId), ['u1']);
  });

  test('sanitizeRankingEntries keeps backend-marked current user', () {
    final entries = [
      const RankingEntry(
        userId: 'u2',
        name: 'Belchior',
        xp: 0,
        position: 2,
        isCurrentUser: true,
      ),
    ];

    final sanitized = sanitizeRankingEntries(entries);

    expect(sanitized, hasLength(1));
    expect(sanitized.first.userId, 'u2');
  });

  test(
      'sanitizeRankingEntries keeps current user even if name matches operational pattern',
      () {
    final entries = [
      const RankingEntry(
        userId: 'u2',
        name: 'Smoke Test',
        xp: 0,
        position: 2,
      ),
    ];

    final sanitized = sanitizeRankingEntries(entries, currentUserId: 'u2');

    expect(sanitized, hasLength(1));
    expect(sanitized.first.userId, 'u2');
  });

  test(
      'sanitizeRankingEntries keeps only redesigned app accounts when backend provides namespace markers',
      () {
    final entries = [
      const RankingEntry(
        userId: 'u1',
        name: 'Conta Nova',
        xp: 120,
        position: 1,
        rankingNamespace: 'quiz-vance-redesign-v2',
      ),
      const RankingEntry(
        userId: 'u2',
        name: 'Conta Antiga',
        xp: 80,
        position: 2,
        rankingNamespace: 'quiz-vance-legacy-v1',
      ),
    ];

    final sanitized = sanitizeRankingEntries(entries);

    expect(sanitized.map((entry) => entry.userId), ['u1']);
  });

  test('sanitizeRankingEntries removes generic smoke account names', () {
    final entries = [
      const RankingEntry(userId: 'u1', name: 'Smoke', xp: 0, position: 1),
      const RankingEntry(userId: 'u2', name: 'Belchior', xp: 0, position: 2),
    ];

    final sanitized = sanitizeRankingEntries(entries);

    expect(sanitized.map((entry) => entry.userId), ['u2']);
  });

  test('sanitizeRankingEntries merges current user name variants', () {
    final entries = [
      const RankingEntry(
        userId: 'legacy-id',
        name: 'belchior',
        xp: 0,
        position: 1,
      ),
      const RankingEntry(
        userId: 'user-123',
        name: 'Belchior oliveira',
        xp: 0,
        position: 5,
        isCurrentUser: true,
      ),
    ];

    final sanitized = sanitizeRankingEntries(
      entries,
      currentUserId: 'user-123',
      currentUserName: 'Belchior Oliveira',
    );

    expect(sanitized, hasLength(1));
    expect(sanitized.first.userId, 'user-123');
    expect(sanitized.first.name, 'Belchior Oliveira');
    expect(sanitized.first.isCurrentUser, isTrue);
  });

  test('repository throws explicit error when ranking payload is invalid',
      () async {
    when(() => dio.get(ApiEndpoints.rankingWeekly)).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.rankingWeekly),
        data: 'payload-invalido',
      ),
    );

    final repository = RankingRepository(apiClient);

    await expectLater(
      repository.getWeekly(),
      throwsA(isA<RemoteServiceException>()),
    );
  });
}
