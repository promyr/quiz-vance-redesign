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
  Map<String, dynamic> toJson() => {
        'topic': topic,
        'difficulty': difficulty,
        'provider': aiProvider,
        'content': conteudo?.substring(0, conteudo!.length.clamp(0, 4000)),
        'documentId': documentId,
        'planId': planId,
        'sessionId': studySessionId,
        'quantity': quantity,
      };
  factory QuizGenerationParams.fromJson(Map<String, dynamic> data) =>
      QuizGenerationParams(
        topic: data['topic'] as String,
        difficulty: data['difficulty'] as String,
        aiProvider: data['provider'] as String?,
        conteudo: data['content'] as String?,
        documentId: data['documentId'] as int?,
        planId: data['planId'] as String?,
        studySessionId: data['sessionId'] as String?,
        quantity: data['quantity'] as int? ?? 10,
      );
}
