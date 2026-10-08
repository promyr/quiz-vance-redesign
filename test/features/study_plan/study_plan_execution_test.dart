import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StudyPlan & StudyPlanItem Domain Tests', () {
    final today = DateTime(2026, 7, 30); // Quinta-feira

    final plan = StudyPlan(
      id: 'plan_test_001',
      title: 'Concurso Técnico em Mecânica',
      objetivo: 'Concurso Técnico em Mecânica',
      dataProva: '2026-10-20',
      tempoDiario: 45,
      status: StudyPlanStatus.active,
      sourceDocumentIds: const [101, 102],
      items: [
        StudyPlanItem(
          id: 1,
          sessionId: 'session_001',
          dia: 'Quinta',
          scheduledDate: '2026-07-30',
          subject: 'Motores de Ciclo Otto',
          tema: 'Componentes eletrônicos',
          subtopics: const ['Sistema de ignição', 'Sensores'],
          atividade: 'Fazer Quiz e Revisar',
          duracaoMin: 30,
          prioridade: 1,
          recommendedMode: StudyRecommendedMode.quiz,
          status: StudySessionStatus.pending,
          sourceDocumentIds: const [101],
        ),
        StudyPlanItem(
          id: 2,
          sessionId: 'session_002',
          dia: 'Quinta',
          scheduledDate: '2026-07-30',
          subject: 'Legislação',
          tema: 'Normas de segurança',
          subtopics: const ['NR-12', 'EPIs'],
          atividade: 'Estudar com Flashcards',
          duracaoMin: 20,
          prioridade: 2,
          recommendedMode: StudyRecommendedMode.quiz,
          status: StudySessionStatus.pending,
          sourceDocumentIds: const [102],
        ),
        StudyPlanItem(
          id: 3,
          sessionId: 'session_003',
          dia: 'Quinta',
          scheduledDate: '2026-07-30',
          subject: 'Revisão',
          tema: 'Sistema de ignição',
          subtopics: const ['Velas', 'Bobinas'],
          atividade: 'Revisão rápida',
          duracaoMin: 15,
          prioridade: 3,
          recommendedMode: StudyRecommendedMode.auto,
          status: StudySessionStatus.completed,
          concluido: true,
          sourceDocumentIds: const [101],
        ),
        // Sessão de outro dia (Sexta)
        StudyPlanItem(
          id: 4,
          sessionId: 'session_004',
          dia: 'Sexta',
          scheduledDate: '2026-07-31',
          subject: 'Hidráulica',
          tema: 'Bombas e válvulas',
          atividade: 'Leitura',
          duracaoMin: 30,
          prioridade: 2,
          status: StudySessionStatus.pending,
        ),
        // Sessão atrasada de ontem
        StudyPlanItem(
          id: 5,
          sessionId: 'session_005',
          dia: 'Quarta',
          scheduledDate: '2026-07-29',
          subject: 'Pneumática',
          tema: 'Compressores',
          atividade: 'Fazer Quiz',
          duracaoMin: 25,
          prioridade: 1,
          status: StudySessionStatus.pending,
        ),
      ],
    );

    test('1. Resolução correta de sessões para a data atual', () {
      final todaySessions = plan.getSessionsForDate(today);

      expect(todaySessions.length, equals(3));
      expect(todaySessions[0].subject, equals('Motores de Ciclo Otto'));
      expect(todaySessions[1].subject, equals('Legislação'));
      expect(todaySessions[2].subject, equals('Revisão'));
    });

    test('2. Resolução de sessões atrasadas pendentes (overdue)', () {
      final overdue = plan.getOverduePendingSessions(today);

      expect(overdue.length, equals(1));
      expect(overdue.first.sessionId, equals('session_005'));
      expect(overdue.first.subject, equals('Pneumática'));
    });

    test('3. Cálculo de minutos restantes no dia', () {
      final remaining = plan.getTodayRemainingMinutes(today);

      // session_001 (30) + session_002 (20) = 50 min (session_003 concluída)
      expect(remaining, equals(50));
    });

    test('4. Cálculo do progresso total do plano', () {
      // 1 de 5 concluídas = 20%
      expect(plan.totalProgress, equals(0.2));
    });

    test('5. Modificação de status da sessão (copyWith)', () {
      final item = plan.items.first;
      final updated = item.copyWith(
        status: StudySessionStatus.completed,
        correctAnswers: 8,
        incorrectAnswers: 2,
        score: 80.0,
      );

      expect(updated.isCompleted, isTrue);
      expect(updated.correctAnswers, equals(8));
      expect(updated.score, equals(80.0));
    });

    test('6. Persistência de progresso em andamento (StudySessionProgress)',
        () {
      final progress = StudySessionProgress(
        sessionId: 'session_001',
        planId: plan.id,
        selectedMode: 'QUIZ',
        status: 'IN_PROGRESS',
        currentItem: 7,
        totalItems: 20,
        correctAnswers: 5,
        incorrectAnswers: 1,
        progressPercentage: 35.0,
        startedAt: DateTime.now().toIso8601String(),
        lastAccessedAt: DateTime.now().toIso8601String(),
      );

      final updatedPlan = plan.copyWith(activeSessionProgress: progress);

      expect(updatedPlan.activeSessionProgress, isNotNull);
      expect(updatedPlan.activeSessionProgress!.currentItem, equals(7));
      expect(updatedPlan.activeSessionProgress!.selectedMode, equals('QUIZ'));
    });

    test('7. Deserialização e Serialização JSON bidirecional robusta', () {
      final json = plan.toJson();
      final recreated = StudyPlan.fromJson(json);

      expect(recreated.id, equals(plan.id));
      expect(recreated.title, equals(plan.title));
      expect(recreated.items.length, equals(plan.items.length));
      expect(recreated.items.first.subject, equals('Motores de Ciclo Otto'));
      expect(recreated.items.first.subtopics, contains('Sistema de ignição'));
      expect(recreated.sourceDocumentIds, contains(101));
    });
  });
}
