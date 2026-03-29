/// Modelo para questões dissertativas de Quiz Aberto.
class OpenQuestion {
  final String pergunta;
  final String contexto;
  final String respostaEsperada;

  const OpenQuestion({
    required this.pergunta,
    required this.contexto,
    required this.respostaEsperada,
  });

  /// Converte JSON para [OpenQuestion].
  factory OpenQuestion.fromJson(Map<String, dynamic> j) => OpenQuestion(
    pergunta: j['pergunta'] as String? ?? '',
    contexto: j['contexto'] as String? ?? '',
    respostaEsperada: j['resposta_esperada'] as String? ?? '',
  );

  /// Converte [OpenQuestion] para JSON.
  Map<String, dynamic> toJson() => {
    'pergunta': pergunta,
    'contexto': contexto,
    'resposta_esperada': respostaEsperada,
  };
}

/// Modelo de avaliação/nota de uma questão dissertativa.
class OpenGrade {
  final int nota;
  final bool correto;
  final String feedback;
  final List<String> pontosForts;
  final List<String> pontosMelhorar;
  final Map<String, int> criterios; // aderencia, estrutura, clareza, fundamentacao

  const OpenGrade({
    required this.nota,
    required this.correto,
    required this.feedback,
    required this.pontosForts,
    required this.pontosMelhorar,
    required this.criterios,
  });

  /// Converte JSON para [OpenGrade].
  factory OpenGrade.fromJson(Map<String, dynamic> j) => OpenGrade(
    nota: (j['nota'] as num?)?.toInt() ?? 0,
    correto: (j['correto'] as bool?) ?? false,
    feedback: j['feedback'] as String? ?? '',
    pontosForts: List<String>.from(j['pontos_fortes'] ?? []),
    pontosMelhorar: List<String>.from(j['pontos_melhorar'] ?? []),
    criterios: Map<String, int>.from(
      (j['criterios'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      ),
    ),
  );

  /// Converte [OpenGrade] para JSON.
  Map<String, dynamic> toJson() => {
    'nota': nota,
    'correto': correto,
    'feedback': feedback,
    'pontos_fortes': pontosForts,
    'pontos_melhorar': pontosMelhorar,
    'criterios': criterios,
  };
}
