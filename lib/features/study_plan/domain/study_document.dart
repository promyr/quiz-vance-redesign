import 'study_plan_notice_analysis.dart';

enum StudyDocumentPurpose {
  studyPlan('study_plan'),
  library('library');

  const StudyDocumentPurpose(this.apiValue);
  final String apiValue;
}

enum StudyDocumentStatus {
  uploading,
  extracting,
  mapping,
  awaitingSelection,
  analyzing,
  consolidating,
  ready,
  needsReview,
  failed,
  deleted,
  unknown;

  static StudyDocumentStatus fromApi(String? value) {
    return switch ((value ?? '').trim().toLowerCase()) {
      'uploading' => uploading,
      'extracting' => extracting,
      'mapping' => mapping,
      'awaiting_selection' => awaitingSelection,
      'analyzing' => analyzing,
      'consolidating' => consolidating,
      'ready' => ready,
      'needs_review' => needsReview,
      'failed' => failed,
      'deleted' => deleted,
      _ => unknown,
    };
  }

  bool get isProcessing => switch (this) {
        uploading ||
        extracting ||
        mapping ||
        analyzing ||
        consolidating =>
          true,
        _ => false,
      };
}

class StudyDocumentCargo {
  const StudyDocumentCargo({
    required this.id,
    required this.title,
    required this.pageNumber,
  });

  factory StudyDocumentCargo.fromJson(Map<String, dynamic> json) {
    return StudyDocumentCargo(
      id: (json['id'] ?? json['cargo_id'] ?? '').toString().trim(),
      title: (json['title'] ?? json['titulo'] ?? '').toString().trim(),
      pageNumber: (json['page_number'] as num?)?.toInt(),
    );
  }

  final String id;
  final String title;
  final int? pageNumber;
}

class StudyDocumentEvidence {
  const StudyDocumentEvidence({
    required this.page,
    required this.snippet,
  });

  factory StudyDocumentEvidence.fromJson(Map<String, dynamic> json) {
    return StudyDocumentEvidence(
      page: (json['pagina'] as num?)?.toInt() ?? 0,
      snippet: (json['trecho'] ?? '').toString().trim(),
    );
  }

  final int page;
  final String snippet;
}

class StudyDocumentSubject {
  const StudyDocumentSubject({
    required this.name,
    required this.topics,
    required this.evidences,
  });

  factory StudyDocumentSubject.fromJson(Map<String, dynamic> json) {
    return StudyDocumentSubject(
      name: (json['nome'] ?? '').toString().trim(),
      topics: (json['topicos'] as List<dynamic>? ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      evidences: (json['evidencias'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StudyDocumentEvidence.fromJson)
          .where((item) => item.page > 0 && item.snippet.isNotEmpty)
          .toList(growable: false),
    );
  }

  final String name;
  final List<String> topics;
  final List<StudyDocumentEvidence> evidences;

  List<int> get evidencePages =>
      evidences.map((item) => item.page).toSet().toList(growable: false)
        ..sort();
}

class StudyDocumentAnalysis {
  const StudyDocumentAnalysis({
    required this.cargoId,
    required this.cargoTitle,
    required this.examDate,
    required this.subjects,
  });

  factory StudyDocumentAnalysis.fromJson(Map<String, dynamic> json) {
    return StudyDocumentAnalysis(
      cargoId: (json['cargo_id'] ?? '').toString().trim(),
      cargoTitle: (json['cargo'] ?? '').toString().trim(),
      examDate: (json['data_prova'] as String?)?.trim(),
      subjects: (json['disciplinas'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StudyDocumentSubject.fromJson)
          .where((item) => item.name.isNotEmpty && item.topics.isNotEmpty)
          .toList(growable: false),
    );
  }

  final String cargoId;
  final String cargoTitle;
  final String? examDate;
  final List<StudyDocumentSubject> subjects;

  StudyPlanNoticeAnalysis toNoticeAnalysis() {
    return StudyPlanNoticeAnalysis.fromJson({
      'cargo_encontrado': cargoTitle,
      'cronograma_edital': {
        'data_prova': examDate,
        'data_prova_definida': examDate != null && examDate!.isNotEmpty,
      },
      'disciplinas': [
        for (final subject in subjects)
          {
            'nome': subject.name,
            'topicos': subject.topics,
            'evidencia': subject.evidences
                .map((item) => 'p. ${item.page}: ${item.snippet}')
                .join(' | '),
          },
      ],
    });
  }
}

class StudyDocument {
  const StudyDocument({
    required this.id,
    required this.purpose,
    required this.fileName,
    required this.sizeBytes,
    required this.status,
    required this.progress,
    required this.cargos,
    this.pageCount,
    this.examDate,
    this.selectedCargoId,
    this.selectedCargoTitle,
    this.analysis,
    this.errorCode,
    this.errorMessage,
    this.canRetry = false,
  });

  factory StudyDocument.fromJson(Map<String, dynamic> json) {
    final rawPurpose = (json['purpose'] ?? '').toString();
    final rawAnalysis = json['analysis_result'];
    final rawError = json['error'];
    return StudyDocument(
      id: (json['id'] as num?)?.toInt() ?? 0,
      purpose: rawPurpose == StudyDocumentPurpose.library.apiValue
          ? StudyDocumentPurpose.library
          : StudyDocumentPurpose.studyPlan,
      fileName: (json['file_name'] ?? '').toString().trim(),
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      status: StudyDocumentStatus.fromApi(json['status'] as String?),
      progress: ((json['progress'] as num?)?.toInt() ?? 0).clamp(0, 100),
      pageCount: (json['page_count'] as num?)?.toInt(),
      cargos: (json['cargos'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StudyDocumentCargo.fromJson)
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList(growable: false),
      examDate: (json['exam_date'] as String?)?.trim(),
      selectedCargoId: (json['selected_cargo_id'] as String?)?.trim(),
      selectedCargoTitle: (json['selected_cargo_title'] as String?)?.trim(),
      analysis: rawAnalysis is Map<String, dynamic>
          ? StudyDocumentAnalysis.fromJson(rawAnalysis)
          : null,
      errorCode:
          rawError is Map<String, dynamic> ? rawError['code'] as String? : null,
      errorMessage: rawError is Map<String, dynamic>
          ? rawError['message'] as String?
          : null,
      canRetry: json['can_retry'] == true,
    );
  }

  final int id;
  final StudyDocumentPurpose purpose;
  final String fileName;
  final int sizeBytes;
  final StudyDocumentStatus status;
  final int progress;
  final int? pageCount;
  final List<StudyDocumentCargo> cargos;
  final String? examDate;
  final String? selectedCargoId;
  final String? selectedCargoTitle;
  final StudyDocumentAnalysis? analysis;
  final String? errorCode;
  final String? errorMessage;
  final bool canRetry;
}
