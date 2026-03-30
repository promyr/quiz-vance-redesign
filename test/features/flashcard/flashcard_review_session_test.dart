import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/flashcard/domain/flashcard_model.dart';
import 'package:quiz_vance_flutter/features/flashcard/domain/flashcard_review_session.dart';

Flashcard _card(int id) => Flashcard(
      id: id,
      remoteId: 'card-$id',
      front: 'Front $id',
      back: 'Back $id',
      dueDate: DateTime(2026, 3, 24),
      createdAt: DateTime(2026, 3, 24),
    );

void main() {
  test('inicia sessao com deck ativo e ciclo zerado', () {
    final result = startFlashcardReviewSession([_card(1), _card(2)]);

    expect(result.activeCards.map((card) => card.id).toList(), equals([1, 2]));
    expect(result.nextCycleCards, isEmpty);
    expect(result.currentIndex, equals(0));
    expect(result.reviewedCount, equals(0));
    expect(result.cycleTotalCount, equals(2));
    expect(result.waitingForNextCycle, isFalse);
  });

  test('avanca para o proximo card sem repetir no mesmo ciclo', () {
    final result = advanceFlashcardReviewSession(
      activeCards: [_card(1), _card(2), _card(3)],
      nextCycleCards: const <Flashcard>[],
      currentIndex: 0,
      reviewedCount: 0,
      cycleTotalCount: 3,
      reviewedCard: _card(1).copyWith(intervalDays: 3),
    );

    expect(result.activeCards.map((card) => card.id).toList(), equals([2, 3]));
    expect(result.nextCycleCards.map((card) => card.id).toList(), equals([1]));
    expect(result.currentIndex, equals(0));
    expect(result.reviewedCount, equals(1));
    expect(result.waitingForNextCycle, isFalse);
  });

  test('fecha o ciclo ao revisar o ultimo card restante', () {
    final result = advanceFlashcardReviewSession(
      activeCards: [_card(2)],
      nextCycleCards: [_card(1)],
      currentIndex: 0,
      reviewedCount: 1,
      cycleTotalCount: 2,
      reviewedCard: _card(2).copyWith(intervalDays: 4),
    );

    expect(result.activeCards, isEmpty);
    expect(result.nextCycleCards.map((card) => card.id).toList(), equals([1, 2]));
    expect(result.reviewedCount, equals(2));
    expect(result.waitingForNextCycle, isTrue);
  });

  test('inicia novo ciclo apenas quando o usuario decide continuar', () {
    final result = continueFlashcardReviewSession([_card(1), _card(2)]);

    expect(result.activeCards.map((card) => card.id).toList(), equals([1, 2]));
    expect(result.nextCycleCards, isEmpty);
    expect(result.currentIndex, equals(0));
    expect(result.reviewedCount, equals(0));
    expect(result.cycleTotalCount, equals(2));
    expect(result.waitingForNextCycle, isFalse);
  });
}
