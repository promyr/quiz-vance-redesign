import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/ranking/data/ranking_repository.dart';
import 'package:quiz_vance_flutter/features/ranking/presentation/ranking_screen.dart';

void main() {
  test(
      'buildRankingDisplayModel shows compact list when fewer than 3 entries remain',
      () {
    final entries = [
      const RankingEntry(userId: 'u1', name: 'Alice', xp: 120, position: 1),
      const RankingEntry(userId: 'u2', name: 'Bob', xp: 80, position: 2),
    ];

    final display = buildRankingDisplayModel(entries);

    expect(display.podiumEntries, isEmpty);
    expect(display.listEntries, entries);
    expect(display.listStartRank, 1);
  });

  test('buildRankingDisplayModel keeps podium behavior for 3 or more entries',
      () {
    final entries = [
      const RankingEntry(userId: 'u1', name: 'Alice', xp: 120, position: 1),
      const RankingEntry(userId: 'u2', name: 'Bob', xp: 80, position: 2),
      const RankingEntry(userId: 'u3', name: 'Carol', xp: 50, position: 3),
      const RankingEntry(userId: 'u4', name: 'Dan', xp: 20, position: 4),
    ];

    final display = buildRankingDisplayModel(entries);

    expect(
        display.podiumEntries.map((entry) => entry.userId), ['u1', 'u2', 'u3']);
    expect(display.listEntries.map((entry) => entry.userId), ['u4']);
    expect(display.listStartRank, 4);
  });

  test('buildRankingDisplayModel disables podium when top entries are all zero',
      () {
    final entries = [
      const RankingEntry(userId: 'u1', name: 'Bel', xp: 0, position: 1),
      const RankingEntry(userId: 'u2', name: 'Dan', xp: 0, position: 2),
      const RankingEntry(userId: 'u3', name: 'Bob', xp: 0, position: 3),
      const RankingEntry(userId: 'u4', name: 'Ana', xp: 0, position: 4),
    ];

    final display = buildRankingDisplayModel(entries);

    expect(display.podiumEntries, isEmpty);
    expect(display.listEntries, entries);
    expect(display.listStartRank, 1);
  });
}
