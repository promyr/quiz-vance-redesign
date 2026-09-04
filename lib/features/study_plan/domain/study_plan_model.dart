/// Represents one scheduled study-plan activity.
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

  factory StudyPlanItem.fromJson(Map<String, dynamic> json) => StudyPlanItem(
        id: (json['id'] as num?)?.toInt(),
        dia: json['dia'] as String? ?? '',
        tema: json['tema'] as String? ?? '',
        atividade: json['atividade'] as String? ?? '',
        duracaoMin: (json['duracao_min'] as num?)?.toInt() ?? 30,
        prioridade: (json['prioridade'] as num?)?.toInt() ?? 2,
        concluido: json['concluido'] as bool? ?? false,
      );

  final int? id;
  final String dia;
  final String tema;
  final String atividade;
  final int duracaoMin;
  final int prioridade;
  final bool concluido;

  StudyPlanItem copyWith({
    int? id,
    String? dia,
    String? tema,
    String? atividade,
    int? duracaoMin,
    int? prioridade,
    bool? concluido,
  }) =>
      StudyPlanItem(
        id: id ?? this.id,
        dia: dia ?? this.dia,
        tema: tema ?? this.tema,
        atividade: atividade ?? this.atividade,
        duracaoMin: duracaoMin ?? this.duracaoMin,
        prioridade: prioridade ?? this.prioridade,
        concluido: concluido ?? this.concluido,
      );

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

/// Represents a complete study plan and its metadata.
class StudyPlan {
  StudyPlan({
    required this.objetivo,
    this.dataProva,
    required this.tempoDiario,
    required this.items,
  });

  final String objetivo;
  final String? dataProva;
  final int tempoDiario;
  final List<StudyPlanItem> items;
}
