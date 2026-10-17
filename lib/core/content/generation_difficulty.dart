/// New generation mixes medium and hard questions; legacy easy/medium settings
/// no longer request easy questions. Explicit hard sessions remain hard.
const mixedGenerationDifficulty = 'mixed';

String normalizeGenerationDifficulty(String difficulty) {
  return switch (difficulty.trim().toLowerCase()) {
    'hard' ||
    'dificil' ||
    'difícil' ||
    'avancado' ||
    'avançado' ||
    'mestre' =>
      'hard',
    _ => mixedGenerationDifficulty,
  };
}
