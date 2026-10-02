class ConcursoInfo {
  const ConcursoInfo({
    required this.orgao,
    required this.banca,
    required this.statusEdital,
    required this.modalidade,
  });

  factory ConcursoInfo.fromJson(Map<String, dynamic> json) {
    return ConcursoInfo(
      orgao: (json['orgao'] as String? ?? '').trim(),
      banca: (json['banca'] as String? ?? '').trim(),
      statusEdital: (json['status_edital'] as String? ?? 'PUBLICADO').trim(),
      modalidade: (json['modalidade'] as String? ?? '').trim(),
    );
  }

  final String orgao;
  final String banca;
  final String statusEdital;
  final String modalidade;

  bool get isSuspenso =>
      statusEdital.toUpperCase().contains('SUSPEN') ||
      statusEdital.toUpperCase().contains('ANULAD');
}

class CronogramaEdital {
  const CronogramaEdital({
    required this.dataPublicacao,
    required this.inscricoesInicio,
    required this.inscricoesFim,
    required this.pagamentoLimite,
    required this.dataProva,
    required this.dataProvaDefinida,
  });

  factory CronogramaEdital.fromJson(Map<String, dynamic> json) {
    return CronogramaEdital(
      dataPublicacao: (json['data_publicacao'] as String? ?? '').trim(),
      inscricoesInicio: (json['inscricoes_inicio'] as String? ?? '').trim(),
      inscricoesFim: (json['inscricoes_fim'] as String? ?? '').trim(),
      pagamentoLimite: (json['pagamento_limite'] as String? ?? '').trim(),
      dataProva: (json['data_prova'] as String? ?? '').trim(),
      dataProvaDefinida: (json['data_prova_definida'] as bool? ?? false),
    );
  }

  final String dataPublicacao;
  final String inscricoesInicio;
  final String inscricoesFim;
  final String pagamentoLimite;
  final String dataProva;
  final bool dataProvaDefinida;
}

class CargoNoticeItem {
  const CargoNoticeItem({
    required this.cargoId,
    required this.titulo,
    required this.escolaridade,
    required this.vagas,
  });

  factory CargoNoticeItem.fromJson(Map<String, dynamic> json) {
    return CargoNoticeItem(
      cargoId: (json['cargo_id'] as String? ?? '').trim(),
      titulo: (json['titulo'] as String? ?? '').trim(),
      escolaridade: (json['escolaridade'] as String? ?? '').trim(),
      vagas: json['vagas'] is int ? json['vagas'] as int : null,
    );
  }

  final String cargoId;
  final String titulo;
  final String escolaridade;
  final int? vagas;
}

class StudyPlanNoticeSubject {
  const StudyPlanNoticeSubject({
    required this.name,
    required this.topics,
    required this.evidence,
    required this.peso,
    required this.numQuestoes,
  });

  factory StudyPlanNoticeSubject.fromJson(Map<String, dynamic> json) {
    final name = (json['nome'] as String? ?? '').trim();
    final topics = (json['topicos'] as List<dynamic>? ?? const [])
        .map((topic) => topic.toString().trim())
        .where((topic) => topic.isNotEmpty)
        .toList(growable: false);
    return StudyPlanNoticeSubject(
      name: name,
      topics: topics,
      evidence: (json['evidencia'] as String? ?? '').trim(),
      peso: json['peso'] is int ? json['peso'] as int : null,
      numQuestoes:
          json['num_questoes'] is int ? json['num_questoes'] as int : null,
    );
  }

  final String name;
  final List<String> topics;
  final String evidence;
  final int? peso;
  final int? numQuestoes;
}

class StudyPlanNoticeAnalysis {
  const StudyPlanNoticeAnalysis({
    required this.jobTitle,
    required this.subjects,
    required this.concursoInfo,
    required this.cronograma,
    required this.cargosPopup,
  });

  factory StudyPlanNoticeAnalysis.fromJson(Map<String, dynamic> json) {
    final rawSubjects = json['disciplinas'] as List<dynamic>? ?? const [];
    final subjects = rawSubjects
        .whereType<Map<String, dynamic>>()
        .map(StudyPlanNoticeSubject.fromJson)
        .where(
            (subject) => subject.name.isNotEmpty && subject.topics.isNotEmpty)
        .toList(growable: false);

    ConcursoInfo? concursoInfo;
    final rawInfo = json['concurso_info'];
    if (rawInfo is Map<String, dynamic>) {
      concursoInfo = ConcursoInfo.fromJson(rawInfo);
    }

    CronogramaEdital? cronograma;
    final rawCrono = json['cronograma_edital'];
    if (rawCrono is Map<String, dynamic>) {
      cronograma = CronogramaEdital.fromJson(rawCrono);
    }

    final rawCargos = json['cargos_popup'] as List<dynamic>? ?? const [];
    final cargosPopup = rawCargos
        .whereType<Map<String, dynamic>>()
        .map(CargoNoticeItem.fromJson)
        .where((c) => c.titulo.isNotEmpty)
        .toList(growable: false);

    return StudyPlanNoticeAnalysis(
      jobTitle: (json['cargo_encontrado'] as String? ?? '').trim(),
      subjects: subjects,
      concursoInfo: concursoInfo,
      cronograma: cronograma,
      cargosPopup: cargosPopup,
    );
  }

  final String jobTitle;
  final List<StudyPlanNoticeSubject> subjects;
  final ConcursoInfo? concursoInfo;
  final CronogramaEdital? cronograma;
  final List<CargoNoticeItem> cargosPopup;

  /// true se a data da prova ainda não foi definida no edital
  bool get precisaDataManual =>
      cronograma == null ||
      !cronograma!.dataProvaDefinida ||
      cronograma!.dataProva.isEmpty;

  List<String> get planTopics => [
        for (final subject in subjects)
          for (final topic in subject.topics) '${subject.name}: $topic',
      ];
}
