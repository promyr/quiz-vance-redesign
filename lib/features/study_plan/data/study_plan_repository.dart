import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/backend_warmup.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../../../shared/application/account_scoped_preferences.dart';
import '../domain/study_plan_model.dart';
import '../domain/study_plan_notice_analysis.dart';
import '../domain/study_document.dart';

class StudyPlanRepository {
  StudyPlanRepository(
    this._client, {
    AccountScopedPreferences? preferences,
    Future<void> Function()? ensureBackendReady,
  })  : _preferences = preferences ?? AccountScopedPreferences.instance,
        _ensureBackendReady = ensureBackendReady;

  final ApiClient _client;
  final AccountScopedPreferences _preferences;
  final Future<void> Function()? _ensureBackendReady;

  static const _activePlanKey = 'study_plan_active';
  static const _allPlansKey = 'study_plans_all';
  static const _activePlanIdKey = 'study_plan_active_id';

  /// Obter todos os planos de estudos do usuário.
  Future<List<StudyPlan>> getPlans() async {
    final rawList = await _preferences.getString(_allPlansKey);
    if (rawList != null && rawList.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(rawList);
        final plans = jsonList
            .whereType<Map<String, dynamic>>()
            .map(StudyPlan.fromJson)
            .toList();
        if (plans.isNotEmpty) return plans;
      } catch (_) {}
    }

    // Fallback para o plano legado em _activePlanKey
    final active = await getActivePlan();
    if (active != null) {
      return [active];
    }
    return const [];
  }

  /// Obter o plano de estudos atualmente ativo.
  Future<StudyPlan?> getActivePlan() async {
    final activeId = await _preferences.getString(_activePlanIdKey);
    final plans = await _getPlansRaw();

    if (plans.isNotEmpty) {
      if (activeId != null) {
        final found = plans.firstWhere(
          (p) => p.id == activeId && p.isActive,
          orElse: () =>
              plans.firstWhere((p) => p.isActive, orElse: () => plans.first),
        );
        return found;
      }
      return plans.firstWhere((p) => p.isActive, orElse: () => plans.first);
    }

    // Fallback legado
    final raw = await _preferences.getString(_activePlanKey);
    if (raw == null) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final plan = StudyPlan.fromJson(map);
      // Do not call savePlan here: it reads getPlans, whose legacy fallback
      // enters this method again before the migrated list has been written.
      await _savePlansRaw([plan]);
      if (plan.isActive) {
        await _preferences.setString(_activePlanIdKey, plan.id);
      }
      return plan;
    } catch (_) {
      return null;
    }
  }

  /// Define qual plano é o principal/ativo.
  Future<void> setActivePlan(String planId) async {
    await _preferences.setString(_activePlanIdKey, planId);
    final plans = await getPlans();
    final updated = plans.map((p) {
      if (p.id == planId) {
        return p.copyWith(status: StudyPlanStatus.active);
      }
      return p;
    }).toList();
    await _savePlansRaw(updated);
  }

  /// Salva ou atualiza um plano de estudos.
  Future<void> savePlan(StudyPlan plan) async {
    final plans = await getPlans();
    final index = plans.indexWhere((p) => p.id == plan.id);
    final updated = List<StudyPlan>.from(plans);
    if (index >= 0) {
      updated[index] = plan;
    } else {
      updated.insert(0, plan);
    }

    await _savePlansRaw(updated);
    if (plan.isActive) {
      await _preferences.setString(_activePlanIdKey, plan.id);
      await _preferences.setString(_activePlanKey, jsonEncode(plan.toJson()));
    }
  }

  /// Exclui um plano de estudos.
  Future<void> deletePlan(String planId) async {
    final plans = await getPlans();
    final updated = plans.where((p) => p.id != planId).toList();
    await _savePlansRaw(updated);

    final activeId = await _preferences.getString(_activePlanIdKey);
    if (activeId == planId) {
      if (updated.isNotEmpty) {
        await setActivePlan(updated.first.id);
      } else {
        await _preferences.remove(_activePlanIdKey);
        await _preferences.remove(_activePlanKey);
      }
    }
  }

  /// Alterna o estado de conclusão de uma sessão pelo índice no plano.
  Future<StudyPlan> toggleItem(StudyPlan plan, int index) async {
    if (index < 0 || index >= plan.items.length) return plan;

    final updatedItems = List<StudyPlanItem>.of(plan.items);
    final current = updatedItems[index];
    final newCompleted = !current.isCompleted;

    updatedItems[index] = current.copyWith(
      concluido: newCompleted,
      status: newCompleted
          ? StudySessionStatus.completed
          : StudySessionStatus.pending,
      completedAt: newCompleted ? DateTime.now() : null,
    );

    final updatedPlan = plan.copyWith(items: updatedItems);
    await savePlan(updatedPlan);
    return updatedPlan;
  }

  /// Atualiza o status e resultados de uma sessão específica no plano (ex: pós Quiz ou Flashcards).
  Future<StudyPlan> updateSessionResult({
    required String planId,
    required String sessionId,
    required StudySessionStatus status,
    int? correctAnswers,
    int? incorrectAnswers,
    int? timeSpentMinutes,
    double? score,
  }) async {
    final plans = await getPlans();
    final planIndex = plans.indexWhere((p) => p.id == planId);
    if (planIndex < 0) {
      final active = await getActivePlan();
      if (active == null || active.id != planId) {
        throw Exception('Plano selecionado não encontrado.');
      }
      await savePlan(active);
      return updateSessionResult(
        planId: planId,
        sessionId: sessionId,
        status: status,
        correctAnswers: correctAnswers,
        incorrectAnswers: incorrectAnswers,
        timeSpentMinutes: timeSpentMinutes,
        score: score,
      );
    }

    final targetPlan = plans[planIndex];
    final itemIndex = targetPlan.items.indexWhere(
      (i) => i.effectiveSessionId == sessionId || i.id.toString() == sessionId,
    );

    if (itemIndex < 0) return targetPlan;

    final updatedItems = List<StudyPlanItem>.of(targetPlan.items);
    final current = updatedItems[itemIndex];
    final isDone = status == StudySessionStatus.completed;

    updatedItems[itemIndex] = current.copyWith(
      status: status,
      concluido: isDone,
      completedAt: isDone ? DateTime.now() : current.completedAt,
      correctAnswers: correctAnswers ?? current.correctAnswers,
      incorrectAnswers: incorrectAnswers ?? current.incorrectAnswers,
      timeSpentMinutes: timeSpentMinutes ?? current.timeSpentMinutes,
      score: score ?? current.score,
    );

    final updatedPlan = targetPlan.copyWith(
      items: updatedItems,
      clearActiveSessionProgress: isDone,
    );

    await savePlan(updatedPlan);
    return updatedPlan;
  }

  /// Salva progresso parcial de uma sessão em andamento (ex: interrompida mid-quiz).
  Future<StudyPlan> saveSessionProgress(
    String planId,
    StudySessionProgress progress,
  ) async {
    final plans = await getPlans();
    final planIndex = plans.indexWhere((p) => p.id == planId);
    final targetPlan =
        planIndex >= 0 ? plans[planIndex] : await getActivePlan();
    if (targetPlan == null) {
      return StudyPlan(objetivo: 'Estudo', tempoDiario: 30, items: const []);
    }

    final itemIndex = targetPlan.items.indexWhere(
      (i) =>
          i.sessionId == progress.sessionId ||
          i.id.toString() == progress.sessionId,
    );

    List<StudyPlanItem> updatedItems = targetPlan.items;
    if (itemIndex >= 0) {
      final items = List<StudyPlanItem>.of(targetPlan.items);
      items[itemIndex] = items[itemIndex].copyWith(
        status: StudySessionStatus.inProgress,
      );
      updatedItems = items;
    }

    final updatedPlan = targetPlan.copyWith(
      items: updatedItems,
      activeSessionProgress: progress,
    );

    await savePlan(updatedPlan);
    return updatedPlan;
  }

  /// Reagenda uma sessão para uma nova data (YYYY-MM-DD).
  Future<StudyPlan> rescheduleSession({
    required String planId,
    required String sessionId,
    required String newScheduledDate,
  }) async {
    final plans = await getPlans();
    final planIndex = plans.indexWhere((p) => p.id == planId);
    if (planIndex < 0) return (await getActivePlan())!;

    final targetPlan = plans[planIndex];
    final itemIndex = targetPlan.items.indexWhere(
      (i) => i.effectiveSessionId == sessionId || i.id.toString() == sessionId,
    );

    if (itemIndex < 0) return targetPlan;

    final updatedItems = List<StudyPlanItem>.of(targetPlan.items);
    updatedItems[itemIndex] = updatedItems[itemIndex].copyWith(
      scheduledDate: newScheduledDate,
      status: StudySessionStatus.pending,
    );

    final updatedPlan = targetPlan.copyWith(items: updatedItems);
    await savePlan(updatedPlan);
    return updatedPlan;
  }

  /// Transferir todas as sessões pendentes atrasadas para a data de hoje.
  Future<StudyPlan> carryOverOverdueSessions({
    required String planId,
    required DateTime today,
  }) async {
    final dateStr = today.toIso8601String().substring(0, 10);
    final plans = await getPlans();
    final planIndex = plans.indexWhere((p) => p.id == planId);
    if (planIndex < 0) return (await getActivePlan())!;

    final targetPlan = plans[planIndex];
    final overdue = targetPlan.getOverduePendingSessions(today);
    if (overdue.isEmpty) return targetPlan;

    final overdueIds = overdue.map((i) => i.sessionId).toSet();
    final updatedItems = targetPlan.items.map((item) {
      if (overdueIds.contains(item.sessionId)) {
        return item.copyWith(scheduledDate: dateStr);
      }
      return item;
    }).toList();

    final updatedPlan = targetPlan.copyWith(items: updatedItems);
    await savePlan(updatedPlan);
    return updatedPlan;
  }

  Future<StudyPlan> generatePlan({
    required String objetivo,
    String? dataProva,
    required int tempoDiario,
    List<String> topicos = const [],
    String? aiProvider,
    List<int> sourceDocumentIds = const [],
  }) async {
    try {
      final hoursPerWeek = (tempoDiario * 7 / 60.0).clamp(1.0, 168.0);

      final response = await _client.dio.post(
        ApiEndpoints.studyPlanGenerate,
        data: {
          'goal': objetivo,
          'topics': topicos,
          'hours_per_week': hoursPerWeek,
          'weeks': 4,
          'level': 'iniciante',
          if (aiProvider != null && aiProvider.isNotEmpty)
            'provider': aiProvider,
        },
      );

      final rawList = (response.data['semanas'] as List<dynamic>?) ??
          (response.data['itens'] as List<dynamic>?) ??
          const [];

      final items = _semanaListToItems(rawList, tempoDiario, sourceDocumentIds);
      if (items.isEmpty) {
        throw const RemoteServiceException(
          'O backend não retornou tarefas para o plano de estudo.',
        );
      }

      final plan = StudyPlan(
        title: objetivo,
        objetivo: objetivo,
        dataProva: dataProva,
        tempoDiario: tempoDiario,
        sourceDocumentIds: sourceDocumentIds,
        items: items,
      );

      await savePlan(plan);
      return plan;
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? 0;
      final detail = extractApiErrorMessage(error.response?.data);

      if (detail != null) {
        if (statusCode >= 400 && statusCode < 500) {
          throw Exception(detail);
        }
        throw RemoteServiceException(detail);
      }

      if (statusCode >= 400 && statusCode < 500) {
        throw Exception('Erro $statusCode ao gerar plano de estudo');
      }

      throw buildRemoteServiceException(
        error,
        fallback:
            'Não foi possível gerar o plano de estudo agora. Tente novamente.',
        connectivityFallback:
            'Não foi possível conectar ao servidor do plano de estudo. Verifique sua conexão e tente novamente.',
      );
    } catch (error) {
      if (error is RemoteServiceException) rethrow;
      throw const RemoteServiceException(
        'Não foi possível gerar o plano de estudo agora.',
      );
    }
  }

  Future<StudyPlanNoticeAnalysis> analyzeNotice({
    String? jobTitle,
    CargoNoticeItem? selectedCargo,
    required String noticeText,
    String? aiProvider,
  }) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.studyPlanAnalyzeNotice,
        data: {
          if ((selectedCargo?.titulo ?? jobTitle ?? '').trim().isNotEmpty)
            'job_title': (selectedCargo?.titulo ?? jobTitle ?? '').trim(),
          if (selectedCargo != null && selectedCargo.cargoId.trim().isNotEmpty)
            'job_id': selectedCargo.cargoId.trim(),
          if (selectedCargo != null &&
              selectedCargo.escolaridade.trim().isNotEmpty)
            'job_education': selectedCargo.escolaridade.trim(),
          if (selectedCargo?.vagas != null)
            'job_vacancies': selectedCargo!.vagas,
          'notice_text': noticeText,
          if (aiProvider != null && aiProvider.isNotEmpty)
            'provider': aiProvider,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 110),
        ),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Resposta inválida da análise do edital.');
      }
      final analysis = StudyPlanNoticeAnalysis.fromJson(data);
      final effectiveJobTitle =
          (selectedCargo?.titulo ?? jobTitle ?? '').trim();
      if (effectiveJobTitle.isNotEmpty && analysis.subjects.isEmpty) {
        throw const RemoteServiceException(
          'Nenhum conteúdo programático foi encontrado para esse cargo.',
        );
      }
      return analysis;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.receiveTimeout) {
        throw const RemoteServiceException(
          'A análise do edital demorou mais que o esperado. O servidor continua disponível; tente novamente.',
        );
      }
      throw buildRemoteServiceException(
        error,
        fallback: 'Não foi possível analisar o edital agora.',
        connectivityFallback:
            'Não foi possível conectar ao servidor para analisar o edital.',
      );
    }
  }

  Future<StudyDocument> uploadDocument({
    required StudyDocumentPurpose purpose,
    required String fileName,
    required int length,
    required Stream<List<int>> Function() openRead,
    void Function(int sent, int total)? onProgress,
  }) async {
    if (length <= 0) {
      throw const RemoteServiceException('O PDF selecionado esta vazio.');
    }
    try {
      // O Render pode estar suspenso. Aguarde o health check iniciado no
      // bootstrap antes de abrir a conexao longa do multipart; isso evita que
      // a primeira tentativa estoure o timeout enquanto a segunda funciona.
      await _ensureBackendReady?.call();
      final form = FormData.fromMap({
        'purpose': purpose.apiValue,
        'file': MultipartFile.fromStream(
          openRead,
          length,
          filename: fileName,
          contentType: DioMediaType('application', 'pdf'),
        ),
      });
      final response = await _client.dio.post(
        ApiEndpoints.documentsV2,
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 2),
        ),
        onSendProgress: onProgress,
      );
      return _documentFromResponse(response.data);
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel enviar o PDF.',
        connectivityFallback:
            'Nao foi possivel conectar ao servidor para enviar o PDF.',
      );
    }
  }

  Future<List<StudyDocument>> listDocuments({
    StudyDocumentPurpose? purpose,
  }) async {
    try {
      final response = await _client.dio.get(
        ApiEndpoints.documentsV2,
        queryParameters: {
          if (purpose != null) 'purpose': purpose.apiValue,
        },
      );
      final data = response.data;
      final items = data is Map<String, dynamic>
          ? data['items'] as List<dynamic>? ?? const []
          : const <dynamic>[];
      return items
          .whereType<Map<String, dynamic>>()
          .map(StudyDocument.fromJson)
          .toList(growable: false);
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel carregar a Central de Editais.',
      );
    }
  }

  Future<StudyDocument> getDocument(int documentId) async {
    try {
      final response =
          await _client.dio.get(ApiEndpoints.documentV2(documentId));
      return _documentFromResponse(response.data);
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel atualizar o processamento do PDF.',
      );
    }
  }

  Future<StudyDocument> selectDocumentCargo({
    required int documentId,
    required String cargoId,
    String? cargoTitle,
  }) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.documentSelectCargoV2(documentId),
        data: {
          'cargo_id': cargoId,
          if (cargoTitle != null) 'cargo_title': cargoTitle
        },
      );
      return _documentFromResponse(response.data);
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel iniciar a analise do cargo.',
      );
    }
  }

  Future<StudyDocument> retryDocumentAnalysis(int documentId) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.documentRetryAnalysisV2(documentId),
      );
      return _documentFromResponse(response.data);
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel retomar a analise do edital.',
      );
    }
  }

  Future<String> getDocumentContent(int documentId) async {
    try {
      final response =
          await _client.dio.get(ApiEndpoints.documentContentV2(documentId));
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Resposta invalida do documento.');
      }
      return (data['text'] ?? '').toString();
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel obter o texto extraido do PDF.',
      );
    }
  }

  Future<void> deleteDocument(int documentId) async {
    try {
      await _client.dio.delete(ApiEndpoints.documentV2(documentId));
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback: 'Nao foi possivel excluir o documento.',
      );
    }
  }

  StudyDocument _documentFromResponse(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Resposta invalida do documento.');
    }
    return StudyDocument.fromJson(value);
  }

  Future<List<StudyPlan>> _getPlansRaw() async {
    final rawList = await _preferences.getString(_allPlansKey);
    if (rawList == null || rawList.isEmpty) return const [];
    try {
      final List<dynamic> list = jsonDecode(rawList);
      return list
          .whereType<Map<String, dynamic>>()
          .map(StudyPlan.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _savePlansRaw(List<StudyPlan> plans) async {
    final jsonList = jsonEncode(plans.map((p) => p.toJson()).toList());
    await _preferences.setString(_allPlansKey, jsonList);
  }

  List<StudyPlanItem> _semanaListToItems(
    List<dynamic> semanas,
    int tempoDiarioMin,
    List<int> sourceDocumentIds,
  ) {
    final diasDaSemana = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo',
    ];
    final items = <StudyPlanItem>[];
    var diaIndex = 0;

    for (final semanaRaw in semanas) {
      if (semanaRaw is! Map<String, dynamic>) continue;
      final foco = semanaRaw['foco'] as String? ?? 'Revisão';
      final tarefas = (semanaRaw['tarefas'] as List<dynamic>?)
              ?.map((tarefa) => tarefa.toString())
              .toList() ??
          ['Revisar conteúdo', 'Praticar questões'];
      final semanaNum = (semanaRaw['semana'] as num?)?.toInt() ?? 1;

      for (final tarefa in tarefas) {
        final subject =
            foco.contains(':') ? foco.split(':').first.trim() : foco;
        final topic = foco.contains(':') ? foco.split(':').last.trim() : tarefa;

        // Determinar o modo recomendado alternando ou baseando no texto
        final mode = tarefa.toLowerCase().contains('quest') ||
                tarefa.toLowerCase().contains('quiz')
            ? StudyRecommendedMode.quiz
            : (tarefa.toLowerCase().contains('flash') ||
                    tarefa.toLowerCase().contains('memoriz')
                ? StudyRecommendedMode.flashcard
                : (diaIndex % 2 == 0
                    ? StudyRecommendedMode.quiz
                    : StudyRecommendedMode.flashcard));

        items.add(
          StudyPlanItem(
            id: diaIndex,
            sessionId:
                'session_${diaIndex}_${DateTime.now().millisecondsSinceEpoch}',
            dia: diasDaSemana[diaIndex % 7],
            subject: subject,
            tema: foco,
            subtopics: [topic],
            atividade: tarefa,
            duracaoMin: tempoDiarioMin,
            prioridade: semanaNum <= 2 ? 1 : 2,
            recommendedMode: mode,
            difficulty: 'intermediario',
            status: StudySessionStatus.pending,
            sourceDocumentIds: sourceDocumentIds,
          ),
        );
        diaIndex++;
      }
    }

    return items;
  }
}

final studyPlanRepositoryProvider = Provider<StudyPlanRepository>(
  (ref) => StudyPlanRepository(
    ref.watch(apiClientProvider),
    ensureBackendReady: () async {
      await BackendWarmup.instance.warmUp();
    },
  ),
);

final allPlansProvider = FutureProvider.autoDispose<List<StudyPlan>>((ref) {
  return ref.watch(studyPlanRepositoryProvider).getPlans();
});

final activePlanProvider = FutureProvider.autoDispose<StudyPlan?>((ref) {
  return ref.watch(studyPlanRepositoryProvider).getActivePlan();
});
