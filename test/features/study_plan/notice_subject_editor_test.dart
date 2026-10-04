import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/study_plan/presentation/notice_subject_editor.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_notice_analysis.dart';
void main() {
  testWidgets('edits extracted subject and topics while preserving evidence', (tester) async {
    StudyPlanNoticeSubject? saved;
    const original=StudyPlanNoticeSubject(name:'Direito',topics:['Constitucional'],evidence:'Pagina 20',peso:2,numQuestoes:10);
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:() async { saved=await showDialog<StudyPlanNoticeSubject>(context:context,builder:(_)=>const NoticeSubjectEditor(subject:original)); },child:const Text('Abrir'))))));
    await tester.tap(find.text('Abrir')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first,'Direito publico');
    await tester.enterText(find.byType(TextFormField).last,'Constitucional\nAdministrativo\nConstitucional');
    await tester.tap(find.text('Salvar revisão')); await tester.pumpAndSettle();
    expect(saved!.name,'Direito publico'); expect(saved!.topics,['Constitucional','Administrativo']); expect(saved!.evidence,'Pagina 20');
  });
}
