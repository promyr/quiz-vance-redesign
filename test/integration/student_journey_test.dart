// Screens, repositories and SQLite are real. Network responses are isolated
// fixtures: this journey does not prove Android plugins or production AI.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:quiz_vance_flutter/features/error_notebook/data/error_notebook_repository.dart';
import 'package:quiz_vance_flutter/features/history/presentation/activity_history_screen.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/library/presentation/study_package_screen.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_result_screen.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_session_screen.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/stats/presentation/stats_screen.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:quiz_vance_flutter/shared/application/offline_sync_queue.dart';
import 'package:quiz_vance_flutter/shared/providers/user_provider.dart';

class StudentApi extends ApiClient {
  StudentApi() {
    transport.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add('${r.method} ${r.path}');
      Object data;
      switch (r.path) {
        case ApiEndpoints.quizGenerate:
          generation = Map<String, dynamic>.from(r.data as Map);
          data = {'questions': questions};
        case ApiEndpoints.quizSubmit:
          if (!online) {
            h.reject(DioException(
                requestOptions: r,
                type: DioExceptionType.connectionError,
                message: 'isolated offline fixture'));
            return;
          }
          if (rejectResult) {
            h.reject(DioException(
                requestOptions: r,
                type: DioExceptionType.badResponse,
                response: Response(
                    requestOptions: r,
                    statusCode: 422,
                    data: {'detail': 'Resultado rejeitado para revisão.'})));
            return;
          }
          final value = Map<String, dynamic>.from(r.data as Map);
          results.putIfAbsent(value['session_id'].toString(), () => value);
          data = {'ok': true};
        case ApiEndpoints.userStats:
          final total =
              results.values.fold<int>(0, (n, e) => n + (e['total'] as int));
          final correct =
              results.values.fold<int>(0, (n, e) => n + (e['correct'] as int));
          data = {
            'total_questoes': total,
            'today_questoes': total,
            'today_acertos': correct,
            'today_xp': correct * 10,
            'xp': correct * 10,
            'level': 1,
            'is_premium': true,
            'accuracy_rate': total == 0 ? 0 : 100 * correct / total
          };
        case ApiEndpoints.quizHistory:
          data = {
            'history': results.entries
                .map((e) => {
                      'event_id': e.key,
                      'total': e.value['total'],
                      'correct': e.value['correct'],
                      'xp_earned': e.value['xp_earned'],
                      'accuracy': 50.0,
                      'created_at': DateTime.now().toIso8601String(),
                    })
                .toList()
          };
        case ApiEndpoints.userAchievements:
          data = {'achievements': []};
        case ApiEndpoints.userAchievementsUnlock:
          data = {'ok': true};
        default:
          // Fail unexpected network usage instead of accidentally contacting production.
          h.reject(DioException(
              requestOptions: r, message: 'Unsupported fixture ${r.path}'));
          return;
      }
      h.resolve(Response(requestOptions: r, statusCode: 200, data: data));
    }));
  }
  final transport = Dio();
  final requests = <String>[];
  final results = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? generation;
  bool online = true;
  bool rejectResult = false;
  @override
  Dio get dio => transport;
}

final questions = [
  {
    'id': 'fifth',
    'text': 'Qual alternativa corresponde a cinco?',
    'options': [
      for (var i = 1; i <= 5; i++) {'id': '$i', 'text': 'Número $i'}
    ],
    'correctOptionId': '5',
    'explanation': 'Cinco é a quinta alternativa. ' * 35
  },
  {
    'id': 'wrong',
    'text': 'Quanto é dois mais dois?',
    'options': [
      {'id': 'a', 'text': 'Quatro'},
      {'id': 'b', 'text': 'Três'}
    ],
    'correctOptionId': 'a',
    'explanation':
        'Somando duas unidades a duas unidades, obtemos quatro. ' * 35
  },
];

final journeyFindings = <String>[];
final journeySteps = <String>[];

Future<void> click(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 350,
        scrollable: find.byType(Scrollable).first, maxScrolls: 30);
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 500));
  journeySteps.add(target.description);
  debugPrint('JOURNEY_STEP ${target.description}');
  // Tap the visible button surface, not the center of an overflowing label.
  final surface = target.description.contains('Iniciar Quiz com este Material')
      ? find.ancestor(of: target, matching: find.byType(GestureDetector)).first
      : target;
  await tester.tap(surface);
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  final error = tester.takeException();
  if (error != null) journeyFindings.add(error.toString());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('JourneyFont');
    font.addFont(File(r'C:\Windows\Fonts\segoeui.ttf')
        .readAsBytes()
        .then(ByteData.sublistView));
    await font.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(File(
            r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf')
        .readAsBytes()
        .then(ByteData.sublistView));
    await icons.load();
  });
  for (final scenario in [
    (width: 320.0, scale: 1.0, offline: false),
    (width: 360.0, scale: 1.6, offline: false),
    (width: 800.0, scale: 2.0, offline: false),
    (width: 320.0, scale: 2.0, offline: false),
    (width: 360.0, scale: 3.0, offline: false),
    (width: 480.0, scale: 2.0, offline: false),
    (width: 360.0, scale: 1.0, offline: true),
  ]) {
    testWidgets(
        'student journey ${scenario.width} font ${scenario.scale} offline ${scenario.offline}',
        (tester) async {
      journeyFindings.clear();
      journeySteps.clear();
      final previousError = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint('JOURNEY_UI_DIAGNOSTIC ${details.toString()}');
        previousError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = previousError;
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(scenario.width, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      AccountScopedPreferences.instance.setActiveAccountId('student-journey');
      final dir = await tester
          .runAsync(() => Directory.systemTemp.createTemp('qv-student-'));
      await tester.runAsync(() async {
        await LocalStorage.instance.configureForTesting(
            databasePath: '${dir!.path}/data.db',
            keyStore: MemoryLocalStorageKeyStore());
        await LocalStorage.instance.init();
      });
      LocalStorage.instance.setActiveAccountId('student-journey');
      addTearDown(() async {
        await LocalStorage.instance.resetForTesting();
        AccountScopedPreferences.instance.setActiveAccountId(null);
      });
      final api = StudentApi();
      final file = LibraryFile(
          id: -91,
          nome: 'Material de matemática',
          conteudo:
              'Capítulo 1 — Adição\nA adição combina quantidades. Dois mais dois resulta em quatro.\nCapítulo 2 — Números\nOs números naturais incluem um, dois, três, quatro e cinco.',
          criadoEm: DateTime.now());
      final package = StudyPackage(
          titulo: 'Matemática',
          resumoCurto: file.conteudo,
          topicosPrincipais: ['Adição'],
          questoes: [],
          checklistEstudo: ['Ler os conceitos', 'Resolver exercícios']);
      final boundary = GlobalKey();
      final router = GoRouter(initialLocation: '/library', routes: [
        GoRoute(
            path: '/library',
            builder: (_, __) =>
                StudyPackageScreen(package: package, file: file)),
        GoRoute(
            path: '/quiz-session',
            name: 'quizSession',
            builder: (_, state) => QuizSessionScreen(
                questions: const [],
                generationParams: (state.extra as Map)['generationParams']
                    as QuizGenerationParams)),
        GoRoute(
            path: '/quiz-result',
            name: 'quizResult',
            builder: (_, state) => QuizResultScreen(
                result: (state.extra as Map)['result'] as QuizResult)),
        GoRoute(path: '/', builder: (_, __) => const StatsScreen()),
        GoRoute(
            path: '/history',
            builder: (_, __) => const ActivityHistoryScreen()),
      ]);
      addTearDown(router.dispose);
      final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
              theme: ThemeData(fontFamily: 'JourneyFont'),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scenario.scale)),
                  child: RepaintBoundary(key: boundary, child: child!)),
              routerConfig: router)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Flashcards'), findsNothing);
      if (scenario.width == 360 && scenario.scale == 1.6) {
        final button = find.text('Iniciar Quiz com este Material');
        await tester.ensureVisible(button);
        await tester.pump(const Duration(seconds: 1));
        final rendered = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await rendered.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
                  'output_apk/jornada-usuario-2026-10-07/library-button-360-font160.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await click(tester, find.text('Iniciar Quiz com este Material'));
      expect(api.generation!['topic'], 'Adição');
      expect(api.generation!['document_id'], 91);
      expect(api.generation!['context'], contains('Dois mais dois'));
      expect(api.generation!.containsKey('provider'), isFalse);
      expect(
          find.text('Qual alternativa corresponde a cinco?'), findsOneWidget);
      await click(tester, find.text('Número 5'));
      expect(find.textContaining('Você acertou!'), findsOneWidget);
      await click(tester, find.text('Próxima questão'));
      expect(find.text('Quanto é dois mais dois?'), findsOneWidget);
      await click(tester, find.text('Três'));
      expect(find.textContaining('Gabarito Comentado'), findsOneWidget);
      api.online = !scenario.offline;
      await click(tester, find.text('Ver resultado'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('1 de 2 corretas'), findsOneWidget);
      final notebook = ErrorNotebookRepository();
      expect((await notebook.getErrorQuestions()).single.timesFailed, 1);
      if (scenario.offline) {
        expect(await container.read(offlineSyncQueueProvider).getPendingItems(),
            hasLength(1));
        api.online = true;
        api.rejectResult = true;
        await click(tester, find.text('Tentar novamente'));
        expect(find.textContaining('O servidor não aceitou o resultado.'),
            findsOneWidget);
        expect(find.textContaining('quando a conexão voltar'), findsNothing);
        expect(await container.read(offlineSyncQueueProvider).getPendingItems(),
            hasLength(1));
        expect((await notebook.getErrorQuestions()).single.timesFailed, 1);
        api.rejectResult = false;
        await click(tester, find.text('Tentar novamente'));
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(await container.read(offlineSyncQueueProvider).getPendingItems(),
            isEmpty);
        // Retrying upload must not record the same wrong answer again.
        final failures =
            (await notebook.getErrorQuestions()).single.timesFailed;
        if (failures != 1) {
          journeyFindings
              .add('OFFLINE_RETRY: same wrong answer recorded $failures times');
        }
      }
      expect(api.results, hasLength(1));
      expect(api.results.values.single['total'], 2);
      expect(api.results.values.single['correct'], 1);
      await click(
          tester, find.textContaining('Revisar Gabarito e Explicações'));
      expect(find.text('Sua resposta: Três'), findsOneWidget);
      await click(tester, find.text('Voltar ao início'));
      final stats = container.read(userStatsNotifierProvider).requireValue;
      expect(stats.todayQuizzes, 2);
      expect(stats.todayCorrect, 1);
      expect(stats.todayXp, 10);
      expect(find.textContaining('Flashcards'), findsNothing);
      await click(tester, find.text('Ver histórico de atividades'));
      expect(find.textContaining('50%'), findsOneWidget);
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await render.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        final png = File(
            'output_apk/jornada-usuario-2026-10-07/history-${scenario.width.toInt()}-${scenario.scale}.png');
        await png.parent.create(recursive: true);
        await png.writeAsBytes(data!.buffer.asUint8List());
        img.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final record = jsonEncode({
          'width': scenario.width,
          'font_scale': scenario.scale,
          'offline': scenario.offline,
          'steps': journeySteps,
          'findings': journeyFindings,
          'remote_fixture_sessions': api.results.length,
          'questions': stats.todayQuizzes,
          'correct': stats.todayCorrect,
          'xp': stats.todayXp,
        });
        await File('output_apk/jornada-usuario-2026-10-07/journeys.jsonl')
            .writeAsString('$record\n', mode: FileMode.append);
      });
      expect(journeyFindings, isEmpty,
          reason: 'Product findings collected across the full journey');
    });
  }
}
