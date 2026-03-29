/// Representa um item individual do plano de estudo semanal.
///
/// Modelo imutável — use [copyWith] para criar uma versão modificada.
class StudyPlanItem {
  const StudyPlanItem({
    this.id,
    required this.dia,
    required this.tema,
    required this.atividade,
    required this.duracaoMin,
    required this.prioridade,
    this.concluido = false,
  });

  /// Desserializa um item do JSON.
  factory StudyPlanItem.fromJson(Map<String, dynamic> j) => StudyPlanItem(
        id: (j['id'] as num?)?.toInt(),
        dia: j['dia'] as String? ?? '',
        tema: j['tema'] as String? ?? '',
        atividade: j['atividade'] as String? ?? '',
        duracaoMin: (j['duracao_min'] as num?)?.toInt() ?? 30,
        prioridade: (j['prioridade'] as num?)?.toInt() ?? 2,
        concluido: (j['concluido'] as bool?) ?? false,
      );

  final int? id;
  final String dia; // "Segunda", "Terça", etc.
  final String tema;
  final String atividade;
  final int duracaoMin;
  final int prioridade; // 1 = alta, 2 = normal
  final bool concluido;

  /// Retorna uma cópia com os campos informados substituídos.
  StudyPlanItem copyWith({
    int? id,
    String? dia,
    String? tema,
    String? atividade,
    int? duracaoMin,
    int? prioridade,
    bool? concluido,
  }) {
    return StudyPlanItem(
      id: id ?? this.id,
      dia: dia ?? this.dia,
      tema: tema ?? this.tema,
      atividade: atividade ?? this.atividade,
      duracaoMin: duracaoMin ?? this.duracaoMin,
      prioridade: prioridade ?? this.prioridade,
      concluido: concluido ?? this.concluido,
    );
  }

  /// Serializa para JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'dia': dia,
        'tema': tema,
        'atividade': atividade,
        'duracao_min': duracaoMin,
        'prioridade': prioridade,
        'concluido': concluido,
      };
}

/// Representa o plano de estudo completo com metadados e itens.
class StudyPlan {
  final String objetivo;
  final String? dataProva;
  final int tempoDiario;
  final List<StudyPlanItem> items;

  StudyPlan({
    required this.objetivo,
    this.dataProva,
    required this.tempoDiario,
    required this.items,
  });
}
