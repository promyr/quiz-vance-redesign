import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/flashcard/data/flashcard_repository.dart';
import 'package:quiz_vance_flutter/features/flashcard/domain/flashcard_model.dart';
import 'package:quiz_vance_flutter/features/flashcard/presentation/flashcard_hub_screen.dart';
import 'package:quiz_vance_flutter/features/flashcard/presentation/flashcard_screen.dart';

final _mojibakePattern = RegExp(
  '\\u00C3.|\\u00C2.|\\u00E2\\u20AC|\\u00F0\\u0178|\\u00EF\\u00B8|\\uFFFD',
);

Flashcard _card({required int id, String? remoteId}) {
  return Flashcard(
    id: id,
    remoteId: remoteId,
    front: 'Front $id',
    back: 'Back $id',
    dueDate: DateTime(2026, 3, 24),
    createdAt: DateTime(2026, 3, 24),
  );
}

void expectNoMojibake(String value) {
  expect(value, isNot(matches(_mojibakePattern)));
}

void main() {
  test('shouldSyncFlashcardReview aceita qualquer ID remoto valido', () {
    expect(shouldSyncFlashcardReview('legacy-1'), isTrue);
    expect(shouldSyncFlashcardReview('card-1'), isTrue);
    expect(shouldSyncFlashcardReview(null), isFalse);
  });

  test(
      'applyFlashcardReviewRewards conta atividade parcial para sessoes incompletas',
      () async {
    var todayCountCalls = 0;
    var xpAwarded = 0;
    var streakCalls = 0;

    await applyFlashcardReviewRewards(
      isSessionComplete: false,
      reviewedCardsCount: 4,
      incrementFlashcardsToday: () async {
        todayCountCalls++;
      },
      addXp: (amount) async {
        xpAwarded += amount;
      },
      incrementStreak: () async {
        streakCalls++;
      },
    );

    expect(todayCountCalls, equals(1));
    expect(xpAwarded, equals(0));
    expect(streakCalls, equals(0));
  });

  test('applyFlashcardReviewRewards concede XP e streak ao concluir sessao',
      () async {
    var todayCountCalls = 0;
    var xpAwarded = 0;
    var streakCalls = 0;

    await applyFlashcardReviewRewards(
      isSessionComplete: true,
      reviewedCardsCount: 4,
      incrementFlashcardsToday: () async {
        todayCountCalls++;
      },
      addXp: (amount) async {
        xpAwarded += amount;
      },
      incrementStreak: () async {
        streakCalls++;
      },
    );

    expect(todayCountCalls, equals(1));
    expect(xpAwarded, equals(20));
    expect(streakCalls, equals(1));
  });

  test('buildFlashcardHubReviewModel descreve cards pendentes', () {
    final model = buildFlashcardHubReviewModel(
      [
        _card(id: 1, remoteId: 'card-1'),
        _card(id: 2, remoteId: 'card-2'),
      ],
    );

    expect(model.isEmpty, isFalse);
    expect(model.bannerTitle, equals('2 cards para hoje'));
    expect(
      model.bannerSubtitle,
      equals('Revisao espacada com algoritmo FSRS'),
    );
    expect(model.ctaLabel, equals('Revisar 2 cards agora'));
    expectNoMojibake(model.bannerTitle);
    expectNoMojibake(model.bannerSubtitle);
    expectNoMojibake(model.ctaLabel);
  });

  test('buildFlashcardHubReviewModel preserva copy de revisao real', () {
    final model = buildFlashcardHubReviewModel(
      [_card(id: 1, remoteId: 'card-1')],
    );

    expect(model.isEmpty, isFalse);
    expect(model.bannerTitle, equals('1 card para hoje'));
    expect(model.ctaLabel, equals('Revisar 1 card agora'));
    expectNoMojibake(model.bannerTitle);
    expectNoMojibake(model.bannerSubtitle);
    expectNoMojibake(model.ctaLabel);
  });

  test('buildFlashcardHubReviewModel descreve estado vazio', () {
    final model = buildFlashcardHubReviewModel(const []);

    expect(model.isEmpty, isTrue);
    expect(model.bannerTitle, equals('Tudo em dia!'));
    expect(model.ctaLabel, equals('Sem cards pendentes hoje'));
    expectNoMojibake(model.bannerTitle);
    expectNoMojibake(model.bannerSubtitle);
    expectNoMojibake(model.ctaLabel);
  });
}
