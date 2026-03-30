import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';

void main() {
  group('QuizOption', () {
    test('fromJson creates QuizOption with correct properties', () {
      final json = {
        'id': 'opt_1',
        'text': 'Option A',
        'is_correct': true,
      };

      final option = QuizOption.fromJson(json);

      expect(option.id, equals('opt_1'));
      expect(option.text, equals('Option A'));
      expect(option.isCorrect, equals(true));
    });

    test('fromJson defaults is_correct to false when missing', () {
      final json = {
        'id': 'opt_2',
        'text': 'Option B',
      };

      final option = QuizOption.fromJson(json);

      expect(option.isCorrect, equals(false));
    });

    test('toJson serializes correctly', () {
      const option = QuizOption(
        id: 'opt_3',
        text: 'Option C',
        isCorrect: false,
      );

      final json = option.toJson();

      expect(json['id'], equals('opt_3'));
      expect(json['text'], equals('Option C'));
      expect(json['is_correct'], equals(false));
    });
  });

  group('Question', () {
    test('fromJson creates Question with all properties', () {
      final json = {
        'id': 'q_1',
        'text': 'What is 2+2?',
        'options': [
          {'id': 'opt_1', 'text': '3', 'is_correct': false},
          {'id': 'opt_2', 'text': '4', 'is_correct': true},
        ],
        'correct_option_id': 'opt_2',
        'explanation': 'Two plus two equals four',
        'topic': 'Math',
        'difficulty': 'easy',
      };

      final question = Question.fromJson(json);

      expect(question.id, equals('q_1'));
      expect(question.text, equals('What is 2+2?'));
      expect(question.options, hasLength(2));
      expect(question.correctOptionId, equals('opt_2'));
      expect(question.explanation, equals('Two plus two equals four'));
      expect(question.topic, equals('Math'));
      expect(question.difficulty, equals('easy'));
    });

    test('fromJson defaults difficulty to medium when missing', () {
      final json = {
        'id': 'q_2',
        'text': 'Question?',
        'options': [],
        'correct_option_id': 'opt_1',
      };

      final question = Question.fromJson(json);

      expect(question.difficulty, equals('medium'));
    });

    test('fromJson handles alternative field names', () {
      final json = {
        'id': 'q_3',
        'question': 'Alternative question field?',
        'options': [],
        'correct_answer': 'opt_1',
      };

      final question = Question.fromJson(json);

      expect(question.text, equals('Alternative question field?'));
      expect(question.correctOptionId, equals('opt_1'));
    });

    test('fromJson resolves correct answer when backend sends option letter',
        () {
      final json = {
        'id': 'q_letter',
        'text': 'Pergunta',
        'options': [
          {'id': 'opt_1', 'text': 'Opcao A', 'is_correct': false},
          {'id': 'opt_2', 'text': 'Opcao B', 'is_correct': false},
        ],
        'correct_answer': 'B',
      };

      final question = Question.fromJson(json);

      expect(question.correctOptionId, equals('opt_2'));
      expect(question.correctOption?.text, equals('Opcao B'));
      expect(question.correctOptionLetter, equals('B'));
    });

    test('fromJson resolves correct answer when backend sends option text', () {
      final json = {
        'id': 'q_text',
        'text': 'Pergunta',
        'options': [
          {'id': 'a', 'text': 'Aprender a investir em acoes'},
          {
            'id': 'b',
            'text': 'Gerenciar o orcamento pessoal e familiar',
          },
        ],
        'correct_answer': 'Gerenciar o orcamento pessoal e familiar',
      };

      final question = Question.fromJson(json);

      expect(question.correctOptionId, equals('b'));
      expect(
        question.correctOption?.text,
        equals('Gerenciar o orcamento pessoal e familiar'),
      );
    });

    test('fromJson falls back to option flagged with is_correct', () {
      final json = {
        'id': 'q_flagged',
        'text': 'Pergunta',
        'options': [
          {'id': 'a', 'text': 'Errada', 'is_correct': false},
          {'id': 'b', 'text': 'Certa', 'is_correct': true},
        ],
        'correct_answer': 'payload-inconsistente',
      };

      final question = Question.fromJson(json);

      expect(question.correctOptionId, equals('b'));
      expect(question.correctOption?.text, equals('Certa'));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'q_4',
        'text': 'Question?',
        'options': [],
        'correct_option_id': 'opt_1',
      };

      final question = Question.fromJson(json);

      expect(question.explanation, isNull);
      expect(question.topic, isNull);
    });
  });

  group('QuizResult', () {
    test('accuracy calculation is correct', () {
      const result = QuizResult(
        sessionId: 'sess_1',
        total: 10,
        correct: 8,
        xpEarned: 80,
        timeTaken: Duration(minutes: 5),
        answers: [],
      );

      expect(result.accuracy, equals(0.8));
    });

    test('accuracy is 0.0 when total is 0', () {
      const result = QuizResult(
        sessionId: 'sess_2',
        total: 0,
        correct: 0,
        xpEarned: 0,
        timeTaken: Duration.zero,
        answers: [],
      );

      expect(result.accuracy, equals(0.0));
    });

    test('accuracy is 1.0 for perfect score', () {
      const result = QuizResult(
        sessionId: 'sess_3',
        total: 5,
        correct: 5,
        xpEarned: 50,
        timeTaken: Duration(minutes: 3),
        answers: [],
      );

      expect(result.accuracy, equals(1.0));
    });

    test('QuizResult creation with all fields', () {
      const result = QuizResult(
        sessionId: 'sess_4',
        total: 20,
        correct: 16,
        xpEarned: 160,
        timeTaken: Duration(minutes: 10),
        answers: [],
        topic: 'History',
      );

      expect(result.sessionId, equals('sess_4'));
      expect(result.total, equals(20));
      expect(result.correct, equals(16));
      expect(result.xpEarned, equals(160));
      expect(result.topic, equals('History'));
    });
  });
}
