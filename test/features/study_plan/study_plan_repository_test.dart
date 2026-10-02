import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_model.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_notice_analysis.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_document.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

class _MockPreferences extends Mock implements AccountScopedPreferences {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;
  late StudyPlanRepository repository;
  late AccountScopedPreferences preferences;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    apiClient = _MockApiClient();
    dio = _MockDio();
    preferences = AccountScopedPreferences.instance;
    preferences.setActiveAccountId(null);
    repository = StudyPlanRepository(apiClient);

    when(() => apiClient.dio).thenReturn(dio);
  });

  test('savePlan e getActivePlan respeitam a conta ativa', () async {
    preferences.setActiveAccountId('user-a');
    await repository.savePlan(
      StudyPlan(
        objetivo: 'TRT',
        tempoDiario: 60,
        items: const [
          StudyPlanItem(
            id: 1,
            dia: 'Segunda',
            tema: 'Direito',
            atividade: 'Revisar teoria',
            duracaoMin: 60,
            prioridade: 1,
          ),
        ],
      ),
    );

    preferences.setActiveAccountId('user-b');
    await repository.savePlan(
      StudyPlan(
        objetivo: 'INSS',
        tempoDiario: 30,
        items: const [
          StudyPlanItem(
            id: 2,
            dia: 'Terca',
            tema: 'Português',
            atividade: 'Resolver questoes',
            duracaoMin: 30,
            prioridade: 2,
          ),
        ],
      ),
    );

    preferences.setActiveAccountId('user-a');
    final planA = await repository.getActivePlan();
    preferences.setActiveAccountId('user-b');
    final planB = await repository.getActivePlan();

    expect(planA?.objetivo, 'TRT');
    expect(planB?.objetivo, 'INSS');
  });

  test('migrates a legacy plan without re-entering the legacy reader',
      () async {
    final legacy = StudyPlan(
      id: 'legacy-plan',
      objetivo: 'Concurso legado',
      tempoDiario: 30,
      items: const [],
    );
    final stored = <String, String>{
      'study_plan_active': jsonEncode(legacy.toJson()),
    };
    final store = _MockPreferences();
    var legacyReads = 0;
    when(() => store.getString(any())).thenAnswer((invocation) async {
      final key = invocation.positionalArguments.single as String;
      if (key == 'study_plan_active' && ++legacyReads > 1) {
        // Bound the old recursion so a regression fails instead of hanging CI.
        return null;
      }
      return stored[key];
    });
    when(() => store.setString(any(), any())).thenAnswer((invocation) async {
      stored[invocation.positionalArguments[0] as String] =
          invocation.positionalArguments[1] as String;
    });
    final legacyRepository = StudyPlanRepository(apiClient, preferences: store);

    final active = await legacyRepository.getActivePlan();

    expect(active?.id, 'legacy-plan');
    expect(legacyReads, 1);
    expect(jsonDecode(stored['study_plans_all']!) as List, hasLength(1));
    expect(stored['study_plan_active_id'], 'legacy-plan');
    expect((await legacyRepository.getPlans()).single.id, 'legacy-plan');
    expect(legacyReads, 1);
  });

  test('generatePlan preserves backend validation detail', () async {
    when(
      () => dio.post(
        ApiEndpoints.studyPlanGenerate,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.studyPlanGenerate),
        response: Response(
          requestOptions: RequestOptions(path: ApiEndpoints.studyPlanGenerate),
          statusCode: 422,
          data: {
            'detail': [
              {
                'loc': ['body', 'goal'],
                'msg': 'Field required',
              },
            ],
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.generatePlan(
        objetivo: 'TRT',
        tempoDiario: 60,
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('goal: Field required'),
        ),
      ),
    );
  });

  test('generatePlan throws remote service exception on server failure',
      () async {
    when(
      () => dio.post(
        ApiEndpoints.studyPlanGenerate,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.studyPlanGenerate),
        response: Response(
          requestOptions: RequestOptions(path: ApiEndpoints.studyPlanGenerate),
          statusCode: 500,
          data: {'detail': 'erro interno'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.generatePlan(
        objetivo: 'TRT',
        tempoDiario: 60,
      ),
      throwsA(isA<RemoteServiceException>()),
    );
  });

  test('generatePlan forwards selected provider to backend', () async {
    when(
      () => dio.post(
        ApiEndpoints.studyPlanGenerate,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.studyPlanGenerate),
        data: {
          'semanas': [
            {
              'semana': 1,
              'foco': 'TRT',
              'tarefas': ['Revisar teoria'],
            },
          ],
        },
      ),
    );

    await repository.generatePlan(
      objetivo: 'TRT',
      tempoDiario: 60,
      aiProvider: 'groq',
    );

    final captured = verify(
      () => dio.post(
        ApiEndpoints.studyPlanGenerate,
        data: captureAny(named: 'data'),
      ),
    ).captured.last as Map<String, dynamic>;

    expect(captured['provider'], 'groq');
  });

  test('analyzeNotice sends cargo and extracted PDF text to backend', () async {
    when(
      () => dio.post(
        ApiEndpoints.studyPlanAnalyzeNotice,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions:
            RequestOptions(path: ApiEndpoints.studyPlanAnalyzeNotice),
        data: {
          'cargo_encontrado': 'Analista',
          'disciplinas': [
            {
              'nome': 'Português',
              'topicos': ['Interpretação de texto'],
              'evidencia': 'Língua Portuguesa: interpretação de textos.',
            },
          ],
        },
      ),
    );

    final analysis = await repository.analyzeNotice(
      jobTitle: 'Analista',
      selectedCargo: const CargoNoticeItem(
        cargoId: 'c1',
        titulo: 'Analista',
        escolaridade: 'Superior',
        vagas: 12,
      ),
      noticeText: 'Conteúdo extraído do PDF',
      aiProvider: 'gemini',
    );

    expect(analysis.subjects.single.name, 'Português');
    final payload = verify(
      () => dio.post(
        ApiEndpoints.studyPlanAnalyzeNotice,
        data: captureAny(named: 'data'),
        options: any(named: 'options'),
      ),
    ).captured.single as Map<String, dynamic>;
    expect(payload, {
      'job_title': 'Analista',
      'job_id': 'c1',
      'job_education': 'Superior',
      'job_vacancies': 12,
      'notice_text': 'Conteúdo extraído do PDF',
      'provider': 'gemini',
    });
  });

  test('analyzeNotice accepts cargo discovery without subjects', () async {
    when(
      () => dio.post(
        ApiEndpoints.studyPlanAnalyzeNotice,
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions:
            RequestOptions(path: ApiEndpoints.studyPlanAnalyzeNotice),
        data: {
          'cargo_encontrado': '',
          'cargos_popup': [
            {
              'cargo_id': 'c1',
              'titulo': 'Analista',
              'escolaridade': 'Superior',
              'vagas': 1,
            },
          ],
          'disciplinas': <Object>[],
        },
      ),
    );

    final result = await repository.analyzeNotice(
      noticeText: 'Conteúdo extraído do edital em PDF',
      aiProvider: 'gemini',
    );

    expect(result.subjects, isEmpty);
    expect(result.cargosPopup.single.titulo, 'Analista');

    final invocation = verify(
      () => dio.post(
        ApiEndpoints.studyPlanAnalyzeNotice,
        data: captureAny(named: 'data'),
        options: captureAny(named: 'options'),
      ),
    );
    final captured = invocation.captured;
    final payload = captured[0] as Map<String, dynamic>;
    final options = captured[1] as Options;
    expect(payload, isNot(contains('job_title')));
    expect(options.receiveTimeout, const Duration(seconds: 110));
  });

  test('uploadDocument streams PDF to the versioned durable pipeline',
      () async {
    var backendReadyChecks = 0;
    repository = StudyPlanRepository(
      apiClient,
      ensureBackendReady: () async {
        backendReadyChecks++;
      },
    );
    when(
      () => dio.post(
        ApiEndpoints.documentsV2,
        data: any(named: 'data'),
        options: any(named: 'options'),
        onSendProgress: any(named: 'onSendProgress'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.documentsV2),
        statusCode: 201,
        data: {
          'id': 42,
          'purpose': 'study_plan',
          'file_name': 'edital.pdf',
          'size_bytes': 12,
          'status': 'extracting',
          'progress': 0,
          'cargos': <Object>[],
        },
      ),
    );

    final bytes = Uint8List.fromList('%PDF-1.7\nok'.codeUnits);
    final document = await repository.uploadDocument(
      purpose: StudyDocumentPurpose.studyPlan,
      fileName: 'edital.pdf',
      length: bytes.length,
      openRead: () => Stream<List<int>>.value(bytes),
    );

    expect(document.id, 42);
    expect(document.status, StudyDocumentStatus.extracting);
    expect(backendReadyChecks, 1);
    final captured = verify(
      () => dio.post(
        ApiEndpoints.documentsV2,
        data: captureAny(named: 'data'),
        options: captureAny(named: 'options'),
        onSendProgress: any(named: 'onSendProgress'),
      ),
    ).captured;
    final form = captured[0] as FormData;
    final options = captured[1] as Options;
    expect(
      form.fields.any(
        (entry) => entry.key == 'purpose' && entry.value == 'study_plan',
      ),
      isTrue,
    );
    expect(form.files.single.key, 'file');
    expect(options.sendTimeout, const Duration(minutes: 5));
  });

  test('getDocument maps cargos, progress, result and evidence pages',
      () async {
    when(
      () => dio.get(ApiEndpoints.documentV2(42)),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.documentV2(42)),
        data: {
          'id': 42,
          'purpose': 'study_plan',
          'file_name': 'edital.pdf',
          'size_bytes': 200,
          'status': 'ready',
          'progress': 100,
          'page_count': 90,
          'exam_date': '2027-10-10',
          'selected_cargo_id': 'cargo-2',
          'selected_cargo_title': 'Analista',
          'cargos': [
            {'id': 'cargo-2', 'title': 'Analista', 'page_number': 80},
          ],
          'analysis_result': {
            'cargo_id': 'cargo-2',
            'cargo': 'Analista',
            'data_prova': '2027-10-10',
            'disciplinas': [
              {
                'nome': 'Banco de Dados',
                'topicos': ['SQL'],
                'evidencias': [
                  {'pagina': 80, 'trecho': 'Banco de Dados: SQL'},
                ],
              },
            ],
          },
        },
      ),
    );

    final document = await repository.getDocument(42);

    expect(document.cargos.single.title, 'Analista');
    expect(document.analysis!.subjects.single.name, 'Banco de Dados');
    expect(document.analysis!.subjects.single.evidencePages, [80]);
    expect(document.examDate, '2027-10-10');
  });

  test('selectDocumentCargo queues background analysis', () async {
    when(
      () => dio.post(
        ApiEndpoints.documentSelectCargoV2(42),
        data: {'cargo_id': 'cargo-2'},
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions:
            RequestOptions(path: ApiEndpoints.documentSelectCargoV2(42)),
        statusCode: 202,
        data: {
          'id': 42,
          'purpose': 'study_plan',
          'file_name': 'edital.pdf',
          'size_bytes': 200,
          'status': 'analyzing',
          'progress': 60,
          'cargos': <Object>[],
        },
      ),
    );

    final document = await repository.selectDocumentCargo(
      documentId: 42,
      cargoId: 'cargo-2',
    );

    expect(document.status, StudyDocumentStatus.analyzing);
  });

  test('retryDocumentAnalysis requeues the existing extracted document',
      () async {
    when(
      () => dio.post(ApiEndpoints.documentRetryAnalysisV2(42)),
    ).thenAnswer(
      (_) async => Response(
        requestOptions:
            RequestOptions(path: ApiEndpoints.documentRetryAnalysisV2(42)),
        statusCode: 202,
        data: {
          'id': 42,
          'purpose': 'study_plan',
          'file_name': 'edital.pdf',
          'size_bytes': 200,
          'status': 'analyzing',
          'progress': 62,
          'can_retry': false,
          'cargos': <Object>[],
        },
      ),
    );

    final document = await repository.retryDocumentAnalysis(42);

    expect(document.status, StudyDocumentStatus.analyzing);
    expect(document.canRetry, isFalse);
    verify(() => dio.post(ApiEndpoints.documentRetryAnalysisV2(42))).called(1);
  });

  test('getDocument maps retry metadata from a failed analysis', () async {
    when(
      () => dio.get(ApiEndpoints.documentV2(42)),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.documentV2(42)),
        data: {
          'id': 42,
          'purpose': 'study_plan',
          'file_name': 'edital.pdf',
          'size_bytes': 200,
          'status': 'failed',
          'progress': 62,
          'can_retry': true,
          'cargos': <Object>[],
          'error': {
            'code': 'payload_too_large',
            'message': 'O segmento excedeu o limite do provedor.',
          },
        },
      ),
    );

    final document = await repository.getDocument(42);

    expect(document.canRetry, isTrue);
    expect(document.errorCode, 'payload_too_large');
    expect(
      document.errorMessage,
      'O segmento excedeu o limite do provedor.',
    );
  });

  test('getDocumentContent returns complete library extraction', () async {
    when(
      () => dio.get(ApiEndpoints.documentContentV2(7)),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.documentContentV2(7)),
        data: {
          'document_id': 7,
          'text': 'Pagina um\n\nPagina dois',
          'page_count': 2,
        },
      ),
    );

    final text = await repository.getDocumentContent(7);

    expect(text, contains('Pagina dois'));
  });
}
