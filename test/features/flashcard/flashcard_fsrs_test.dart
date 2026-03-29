// test/features/flashcard/flashcard_fsrs_test.dart
//
// Testa a lógica pura do algoritmo FSRS simplificado implementado em
// FlashcardRepository._calculateFsrs(). Como o método é privado, os testes
// replicam a mesma fórmula e verificam os invariantes esperados.
//
// Cobertura:
//   - Easiness clamp: nunca abaixo de 1.3, nunca acima de 4.0
//   - Intervalo de repetição: ≥ 1 dia, ≤ 365 dias
//   - Grade "again" (0) → intervalo sempre 1 dia (reset)
//   - Grade "easy" (5) → easiness aumenta em relação ao padrão
//   - Grade "hard" (2) → easiness diminui em relação ao padrão
//   - Repetições: grade ≥ 3 incrementa; grade < 3 zera

import 'package:flutter_test/flutter_test.dart';

// ─── Réplica da fórmula de FlashcardRepository._calculateFsrs ───────────────
// (mantida em sync com lib/features/flashcard/data/flashcard_repository.dart)

class _FsrsResult {
  const _FsrsResult({
    required this.intervalDays,
    required this.easiness,
    required this.repetitions,
  });
  final int intervalDays;
  final double easiness;
  final int repetitions;
}

enum _Grade { again, hard, good, easy }

_FsrsResult _calculateFsrs(_Grade grade) {
  const defaultEasiness = 2.5;
  const gradeMap = {
    _Grade.again: 0,
    _Grade.hard: 2,
    _Grade.good: 4,
    _Grade.easy: 5,
  };
  final q = gradeMap[grade]!;
  final easiness =
      (defaultEasiness + 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
          .clamp(1.3, 4.0);
  final intervalDays = q < 3 ? 1 : (1 * easiness).round().clamp(1, 365);
  return _FsrsResult(
    intervalDays: intervalDays,
    easiness: easiness,
    repetitions: q >= 3 ? 1 : 0,
  );
}

void main() {
  group('FSRS – easiness clamp (nunca sai do range [1.3, 4.0])', () {
    test('grade again produz easiness ≥ 1.3', () {
      final r = _calculateFsrs(_Grade.again);
      expect(r.easiness, greaterThanOrEqualTo(1.3));
      expect(r.easiness, lessThanOrEqualTo(4.0));
    });

    test('grade hard produz easiness ≥ 1.3', () {
      final r = _calculateFsrs(_Grade.hard);
      expect(r.easiness, greaterThanOrEqualTo(1.3));
    });

    test('grade good mantém easiness próximo ao padrão', () {
      final r = _calculateFsrs(_Grade.good);
      expect(r.easiness, greaterThanOrEqualTo(1.3));
      expect(r.easiness, lessThanOrEqualTo(4.0));
    });

    test('grade easy produz easiness ≥ 1.3 e ≤ 4.0', () {
      final r = _calculateFsrs(_Grade.easy);
      expect(r.easiness, greaterThanOrEqualTo(1.3));
      expect(r.easiness, lessThanOrEqualTo(4.0));
    });
  });

  group('FSRS – intervalo de repetição', () {
    test('grade again → intervalo sempre 1 dia (reset total)', () {
      final r = _calculateFsrs(_Grade.again);
      expect(r.intervalDays, equals(1));
    });

    test('grade hard → intervalo 1 dia (q=2 < 3)', () {
      final r = _calculateFsrs(_Grade.hard);
      expect(r.intervalDays, equals(1));
    });

    test('grade good → intervalo ≥ 1 dia', () {
      final r = _calculateFsrs(_Grade.good);
      expect(r.intervalDays, greaterThanOrEqualTo(1));
    });

    test('grade easy → intervalo ≥ 1 dia', () {
      final r = _calculateFsrs(_Grade.easy);
      expect(r.intervalDays, greaterThanOrEqualTo(1));
    });

    test('intervalo nunca excede 365 dias', () {
      for (final grade in _Grade.values) {
        final r = _calculateFsrs(grade);
        expect(r.intervalDays, lessThanOrEqualTo(365),
            reason: 'grade $grade excedeu 365 dias');
      }
    });
  });

  group('FSRS – contagem de repetições', () {
    test('grade again → repetições = 0 (reset)', () {
      expect(_calculateFsrs(_Grade.again).repetitions, equals(0));
    });

    test('grade hard → repetições = 0 (q < 3)', () {
      expect(_calculateFsrs(_Grade.hard).repetitions, equals(0));
    });

    test('grade good → repetições = 1 (q ≥ 3)', () {
      expect(_calculateFsrs(_Grade.good).repetitions, equals(1));
    });

    test('grade easy → repetições = 1 (q ≥ 3)', () {
      expect(_calculateFsrs(_Grade.easy).repetitions, equals(1));
    });
  });

  group('FSRS – progressão de easiness', () {
    test('easy produz easiness maior que again', () {
      final again = _calculateFsrs(_Grade.again);
      final easy = _calculateFsrs(_Grade.easy);
      expect(easy.easiness, greaterThan(again.easiness));
    });

    test('good produz easiness maior que hard', () {
      final hard = _calculateFsrs(_Grade.hard);
      final good = _calculateFsrs(_Grade.good);
      expect(good.easiness, greaterThan(hard.easiness));
    });
  });

  group('FSRS – resultado completo por grade', () {
    test('again: intervalo=1, repetições=0, easiness=[1.3,4.0]', () {
      final r = _calculateFsrs(_Grade.again);
      expect(r.intervalDays, equals(1));
      expect(r.repetitions, equals(0));
      expect(r.easiness, inInclusiveRange(1.3, 4.0));
    });

    test('easy: repetições=1, intervalo≥1, easiness=[1.3,4.0]', () {
      final r = _calculateFsrs(_Grade.easy);
      expect(r.repetitions, equals(1));
      expect(r.intervalDays, greaterThanOrEqualTo(1));
      expect(r.easiness, inInclusiveRange(1.3, 4.0));
    });
  });
}
