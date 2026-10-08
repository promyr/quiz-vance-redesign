import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_model.dart';

void main() {
  final today = DateTime(2026, 10, 8);
  StudyPlan plan(StudyPlanItem item) =>
      StudyPlan(objetivo: 'Plano legado', tempoDiario: 30, items: [item]);
  StudyPlanItem item({DateTime? completedAt, bool done = true}) =>
      StudyPlanItem(
          dia: 'Quinta',
          tema: 'Terminais',
          atividade: 'Quiz',
          duracaoMin: 30,
          prioridade: 1,
          concluido: done,
          completedAt: completedAt);

  test('conclusão da quinta anterior não volta como concluída hoje', () {
    final old = item(completedAt: DateTime(2026, 10, 1));
    final p = plan(old);
    expect(p.getSessionsForDate(today), isEmpty);
    expect(p.items.single.isCompleted, isTrue);
    expect(p.totalProgress, 1);
  });
  test('conclusão sem data não é atribuída a hoje', () {
    expect(plan(item()).getSessionsForDate(today), isEmpty);
  });
  test('conclusão de hoje permanece visível', () {
    expect(
        plan(item(completedAt: today)).getSessionsForDate(today), hasLength(1));
  });
  test('sessão recorrente pendente continua disponível', () {
    final p = plan(item(done: false));
    expect(p.getSessionsForDate(today), hasLength(1));
    expect(p.getTodayRemainingMinutes(today), 30);
  });
}
