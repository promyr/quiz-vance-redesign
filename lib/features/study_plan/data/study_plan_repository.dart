import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../domain/study_plan_model.dart';

class StudyPlanRepository {
  const StudyPlanRepository(this._client);

  final ApiClient _client;
  static const _planKey = 'study_plan_active';

  Future<StudyPlan?> getActivePlan() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_planKey);
    if (raw == null) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return StudyPlan(
        objetivo: map['objetivo'] as String,
        dataProva: map['data_prova'] as String?,
        tempoDiario: ((map['tempo_diario'] as num?) ?? 30).toInt(),
        items: (map['items'] as List<dynamic>)
            .map((item) => StudyPlanItem.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> savePlan(StudyPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _planKey,
      jsonEncode({
        'objetivo': plan.objetivo,
        'data_prova': plan.dataProva,
        'tempo_diario': plan.tempoDiario,
        'items': plan.items.map((item) => item.toJson()).toList(),
      }),
    );
  }

  Future<StudyPlan> toggleItem(StudyPlan plan, int index) async {
    if (index < 0 || index >= plan.items.length) return plan;

    final updatedItems = List<StudyPlanItem>.of(plan.items);
    updatedItems[index] =
        updatedItems[index].copyWith(concluido: !updatedItems[index].concluido);

    final updatedPlan = StudyPlan(
      objetivo: plan.objetivo,
      dataProva: plan.dataProva,
      tempoDiario: plan.tempoDiario,
      items: updatedItems,
    );

    await savePlan(updatedPlan);
    return updatedPlan;
  }

  Future<StudyPlan> generatePlan({
    required String objetivo,
    String? dataProva,
    required int tempoDiario,
    List<String> topicos = const [],
    String? aiProvider,
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

      final items = _semanaListToItems(rawList, tempoDiario);
      if (items.isEmpty) {
        throw const RemoteServiceException(
          'O backend não retornou tarefas para o plano de estudo.',
        );
      }

      final plan = StudyPlan(
        objetivo: objetivo,
        dataProva: dataProva,
        tempoDiario: tempoDiario,
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

  List<StudyPlanItem> _semanaListToItems(
    List<dynamic> semanas,
    int tempoDiarioMin,
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
        items.add(
          StudyPlanItem(
            id: diaIndex,
            dia: diasDaSemana[diaIndex % 7],
            tema: foco,
            atividade: tarefa,
            duracaoMin: tempoDiarioMin,
            prioridade: semanaNum <= 2 ? 1 : 2,
          ),
        );
        diaIndex++;
      }
    }

    return items;
  }
}

final studyPlanRepositoryProvider = Provider<StudyPlanRepository>(
  (ref) => StudyPlanRepository(ref.watch(apiClientProvider)),
);

final activePlanProvider = FutureProvider.autoDispose<StudyPlan?>((ref) {
  return ref.watch(studyPlanRepositoryProvider).getActivePlan();
});
