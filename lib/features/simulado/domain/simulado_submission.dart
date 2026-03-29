/// Modelo de domínio que representa o payload enviado ao backend após
/// a conclusão de um simulado. Encapsula toda a lógica de serialização,
/// mantendo [SimuladoResultScreen] livre de detalhes de transporte.
class SimuladoSubmission {
  const SimuladoSubmission({
    required this.correct,
    required this.total,
    required this.accuracy,
    required this.xpEarned,
    required this.timeTakenSeconds,
    this.topic,
  });

  final int correct;
  final int total;

  /// Taxa de acerto entre 0.0 e 1.0.
  final double accuracy;

  final int xpEarned;
  final int timeTakenSeconds;

  /// Assunto do simulado, se configurado pelo usuário.
  final String? topic;

  Map<String, dynamic> toJson() => {
        'correct': correct,
        'total': total,
        'accuracy': accuracy,
        'xp_earned': xpEarned,
        'time_taken_seconds': timeTakenSeconds,
        if (topic != null && topic!.isNotEmpty) 'topic': topic,
      };
}
