import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/error_notebook/domain/error_question.dart';
import 'package:quiz_vance_flutter/features/error_notebook/domain/review_suggestion.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
void main() {
  test('prioritizes repeated errors and excludes mastered questions', () {
    ErrorQuestion error(String id,String topic,int count,{bool mastered=false})=>ErrorQuestion(id:id,topic:topic,question:Question(id:id,text:id,options:const [],correctOptionId:'a'),failedAt:DateTime(2026,10,4),timesFailed:count,isMastered:mastered);
    final suggestion=suggestErrorReview([error('a','Portugues',1),error('b','Direito',3),error('c','Direito',2),error('d','Matematica',20,mastered:true)]);
    expect(suggestion!.topic,'Direito'); expect(suggestion.questions.map((q)=>q.id),['b','c']);
    expect(suggestErrorReview([error('d','Matematica',20,mastered:true)]),isNull);
  });
}
