/// Configuração já resolvida para iniciar ou continuar um quiz.
class QuizGenerationParams {
  const QuizGenerationParams({
    required this.topic,
    required this.difficulty,
    required this.aiProvider,
    this.conteudo,
    this.documentId,
    this.planId,
    this.studySessionId,
    this.quantity = 10,
  });

  final String topic;
  final String difficulty;
  final String? aiProvider;
  final String? conteudo;
  final int? documentId;
  final String? planId;
  final String? studySessionId;
  final int quantity;
}
