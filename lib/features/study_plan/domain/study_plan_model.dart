/// Status do Plano de Estudos
enum StudyPlanStatus {
  active('ACTIVE'),
  paused('PAUSED'),
  completed('COMPLETED'),
  archived('ARCHIVED');

  const StudyPlanStatus(this.apiValue);
  final String apiValue;

  static StudyPlanStatus fromString(String? value) {
    switch ((value ?? '').trim().toUpperCase()) {
      case 'PAUSED':
        return StudyPlanStatus.paused;
      case 'COMPLETED':
        return StudyPlanStatus.completed;
      case 'ARCHIVED':
        return StudyPlanStatus.archived;
      case 'ACTIVE':
      default:
        return StudyPlanStatus.active;
    }
  }
}

/// Modo de estudo recomendado para uma sessão
enum StudyRecommendedMode {
  quiz('QUIZ'),
  flashcard('FLASHCARDS'),
  reading('READING'),
  auto('AUTO');

  const StudyRecommendedMode(this.apiValue);
  final String apiValue;

  static StudyRecommendedMode fromString(String? value) {
    final clean = (value ?? '').trim().toUpperCase();
    if (clean.contains('QUIZ')) return StudyRecommendedMode.quiz;
    if (clean.contains('FLASH')) return StudyRecommendedMode.flashcard;
    if (clean.contains('LEIT') || clean.contains('READ')) {
      return StudyRecommendedMode.reading;
    }
    return StudyRecommendedMode.auto;
  }
}

/// Status de uma sessão individual do plano
enum StudySessionStatus {
  pending('PENDING'),
  inProgress('IN_PROGRESS'),
  completed('COMPLETED'),
  skipped('SKIPPED');

  const StudySessionStatus(this.apiValue);
  final String apiValue;

  static StudySessionStatus fromString(String? value) {
    switch ((value ?? '').trim().toUpperCase()) {
      case 'IN_PROGRESS':
        return StudySessionStatus.inProgress;
      case 'COMPLETED':
        return StudySessionStatus.completed;
      case 'SKIPPED':
        return StudySessionStatus.skipped;
      case 'PENDING':
      default:
        return StudySessionStatus.pending;
    }
  }
}

/// Progresso de uma sessão em andamento (salvamento mid-way)
class StudySessionProgress {
  const StudySessionProgress({
    required this.sessionId,
    required this.planId,
    required this.selectedMode,
    required this.status,
    required this.currentItem,
    required this.totalItems,
    required this.correctAnswers,
    required this.incorrectAnswers,
    required this.progressPercentage,
    required this.startedAt,
    required this.lastAccessedAt,
    this.completedAt,
  });

  factory StudySessionProgress.fromJson(Map<String, dynamic> json) {
    return StudySessionProgress(
      sessionId: json['session_id']?.toString() ?? json['sessionId']?.toString() ?? '',
      planId: json['plan_id']?.toString() ?? json['planId']?.toString() ?? '',
      selectedMode: json['selected_mode']?.toString() ?? json['selectedMode']?.toString() ?? 'QUIZ',
      status: json['status']?.toString() ?? 'IN_PROGRESS',
      currentItem: (json['current_item'] as num?)?.toInt() ?? (json['currentItem'] as num?)?.toInt() ?? 0,
      totalItems: (json['total_items'] as num?)?.toInt() ?? (json['totalItems'] as num?)?.toInt() ?? 0,
      correctAnswers: (json['correct_answers'] as num?)?.toInt() ?? (json['correctAnswers'] as num?)?.toInt() ?? 0,
      incorrectAnswers: (json['incorrect_answers'] as num?)?.toInt() ?? (json['incorrectAnswers'] as num?)?.toInt() ?? 0,
      progressPercentage: (json['progress_percentage'] as num?)?.toDouble() ?? (json['progress'] as num?)?.toDouble() ?? 0.0,
      startedAt: json['started_at']?.toString() ?? json['startedAt']?.toString() ?? DateTime.now().toIso8601String(),
      lastAccessedAt: json['last_accessed_at']?.toString() ?? json['lastAccessedAt']?.toString() ?? DateTime.now().toIso8601String(),
      completedAt: json['completed_at']?.toString() ?? json['completedAt']?.toString(),
    );
  }

  final String sessionId;
  final String planId;
  final String selectedMode; // QUIZ | FLASHCARDS | READING
  final String status; // IN_PROGRESS | COMPLETED
  final int currentItem;
  final int totalItems;
  final int correctAnswers;
  final int incorrectAnswers;
  final double progressPercentage;
  final String startedAt;
  final String lastAccessedAt;
  final String? completedAt;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'plan_id': planId,
        'selected_mode': selectedMode,
        'status': status,
        'current_item': currentItem,
        'total_items': totalItems,
        'correct_answers': correctAnswers,
        'incorrect_answers': incorrectAnswers,
        'progress_percentage': progressPercentage,
        'started_at': startedAt,
        'last_accessed_at': lastAccessedAt,
        'completed_at': completedAt,
      };

  StudySessionProgress copyWith({
    int? currentItem,
    int? totalItems,
    int? correctAnswers,
    int? incorrectAnswers,
    double? progressPercentage,
    String? status,
    String? completedAt,
    String? lastAccessedAt,
  }) {
    return StudySessionProgress(
      sessionId: sessionId,
      planId: planId,
      selectedMode: selectedMode,
      status: status ?? this.status,
      currentItem: currentItem ?? this.currentItem,
      totalItems: totalItems ?? this.totalItems,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      incorrectAnswers: incorrectAnswers ?? this.incorrectAnswers,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      startedAt: startedAt,
      lastAccessedAt: lastAccessedAt ?? DateTime.now().toIso8601String(),
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// Representa uma sessão / item individual de estudo agendado no plano.
class StudyPlanItem {
  const StudyPlanItem({
    this.id,
    this.sessionId = '',
    this.planId,
    required this.dia,
    this.scheduledDate,
    this.subject = '',
    required this.tema,
    this.subtopics = const [],
    required this.atividade,
    required this.duracaoMin,
    required this.prioridade,
    this.recommendedMode = StudyRecommendedMode.auto,
    this.difficulty = 'intermediario',
    this.status = StudySessionStatus.pending,
    this.concluido = false,
    this.completedAt,
    this.sourceDocumentIds = const [],
    this.sourceSections = const [],
    this.score,
    this.correctAnswers,
    this.incorrectAnswers,
    this.timeSpentMinutes,
  });

  factory StudyPlanItem.fromJson(Map<String, dynamic> json) {
    final rawConcluido = json['concluido'] as bool? ?? false;
    final rawStatus = json['status'] != null
        ? StudySessionStatus.fromString(json['status'].toString())
        : (rawConcluido ? StudySessionStatus.completed : StudySessionStatus.pending);

    final rawTema = json['tema'] as String? ?? json['topic'] as String? ?? '';
    final rawSubject = json['subject'] as String? ?? json['disciplina'] as String? ?? '';
    final rawSubtopics = (json['subtopics'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [];

    final rawDocIds = (json['source_document_ids'] ?? json['sourceDocumentIds']) as List<dynamic>?;
    final docIds = rawDocIds?.map((e) => (e as num).toInt()).toList() ?? const [];

    final rawSections = (json['source_sections'] ?? json['sourceSections']) as List<dynamic>?;
    final sections = rawSections?.map((e) => e.toString()).toList() ?? const [];

    final rawId = (json['id'] as num?)?.toInt();
    final rawSessionId = json['session_id']?.toString() ?? json['sessionId']?.toString() ?? 'session_${rawId ?? rawTema.hashCode}';

    return StudyPlanItem(
      id: rawId,
      sessionId: rawSessionId,
      planId: json['plan_id']?.toString() ?? json['planId']?.toString(),
      dia: json['dia'] as String? ?? json['weekday'] as String? ?? '',
      scheduledDate: json['scheduled_date'] as String? ?? json['scheduledDate'] as String?,
      subject: rawSubject,
      tema: rawTema,
      subtopics: rawSubtopics,
      atividade: json['atividade'] as String? ?? json['activity'] as String? ?? '',
      duracaoMin: (json['duracao_min'] as num?)?.toInt() ?? (json['estimated_minutes'] as num?)?.toInt() ?? 30,
      prioridade: (json['prioridade'] as num?)?.toInt() ?? 2,
      recommendedMode: StudyRecommendedMode.fromString(json['recommended_mode']?.toString() ?? json['recommendedMode']?.toString()),
      difficulty: json['difficulty']?.toString() ?? 'intermediario',
      status: rawStatus,
      concluido: rawStatus == StudySessionStatus.completed || rawConcluido,
      completedAt: json['completed_at'] != null ? DateTime.tryParse(json['completed_at'].toString()) : null,
      sourceDocumentIds: docIds,
      sourceSections: sections,
      score: (json['score'] as num?)?.toDouble(),
      correctAnswers: (json['correct_answers'] as num?)?.toInt(),
      incorrectAnswers: (json['incorrect_answers'] as num?)?.toInt(),
      timeSpentMinutes: (json['time_spent_minutes'] as num?)?.toInt(),
    );
  }

  final int? id;
  final String sessionId;
  final String? planId;
  final String dia;
  final String? scheduledDate; // YYYY-MM-DD
  final String subject; // ex: "Motores de Ciclo Otto"
  final String tema; // ex: "Componentes eletrônicos" ou "Motores: Componentes"
  final List<String> subtopics; // ex: ["Sistema de ignição", "Sensores"]
  final String atividade;
  final int duracaoMin;
  final int prioridade; // 1 = Alta, 2 = Média, 3 = Baixa
  final StudyRecommendedMode recommendedMode;
  final String difficulty;
  final StudySessionStatus status;
  final bool concluido;
  final DateTime? completedAt;
  final List<int> sourceDocumentIds;
  final List<String> sourceSections;
  final double? score;
  final int? correctAnswers;
  final int? incorrectAnswers;
  final int? timeSpentMinutes;

  String get effectiveSessionId =>
      sessionId.isNotEmpty ? sessionId : 'session_${id ?? tema.hashCode}';

  String get effectiveSubject => subject.isNotEmpty
      ? subject
      : (tema.contains(':') ? tema.split(':').first.trim() : tema);

  bool get isCompleted => status == StudySessionStatus.completed || concluido;
  bool get isInProgress => status == StudySessionStatus.inProgress;
  bool get isPending => status == StudySessionStatus.pending;

  StudyPlanItem copyWith({
    int? id,
    String? sessionId,
    String? planId,
    String? dia,
    String? scheduledDate,
    String? subject,
    String? tema,
    List<String>? subtopics,
    String? atividade,
    int? duracaoMin,
    int? prioridade,
    StudyRecommendedMode? recommendedMode,
    String? difficulty,
    StudySessionStatus? status,
    bool? concluido,
    DateTime? completedAt,
    List<int>? sourceDocumentIds,
    List<String>? sourceSections,
    double? score,
    int? correctAnswers,
    int? incorrectAnswers,
    int? timeSpentMinutes,
  }) {
    final newStatus = status ?? this.status;
    final isDone = concluido ?? (newStatus == StudySessionStatus.completed);
    return StudyPlanItem(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      planId: planId ?? this.planId,
      dia: dia ?? this.dia,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      subject: subject ?? this.subject,
      tema: tema ?? this.tema,
      subtopics: subtopics ?? this.subtopics,
      atividade: atividade ?? this.atividade,
      duracaoMin: duracaoMin ?? this.duracaoMin,
      prioridade: prioridade ?? this.prioridade,
      recommendedMode: recommendedMode ?? this.recommendedMode,
      difficulty: difficulty ?? this.difficulty,
      status: newStatus,
      concluido: isDone,
      completedAt: completedAt ?? this.completedAt,
      sourceDocumentIds: sourceDocumentIds ?? this.sourceDocumentIds,
      sourceSections: sourceSections ?? this.sourceSections,
      score: score ?? this.score,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      incorrectAnswers: incorrectAnswers ?? this.incorrectAnswers,
      timeSpentMinutes: timeSpentMinutes ?? this.timeSpentMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'session_id': effectiveSessionId,
        'plan_id': planId,
        'dia': dia,
        'scheduled_date': scheduledDate,
        'subject': effectiveSubject,
        'tema': tema,
        'subtopics': subtopics,
        'atividade': atividade,
        'duracao_min': duracaoMin,
        'prioridade': prioridade,
        'recommended_mode': recommendedMode.apiValue,
        'difficulty': difficulty,
        'status': status.apiValue,
        'concluido': isCompleted,
        'completed_at': completedAt?.toIso8601String(),
        'source_document_ids': sourceDocumentIds,
        'source_sections': sourceSections,
        'score': score,
        'correct_answers': correctAnswers,
        'incorrect_answers': incorrectAnswers,
        'time_spent_minutes': timeSpentMinutes,
      };
}

/// Representa um Plano de Estudos completo.
class StudyPlan {
  StudyPlan({
    String? id,
    this.userId,
    String? title,
    required this.objetivo,
    this.dataProva,
    required this.tempoDiario,
    String? startDate,
    this.targetDate,
    StudyPlanStatus? status,
    String? timezone,
    List<int>? sourceDocumentIds,
    required this.items,
    this.activeSessionProgress,
  })  : id = id ?? 'plan_${objetivo.hashCode}_${DateTime.now().millisecondsSinceEpoch}',
        title = title ?? objetivo,
        startDate = startDate ?? DateTime.now().toIso8601String().substring(0, 10),
        status = status ?? StudyPlanStatus.active,
        timezone = timezone ?? 'America/Sao_Paulo',
        sourceDocumentIds = sourceDocumentIds ?? const [];

  factory StudyPlan.fromJson(Map<String, dynamic> json) {
    final itemsRaw = (json['items'] as List<dynamic>?) ?? const [];
    final itemsList = itemsRaw
        .whereType<Map<String, dynamic>>()
        .map(StudyPlanItem.fromJson)
        .toList();

    final rawDocIds = (json['source_document_ids'] ?? json['sourceDocumentIds']) as List<dynamic>?;
    final docIds = rawDocIds?.map((e) => (e as num).toInt()).toList() ?? const [];

    StudySessionProgress? progress;
    final rawProgress = json['active_session_progress'] ?? json['activeSessionProgress'];
    if (rawProgress is Map<String, dynamic>) {
      progress = StudySessionProgress.fromJson(rawProgress);
    }

    return StudyPlan(
      id: json['id']?.toString(),
      userId: json['user_id']?.toString() ?? json['userId']?.toString(),
      title: json['title']?.toString() ?? json['position']?.toString() ?? json['objetivo'] as String? ?? 'Plano de Estudos',
      objetivo: json['objetivo'] as String? ?? json['title']?.toString() ?? 'Plano de Estudos',
      dataProva: json['data_prova'] as String? ?? json['dataProva'] as String? ?? json['targetDate'] as String?,
      tempoDiario: ((json['tempo_diario'] ?? json['tempoDiario']) as num?)?.toInt() ?? 30,
      startDate: json['start_date'] as String? ?? json['startDate'] as String?,
      targetDate: json['target_date'] as String? ?? json['targetDate'] as String?,
      status: StudyPlanStatus.fromString(json['status']?.toString()),
      timezone: json['timezone']?.toString() ?? 'America/Sao_Paulo',
      sourceDocumentIds: docIds,
      items: itemsList,
      activeSessionProgress: progress,
    );
  }

  final String id;
  final String? userId;
  final String title;
  final String objetivo;
  final String? dataProva;
  final int tempoDiario;
  final String startDate;
  final String? targetDate;
  final StudyPlanStatus status;
  final String timezone;
  final List<int> sourceDocumentIds;
  final List<StudyPlanItem> items;
  final StudySessionProgress? activeSessionProgress;

  bool get isActive => status == StudyPlanStatus.active;

  /// Retorna as sessões programadas para uma determinada data (padrão YYYY-MM-DD local).
  List<StudyPlanItem> getSessionsForDate(DateTime localDate) {
    final dateStr = localDate.toIso8601String().substring(0, 10);
    final weekdayName = _weekdayName(localDate.weekday);

    // 1. Sessões com data estrita agendada para dateStr
    final exactDateSessions = items.where((i) => i.scheduledDate == dateStr).toList();
    if (exactDateSessions.isNotEmpty) {
      return exactDateSessions;
    }

    // 2. Sessões correspondentes ao dia da semana recorrente
    final recurrentSessions = items.where((i) {
      final itemDia = i.dia.trim().toLowerCase();
      return itemDia == weekdayName || itemDia.startsWith(weekdayName.substring(0, 3));
    }).toList();

    return recurrentSessions;
  }

  /// Retorna sessões pendentes atrasadas (de datas anteriores).
  List<StudyPlanItem> getOverduePendingSessions(DateTime localDate) {
    final dateStr = localDate.toIso8601String().substring(0, 10);
    return items.where((i) {
      if (i.isCompleted) return false;
      if (i.scheduledDate != null && i.scheduledDate!.compareTo(dateStr) < 0) {
        return true;
      }
      return false;
    }).toList();
  }

  /// Progresso total (0.0 a 1.0)
  double get totalProgress {
    if (items.isEmpty) return 0.0;
    final completedCount = items.where((i) => i.isCompleted).length;
    return completedCount / items.length;
  }

  /// Minutos totais já concluídos
  int get completedMinutes {
    return items
        .where((i) => i.isCompleted)
        .fold(0, (sum, i) => sum + i.duracaoMin);
  }

  /// Minutos pendentes para o dia atual
  int getTodayRemainingMinutes(DateTime localDate) {
    final todaySessions = getSessionsForDate(localDate);
    return todaySessions
        .where((i) => !i.isCompleted)
        .fold(0, (sum, i) => sum + i.duracaoMin);
  }

  StudyPlan copyWith({
    String? id,
    String? userId,
    String? title,
    String? objetivo,
    String? dataProva,
    int? tempoDiario,
    String? startDate,
    String? targetDate,
    StudyPlanStatus? status,
    String? timezone,
    List<int>? sourceDocumentIds,
    List<StudyPlanItem>? items,
    StudySessionProgress? activeSessionProgress,
    bool clearActiveSessionProgress = false,
  }) {
    return StudyPlan(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      objetivo: objetivo ?? this.objetivo,
      dataProva: dataProva ?? this.dataProva,
      tempoDiario: tempoDiario ?? this.tempoDiario,
      startDate: startDate ?? this.startDate,
      targetDate: targetDate ?? this.targetDate,
      status: status ?? this.status,
      timezone: timezone ?? this.timezone,
      sourceDocumentIds: sourceDocumentIds ?? this.sourceDocumentIds,
      items: items ?? this.items,
      activeSessionProgress: clearActiveSessionProgress
          ? null
          : (activeSessionProgress ?? this.activeSessionProgress),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'objetivo': objetivo,
        'data_prova': dataProva,
        'tempo_diario': tempoDiario,
        'start_date': startDate,
        'target_date': targetDate,
        'status': status.apiValue,
        'timezone': timezone,
        'source_document_ids': sourceDocumentIds,
        'items': items.map((i) => i.toJson()).toList(),
        if (activeSessionProgress != null)
          'active_session_progress': activeSessionProgress!.toJson(),
      };

  static String _weekdayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'segunda';
      case DateTime.tuesday:
        return 'terça';
      case DateTime.wednesday:
        return 'quarta';
      case DateTime.thursday:
        return 'quinta';
      case DateTime.friday:
        return 'sexta';
      case DateTime.saturday:
        return 'sábado';
      case DateTime.sunday:
      default:
        return 'domingo';
    }
  }
}
