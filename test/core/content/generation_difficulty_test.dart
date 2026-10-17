import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/core/content/generation_difficulty.dart';

void main() {
  test('new generation defaults to medium and hard mix', () {
    expect(mixedGenerationDifficulty, 'mixed');
    for (final legacy in [
      'easy',
      'facil',
      'medium',
      'intermediario',
      'mixed',
      ''
    ]) {
      expect(normalizeGenerationDifficulty(legacy), 'mixed', reason: legacy);
    }
  });

  test('explicit hard sessions remain hard', () {
    for (final difficulty in [
      'hard',
      'dificil',
      'difícil',
      'avancado',
      'avançado',
      'mestre',
      ' HARD '
    ]) {
      expect(normalizeGenerationDifficulty(difficulty), 'hard',
          reason: difficulty);
    }
  });
}
