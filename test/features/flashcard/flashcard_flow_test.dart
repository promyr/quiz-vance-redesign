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
      'applyFlashcardReviewRewards registra progresso a cada review',
      () async {
    var todayCountCalls = 0;
    var reviewCalls = 0;

    await applyFlashcardReviewRewards(
      incrementFlashcardsToday: () async {
        todayCountCalls++;
      },
      recordFlashcardReview: () async {
        reviewCalls++;
      },
    );

    expect(todayCountCalls, equals(1));
    expect(reviewCalls, equals(1));
  });

  test('applyFlashcardReviewRewards tolera falha de gamificacao sem travar',
      () async {
    var todayCountCalls = 0;

    await applyFlashcardReviewRewards(
      incrementFlashcardsToday: () async {
        todayCountCalls++;
      },
      recordFlashcardReview: () async {
        throw Exception('gamification down');
      },
    );

    expect(todayCountCalls, equals(1));
  });

  test('buildFlashcardHubReviewModel descreve cards pendentes', () {
    final model = buildFlashcardHubReviewModel(
      [
        _card(id: 1, remoteId: 'card-1'),
        _card(id: 2, remoteId: 'card-2'),
      ],
    );

    expect(model.isEmpty, isFalse);
    expect(model.hasDueCards, isTrue);
    expect(model.bannerTitle, equals('2 cards para hoje'));
    expect(
      model.bannerSubtitle,
      equals('Pendentes primeiro, depois o restante do deck continua.'),
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
    expect(model.hasDueCards, isTrue);
    expect(model.bannerTitle, equals('1 card para hoje'));
    expect(model.ctaLabel, equals('Revisar 1 card agora'));
    expectNoMojibake(model.bannerTitle);
    expectNoMojibake(model.bannerSubtitle);
    expectNoMojibake(model.ctaLabel);
  });

  test('buildFlashcardHubReviewModel habilita revisao continua sem pendencias',
      () {
    final model = buildFlashcardHubReviewModel(
      [
        Flashcard(
          id: 1,
          remoteId: 'card-1',
          front: 'Front 1',
          back: 'Back 1',
          dueDate: DateTime(2999, 1, 1),
          createdAt: DateTime(2026, 3, 24),
        ),
      ],
    );

    expect(model.isEmpty, isFalse);
    expect(model.hasDueCards, isFalse);
    expect(model.bannerTitle, equals('Revisão contínua pronta'));
    expect(model.ctaLabel, equals('Continuar revisão'));
    expectNoMojibake(model.bannerTitle);
    expectNoMojibake(model.bannerSubtitle);
    expectNoMojibake(model.ctaLabel);
  });

  test('buildFlashcardHubReviewModel descreve estado sem deck salvo', () {
    final model = buildFlashcardHubReviewModel(const []);

    expect(model.isEmpty, isTrue);
    expect(model.hasDueCards, isFalse);
    expect(model.bannerTitle, equals('Nenhum flashcard salvo'));
    expect(model.ctaLabel, equals('Gerar flashcards para estudar'));
    expectNoMojibake(model.bannerTitle);
    expectNoMojibake(model.bannerSubtitle);
    expectNoMojibake(model.ctaLabel);
  });
}
