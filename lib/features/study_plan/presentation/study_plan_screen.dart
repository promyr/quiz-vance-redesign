import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_error_message.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../../library/application/study_document_picker.dart';
import '../../library/application/study_document_upload_source.dart';
import '../application/study_plan_coordinator.dart';
import '../application/study_plan_quiz_request.dart';
import '../data/study_plan_repository.dart';
import '../domain/study_plan_model.dart';
import '../domain/study_plan_notice_analysis.dart';
import '../domain/study_document.dart';

part 'study_plan_widgets.dart';

enum _PlanPhase { config, review, viewing }

String formatStudyPlanDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');
  return '$day/$month/$year';
}

DateTime? parseStudyPlanDateOrNull(String raw) {
  final trimmed = raw.trim();
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(trimmed);
  if (match == null) return null;

  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) return null;

  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }

  return parsed;
}

class StudyPlanScreen extends ConsumerStatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  ConsumerState<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends ConsumerState<StudyPlanScreen> {
  late _PlanPhase _phase;
  StudyPlan? _plan;

  final _objectiveCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();

  StudyPlanNoticeAnalysis? _noticeAnalysis;
  Set<int> _selectedSubjectIndexes = {};
  StudyDocument? _noticeDocument;
  List<StudyDocument> _noticeDocuments = const [];
  Timer? _noticePollTimer;
  int _uploadProgress = 0;
  int _tempo = 30;
  bool _loading = false;
  bool _extractingNotice = false;
  bool _analyzingNotice = false;
  bool _retryingNotice = false;

  @override
  void initState() {
    super.initState();
    _phase = _PlanPhase.config;
    _loadActivePlan();
    _resumeNoticeDocuments();
  }

  // ── helpers ──────────────────────────────────────────────────────

  /// Exibe o bottom sheet de seleção de cargo e retorna o cargo escolhido.
  Future<CargoNoticeItem?> _showCargoSelectionSheet(
    List<CargoNoticeItem> cargos,
  ) async {
    if (cargos.isEmpty) return null;
    if (cargos.length == 1) return cargos.first;
    return showModalBottomSheet<CargoNoticeItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CargoSelectionSheet(cargos: cargos),
    );
  }

  Future<void> _loadActivePlan() async {
    try {
      final plan = await ref.read(activePlanProvider.future);
      if (plan != null && mounted) {
        setState(() {
          _plan = plan;
          _phase = _PlanPhase.viewing;
        });
      }
    } catch (_) {
      // Continua em config se houver erro
    }
  }

  @override
  void dispose() {
    _noticePollTimer?.cancel();
    _objectiveCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _generatePlan() async {
    if (_objectiveCtrl.text.trim().isEmpty) {
      _showError('Informe seu objetivo de estudo');
      return;
    }
    if (_selectedNoticeTopics().isEmpty) {
      _showError('Selecione pelo menos uma disciplina do edital.');
      return;
    }

    setState(() => _loading = true);

    try {
      final plan = await ref.read(studyPlanCoordinatorProvider).generatePlan(
            objective: _objectiveCtrl.text,
            examDate: _dateCtrl.text,
            tempoDiario: _tempo,
            rawTopics: '',
            reviewedTopics: _selectedNoticeTopics(),
            sourceDocumentIds:
                _noticeDocument != null ? [_noticeDocument!.id] : const [],
          );

      if (mounted) {
        setState(() {
          _plan = plan;
          _phase = _PlanPhase.viewing;
          _loading = false;
        });
        ref.invalidate(activePlanProvider);
      }
    } catch (e) {
      if (mounted) {
        _showError(
          userVisibleErrorMessage(
            e,
            fallback:
                'Não foi possível gerar o plano de estudos. Tente novamente.',
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  List<String> _selectedNoticeTopics() {
    final analysis = _noticeAnalysis;
    if (analysis == null) return const [];
    return [
      for (final entry in analysis.subjects.asMap().entries)
        if (_selectedSubjectIndexes.contains(entry.key))
          if (entry.value.topics.isEmpty)
            entry.value.name
          else
            for (final topic in entry.value.topics)
              '${entry.value.name}: $topic',
    ];
  }

  Future<void> _pickNoticePdf() async {
    setState(() => _extractingNotice = true);
    PickedStudyDocument? pickedDocument;
    try {
      pickedDocument = await pickStudyDocumentPdf();
      if (pickedDocument == null) return;
      final source = pickedDocument.source;
      final uploaded =
          await ref.read(studyPlanRepositoryProvider).uploadDocument(
                purpose: StudyDocumentPurpose.studyPlan,
                fileName: source.fileName,
                length: source.length,
                openRead: source.openRead,
                onProgress: (sent, total) {
                  if (!mounted || total <= 0) return;
                  setState(() {
                    _uploadProgress =
                        (sent * 100 / total).round().clamp(0, 100);
                  });
                },
              );
      if (!mounted) return;
      setState(() {
        _noticeDocument = uploaded;
        _noticeAnalysis = null;
        _selectedSubjectIndexes = {};
        _noticeDocuments = [
          uploaded,
          ..._noticeDocuments.where((item) => item.id != uploaded.id),
        ];
        _uploadProgress = 100;
      });
      _startNoticePolling(uploaded.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${pickedDocument.displayName}" enviado. A extracao continuara em segundo plano.',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
    } on StudyDocumentUploadException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError(
        userVisibleErrorMessage(
          error,
          fallback: 'Nao foi possivel enviar o edital em PDF.',
        ),
      );
    } finally {
      await pickedDocument?.dispose();
      if (mounted) {
        setState(() {
          _extractingNotice = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _activateNoticeDocument(StudyDocument document) async {
    if (!mounted) return;
    _noticePollTimer?.cancel();
    setState(() => _noticeDocument = document);
    if (document.status == StudyDocumentStatus.awaitingSelection) {
      await _promptCargoSelection(document);
      return;
    }
    if (document.status == StudyDocumentStatus.ready) {
      try {
        // The list endpoint returns summaries without analysis_result.
        final detail = document.analysis == null
            ? await ref
                .read(studyPlanRepositoryProvider)
                .getDocument(document.id)
            : document;
        if (!mounted || _noticeDocument?.id != document.id) return;
        _applyReadyDocument(detail);
      } catch (error) {
        if (!mounted || _noticeDocument?.id != document.id) return;
        _showError(userVisibleErrorMessage(
          error,
          fallback:
              'Não foi possível recuperar a análise do edital. Tente novamente.',
        ));
      }
      return;
    }
    if (document.status == StudyDocumentStatus.needsReview) {
      await _reviewNoticeDocument(document);
      return;
    }
    if (document.status == StudyDocumentStatus.failed) {
      if (!document.canRetry) {
        _showError(
          document.errorMessage ?? 'O processamento precisa de revisao.',
        );
      }
      return;
    }
    _startNoticePolling(document.id);
  }

  Future<void> _resumeNoticeDocuments() async {
    try {
      final documents =
          await ref.read(studyPlanRepositoryProvider).listDocuments(
                purpose: StudyDocumentPurpose.studyPlan,
              );
      if (!mounted) return;
      setState(() {
        _noticeDocuments = documents;
        _noticeDocument = documents.isEmpty ? null : documents.first;
      });
      final current = _noticeDocument;
      if (current != null && current.status.isProcessing) {
        _startNoticePolling(current.id);
      }
    } catch (_) {
      // Uma falha de rede nao bloqueia o envio de um novo edital.
    }
  }

  void _startNoticePolling(int documentId) {
    _noticePollTimer?.cancel();
    _noticePollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshNoticeDocument(documentId)),
    );
    unawaited(_refreshNoticeDocument(documentId));
  }

  Future<void> _refreshNoticeDocument(int documentId) async {
    try {
      final document =
          await ref.read(studyPlanRepositoryProvider).getDocument(documentId);
      if (!mounted) return;
      setState(() {
        _noticeDocument = document;
        _noticeDocuments = [
          document,
          ..._noticeDocuments.where((item) => item.id != document.id),
        ];
      });
      if (document.status == StudyDocumentStatus.awaitingSelection) {
        _noticePollTimer?.cancel();
        await _promptCargoSelection(document);
      } else if (document.status == StudyDocumentStatus.ready) {
        _noticePollTimer?.cancel();
        _applyReadyDocument(document);
      } else if (document.status == StudyDocumentStatus.needsReview ||
          document.status == StudyDocumentStatus.failed) {
        _noticePollTimer?.cancel();
        _showError(document.errorMessage ?? 'Falha ao processar o edital.');
      }
    } catch (_) {
      // O job permanece no servidor e sera consultado novamente.
    }
  }

  Future<void> _promptCargoSelection(StudyDocument document) async {
    if (_analyzingNotice) return;
    final cargos = [
      for (final cargo in document.cargos)
        CargoNoticeItem(
          cargoId: cargo.id,
          titulo: cargo.title,
          escolaridade: '',
          vagas: null,
        ),
    ];
    if (cargos.isEmpty) {
      _showError('Nenhum cargo foi confirmado neste edital.');
      return;
    }
    setState(() => _analyzingNotice = true);
    try {
      final picked = await _showCargoSelectionSheet(cargos);
      if (!mounted || picked == null) return;
      _objectiveCtrl.text = picked.titulo;
      final queued =
          await ref.read(studyPlanRepositoryProvider).selectDocumentCargo(
                documentId: document.id,
                cargoId: picked.cargoId,
              );
      if (!mounted) return;
      setState(() => _noticeDocument = queued);
      _startNoticePolling(document.id);
    } catch (error) {
      _showError(
        userVisibleErrorMessage(
          error,
          fallback: 'Nao foi possivel iniciar a analise do cargo.',
        ),
      );
    } finally {
      if (mounted) setState(() => _analyzingNotice = false);
    }
  }

  void _applyReadyDocument(StudyDocument document) {
    final remoteAnalysis = document.analysis;
    if (remoteAnalysis == null || remoteAnalysis.subjects.isEmpty) {
      _showError('O edital terminou sem disciplinas confirmadas.');
      return;
    }
    final analysis = remoteAnalysis.toNoticeAnalysis();
    _objectiveCtrl.text = remoteAnalysis.cargoTitle;
    final examDate = remoteAnalysis.examDate;
    if (examDate != null && examDate.isNotEmpty) {
      final parts = examDate.split('-');
      if (parts.length == 3) {
        _dateCtrl.text = '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    }
    setState(() {
      _noticeDocument = document;
      _noticeAnalysis = analysis;
      _selectedSubjectIndexes = Set<int>.from(
        List<int>.generate(analysis.subjects.length, (index) => index),
      );
      _phase = _PlanPhase.review;
    });
  }

  Future<void> _deleteNoticeDocument(StudyDocument document) async {
    try {
      await ref.read(studyPlanRepositoryProvider).deleteDocument(document.id);
      if (!mounted) return;
      setState(() {
        _noticeDocuments =
            _noticeDocuments.where((item) => item.id != document.id).toList();
        if (_noticeDocument?.id == document.id) {
          _noticeDocument =
              _noticeDocuments.isEmpty ? null : _noticeDocuments.first;
        }
      });
    } catch (error) {
      _showError(
        userVisibleErrorMessage(
          error,
          fallback: 'Nao foi possivel excluir o edital.',
        ),
      );
    }
  }

  Future<void> _reviewNoticeDocument(StudyDocument document) async {
    if (_analyzingNotice) return;
    setState(() => _analyzingNotice = true);
    try {
      final detail =
          await ref.read(studyPlanRepositoryProvider).getDocument(document.id);
      if (!mounted) return;
      if (detail.cargos.isNotEmpty) {
        setState(() => _analyzingNotice = false);
        await _promptCargoSelection(detail);
        return;
      }
      final controller = TextEditingController();
      final title = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Revisar edital'),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text(
                          'Não foi possível identificar o cargo automaticamente. Informe o nome exato do cargo para analisar o texto extraído. O PDF precisa conter o conteúdo programático; um quadro de vagas isolado pode não conter as disciplinas.'),
                      const SizedBox(height: 16),
                      TextField(
                          controller: controller,
                          maxLength: 200,
                          decoration: const InputDecoration(
                              labelText: 'Cargo desejado')),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar')),
                  TextButton(
                      onPressed: () {
                        final value = controller.text.trim();
                        if (value.isNotEmpty) Navigator.pop(ctx, value);
                      },
                      child: const Text('Continuar análise')),
                ],
              ));
      // Wait for the dialog's closing animation before disposing its controller.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      controller.dispose();
      if (!mounted || title == null) return;
      final queued = await ref
          .read(studyPlanRepositoryProvider)
          .selectDocumentCargo(
              documentId: detail.id, cargoId: 'manual', cargoTitle: title);
      if (!mounted) return;
      _objectiveCtrl.text = title;
      setState(() => _noticeDocument = queued);
      _startNoticePolling(queued.id);
    } catch (error) {
      if (mounted) {
        _showError(userVisibleErrorMessage(error,
            fallback: 'Não foi possível continuar a revisão do edital.'));
      }
    } finally {
      if (mounted) setState(() => _analyzingNotice = false);
    }
  }

  Future<void> _retryNoticeDocument(StudyDocument document) async {
    if (_retryingNotice) return;
    setState(() => _retryingNotice = true);
    try {
      final queued = await ref
          .read(studyPlanRepositoryProvider)
          .retryDocumentAnalysis(document.id);
      if (!mounted) return;
      setState(() {
        _noticeDocument = queued;
        _noticeDocuments = [
          queued,
          ..._noticeDocuments.where((item) => item.id != queued.id),
        ];
      });
      _startNoticePolling(queued.id);
    } catch (error) {
      _showError(
        userVisibleErrorMessage(
          error,
          fallback: 'Nao foi possivel retomar a analise do edital.',
        ),
      );
    } finally {
      if (mounted) setState(() => _retryingNotice = false);
    }
  }

  String _documentStatusLabel(StudyDocument document) {
    return switch (document.status) {
      StudyDocumentStatus.uploading => 'Enviando',
      StudyDocumentStatus.extracting => 'Extraindo paginas e OCR',
      StudyDocumentStatus.mapping => 'Mapeando cargos e datas',
      StudyDocumentStatus.awaitingSelection => 'Selecione o cargo',
      StudyDocumentStatus.analyzing => 'Analisando conteudo do cargo',
      StudyDocumentStatus.consolidating => 'Consolidando disciplinas',
      StudyDocumentStatus.ready => 'Pronto',
      StudyDocumentStatus.needsReview => 'Precisa de revisao',
      StudyDocumentStatus.failed => 'Falhou',
      StudyDocumentStatus.deleted => 'Excluido',
      StudyDocumentStatus.unknown => 'Aguardando',
    };
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  Future<void> _toggleItem(StudyPlanItem item) async {
    if (_plan == null) return;
    try {
      final targetIndex = _plan!.items.indexWhere(
        (i) => i.effectiveSessionId == item.effectiveSessionId,
      );
      if (targetIndex < 0) return;

      final updatedPlan =
          await ref.read(studyPlanCoordinatorProvider).toggleItem(
                plan: _plan!,
                index: targetIndex,
              );
      if (mounted) {
        setState(() => _plan = updatedPlan);
      }
      ref.invalidate(activePlanProvider);
      ref.invalidate(allPlansProvider);
    } catch (_) {
      if (mounted) {
        _showError('Não foi possível atualizar a sessão. Tente novamente.');
      }
    }
  }

  Future<void> _generateNewPlan() async {
    setState(() {
      _phase = _PlanPhase.config;
      _objectiveCtrl.clear();
      _dateCtrl.clear();
      _noticeAnalysis = null;
      _noticeDocument = null;
      _selectedSubjectIndexes = {};
      _tempo = 30;
    });
  }

  Future<void> _goToQuiz([StudyPlanItem? item]) async {
    final plan = _plan;
    if (plan == null || plan.items.isEmpty) return;
    final session = item ??
        plan.items
            .firstWhere((i) => !i.isCompleted, orElse: () => plan.items.first);
    await context.pushNamed('quizSession', extra: {
      'generationParams': studyPlanQuizRequest(plan, session),
      'infiniteMode': false,
    });
    if (mounted) {
      ref.invalidate(activePlanProvider);
      await _loadActivePlan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _PlanPhase.config => _buildConfigPhase(),
      _PlanPhase.review => _buildReviewPhase(),
      _PlanPhase.viewing => _buildViewingPhase(),
    };
  }

  Widget _buildConfigPhase() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/'),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text('←',
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '📅 Plano de Estudo',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Botão para ver plano atual se existir
                    if (_plan != null) ...[
                      _OutlineButton(
                        label: 'Ver Plano Atual →',
                        onPressed: () =>
                            setState(() => _phase = _PlanPhase.viewing),
                      ),
                      const SizedBox(height: 24),
                    ],

                    const Text(
                      'Central de Editais',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Envie o PDF uma vez. Ele sera processado em segundo plano, '
                      'com OCR seletivo e retomada automatica.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    if (_noticeDocuments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final document in _noticeDocuments.take(3))
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: _noticeDocument?.id == document.id
                                ? AppColors.primary.withOpacity(0.1)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _noticeDocument?.id == document.id
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ListTile(
                                  dense: true,
                                  onTap: () => unawaited(
                                    _activateNoticeDocument(document),
                                  ),
                                  leading: const Icon(
                                    Icons.picture_as_pdf_outlined,
                                    color: AppColors.primaryLight,
                                  ),
                                  title: Text(
                                    document.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${_documentStatusLabel(document)} '
                                    '(${document.progress}%)',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Excluir edital',
                                    onPressed: () =>
                                        _deleteNoticeDocument(document),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ),
                                if (document.status ==
                                    StudyDocumentStatus.needsReview)
                                  Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 12),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(document.errorMessage ??
                                                (document.cargos.isEmpty
                                                    ? 'Nenhum cargo foi identificado. Revise o cargo e confira se o PDF contém o conteúdo programático.'
                                                    : 'Revise o cargo selecionado para continuar a análise.')),
                                            const SizedBox(height: 8),
                                            OutlinedButton.icon(
                                                onPressed: _analyzingNotice
                                                    ? null
                                                    : () =>
                                                        _reviewNoticeDocument(
                                                            document),
                                                icon: const Icon(
                                                    Icons.edit_note_rounded),
                                                label: const Text(
                                                    'Revisar edital')),
                                          ])),
                                if (document.canRetry &&
                                    (document.status ==
                                            StudyDocumentStatus.failed ||
                                        document.status ==
                                            StudyDocumentStatus.needsReview))
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          document.errorMessage ??
                                              'A analise foi interrompida, mas '
                                                  'o PDF continua salvo.',
                                          style: const TextStyle(
                                            color: AppColors.error,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        OutlinedButton.icon(
                                          key: Key(
                                            'retryStudyDocument-${document.id}',
                                          ),
                                          onPressed: _retryingNotice
                                              ? null
                                              : () => _retryNoticeDocument(
                                                    document,
                                                  ),
                                          icon: _retryingNotice
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.refresh_rounded,
                                                ),
                                          label: const Text(
                                            'Tentar análise novamente',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 18),
                    _SectionLabel('Edital do concurso'),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('studyPlanNoticePdfButton'),
                        onPressed: _extractingNotice ? null : _pickNoticePdf,
                        icon: _extractingNotice
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(
                          'Enviar novo edital em PDF',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _noticeDocument == null
                          ? 'Somente PDF. Limite operacional de 100 MiB.'
                          : '${_documentStatusLabel(_noticeDocument!)} '
                              '- ${_noticeDocument!.progress}%',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    if (_extractingNotice && _uploadProgress > 0) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _uploadProgress / 100,
                        backgroundColor: AppColors.surface2,
                        color: AppColors.primary,
                      ),
                    ] else if (_noticeDocument?.status.isProcessing ??
                        false) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _noticeDocument!.progress / 100,
                        backgroundColor: AppColors.surface2,
                        color: AppColors.primary,
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Tempo Diário
                    _SectionLabel('Tempo diário: ${_tempo}min por dia'),
                    Slider(
                      value: _tempo.toDouble(),
                      min: 15,
                      max: 120,
                      divisions: 7,
                      label: '${_tempo}min',
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _tempo = v.round()),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewPhase() {
    final analysis = _noticeAnalysis;
    if (analysis == null) {
      return _buildConfigPhase();
    }

    final crono = analysis.cronograma;
    final concurso = analysis.concursoInfo;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar',
                    onPressed: () => setState(() => _phase = _PlanPhase.config),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Revise o conteúdo do edital',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  // ── Cabeçalho do concurso ────────────────────────
                  if (concurso != null && concurso.orgao.isNotEmpty)
                    _ConcursoInfoCard(concurso: concurso, cronograma: crono),

                  if (crono != null && crono.dataProva.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.event_available_rounded,
                              color: AppColors.success, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Data da prova extraída do edital: ${_formatDisplayDate(crono.dataProva)}',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (crono == null || crono.dataProva.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'A data da prova não foi encontrada no edital.',
                        style: TextStyle(color: AppColors.warning),
                      ),
                    ),

                  const SizedBox(height: 4),
                  Text(
                    analysis.jobTitle.isEmpty
                        ? _objectiveCtrl.text.trim()
                        : analysis.jobTitle,
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${analysis.subjects.length} disciplinas • ${analysis.subjects.fold<int>(0, (acc, s) => acc + s.topics.length)} tópicos',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedSubjectIndexes = Set<int>.from(
                                  List<int>.generate(
                                    analysis.subjects.length,
                                    (i) => i,
                                  ),
                                );
                              });
                            },
                            child: const Text(
                              'Marcar todas',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedSubjectIndexes.clear();
                              });
                            },
                            child: const Text(
                              'Desmarcar',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...analysis.subjects.asMap().entries.map((entry) {
                    final index = entry.key;
                    final subject = entry.value;
                    final selected = _selectedSubjectIndexes.contains(index);
                    return Card(
                      color: AppColors.surface,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: CheckboxListTile(
                        value: selected,
                        activeColor: AppColors.primary,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedSubjectIndexes.add(index);
                            } else {
                              _selectedSubjectIndexes.remove(index);
                            }
                          });
                        },
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                subject.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (subject.peso != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Peso ${subject.peso}',
                                  style: const TextStyle(
                                    color: AppColors.primaryLight,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (subject.numQuestoes != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${subject.numQuestoes}Q',
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subject.topics.join(' • '),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                              if (subject.evidence.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Base no edital: ${subject.evidence}',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: AppButton(
                label:
                    'Criar plano (${_selectedSubjectIndexes.length} de ${analysis.subjects.length} selecionadas)',
                isLoading: _loading,
                onPressed: _generatePlan,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Converte YYYY-MM-DD → DD/MM/YYYY para exibição
  String _formatDisplayDate(String iso) {
    final parts = iso.split('-');
    if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    return iso;
  }

  Widget _buildViewingPhase() {
    if (_plan == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: Text('Nenhum plano disponível',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }

    final plan = _plan!;
    final itemsConcluidos = plan.items.where((item) => item.isCompleted).length;
    final progressPct = plan.totalProgress;

    // Agrupar itens por dia
    final itensPorDia = <String, List<StudyPlanItem>>{};
    for (final item in plan.items) {
      itensPorDia.putIfAbsent(item.dia, () => []).add(item);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/'),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text('←',
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '📅 ${plan.objetivo}',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Progresso
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$itemsConcluidos/${plan.items.length} itens concluídos',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progressPct,
                              minHeight: 6,
                              backgroundColor: AppColors.border,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.success),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    _NextStudySession(
                        plan: plan, onStudy: (item) => _goToQuiz(item)),
                    // Chip com data da prova
                    if (plan.dataProva != null && plan.dataProva!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Chip(
                          label: Text('📅 Prova: ${plan.dataProva}',
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 12)),
                          backgroundColor: AppColors.primary.withOpacity(0.15),
                          side: const BorderSide(
                              color: AppColors.primary, width: 1),
                        ),
                      ),

                    // Itens agrupados por dia
                    ...itensPorDia.entries.map((entry) {
                      final dia = entry.key;
                      final itens = entry.value;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 12),
                            child: Text(
                              dia.toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          ...itens.map((item) {
                            return _StudyItemCard(
                              item: item,
                              onToggle: () => _toggleItem(item),
                              onStudy: () => _goToQuiz(item),
                            );
                          }),
                        ],
                      );
                    }),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Botões inferiores ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                children: [
                  _OutlineButton(
                    label: 'Gerar Novo Plano',
                    onPressed: _generateNewPlan,
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Estudar Agora →',
                    onPressed: () => _goToQuiz(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card que representa um item do plano de estudo.
