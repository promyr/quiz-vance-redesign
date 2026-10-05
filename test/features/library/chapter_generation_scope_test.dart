import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/observability/app_observability.dart';
import 'package:quiz_vance_flutter/features/library/data/library_repository.dart';
import 'package:quiz_vance_flutter/features/library/data/material_scope_store.dart';
import 'package:quiz_vance_flutter/features/library/domain/material_chapters.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/quiz/application/quiz_generation_coordinator.dart';
import 'package:quiz_vance_flutter/features/quiz/data/quiz_repository.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';

class MockQuiz extends Mock implements QuizRepository {}

class MockGuard extends Mock implements AiGenerationGuard {}

class MockClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  final file = LibraryFile(
      id: 71,
      nome: 'Livro',
      conteudo:
          'Capítulo 1 - Direito\nOs contratos regulam obrigações entre partes. EXCLUIDO_DIREITO identifica esta matéria jurídica.\nCapítulo 2 - Matemática\nA multiplicação representa uma soma repetida. ESCOLHIDO_MATEMATICA identifica o cálculo de produtos.',
      criadoEm: DateTime(2026));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MaterialScopeStore()
        .save(file, [detectMaterialChapters(file.conteudo)[1]]);
  });
  test('quiz envia apenas o capítulo escolhido', () async {
    final repo = MockQuiz();
    final guard = MockGuard();
    when(() => guard.ensureReadyForGeneration(
            overrideProvider: any(named: 'overrideProvider')))
        .thenAnswer((_) async => 'groq');
    when(() => repo.generate(
            topic: any(named: 'topic'),
            difficulty: any(named: 'difficulty'),
            quantity: any(named: 'quantity'),
            aiProvider: any(named: 'aiProvider'),
            conteudo: any(named: 'conteudo'),
            documentName: any(named: 'documentName'),
            documentId: any(named: 'documentId')))
        .thenAnswer((_) async => <Question>[]);
    await QuizGenerationCoordinator(repo,
            aiGenerationGuard: guard,
            observability: AppObservability(maxEntries: 10))
        .generate(
            useLibrary: true,
            topic: 'Livro',
            difficulty: 'medium',
            quantity: 5,
            infiniteMode: false,
            preferredProvider: 'groq',
            selectedLibraryFile: file);
    final sent = verify(() => repo.generate(
        topic: any(named: 'topic'),
        difficulty: any(named: 'difficulty'),
        quantity: any(named: 'quantity'),
        aiProvider: any(named: 'aiProvider'),
        conteudo: captureAny(named: 'conteudo'),
        documentName: any(named: 'documentName'),
        documentId: any(named: 'documentId'))).captured.single as String;
    expect(sent, contains('ESCOLHIDO_MATEMATICA'));
    expect(sent, isNot(contains('EXCLUIDO_DIREITO')));
  });
  test('pacote de estudo envia apenas capítulos marcados', () async {
    final client = MockClient();
    final dio = MockDio();
    when(() => client.dio).thenReturn(dio);
    when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
            data: <String, dynamic>{},
            requestOptions: RequestOptions(path: '/')));
    await LibraryRepository(client).generatePackage(file: file);
    final data = verify(() => dio.post(any(), data: captureAny(named: 'data')))
        .captured
        .single as Map;
    expect(data['context'], contains('ESCOLHIDO_MATEMATICA'));
    expect(data['context'], isNot(contains('EXCLUIDO_DIREITO')));
  });
}
