import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/account_session_epoch_provider.dart';
import '../data/quiz_recovery_store.dart';
import '../domain/question_model.dart';
import '../domain/quiz_generation_params.dart';

final _pausedQuizProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) {
  ref.watch(accountSessionEpochProvider);
  return QuizRecoveryStore().latest();
});

class ResumeQuizCard extends ConsumerWidget {
  const ResumeQuizCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(_pausedQuizProvider).valueOrNull;
    if (entry == null) return const SizedBox.shrink();
    try {
      final data = entry['data'] as Map<String, dynamic>;
      final questions = (data['questions'] as List)
          .map((q) => Question.fromJson(Map<String, dynamic>.from(q as Map)))
          .toList();
      if (questions.isEmpty || questions.any((q) => q.correctOption == null)) {
        return const SizedBox.shrink();
      }
      final rawParams = data['params'];
      final params = rawParams is Map
          ? QuizGenerationParams.fromJson(Map<String, dynamic>.from(rawParams))
          : null;
      return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Retomar quiz pausado'),
            onPressed: () async {
              await context.pushNamed('quizSession', extra: {
                'questions': questions,
                'generationParams': params,
                'infiniteMode': data['infinite'] == true,
                'isErrorRevisionMode': data['revision'] == true,
                'recoveryKey': entry['key']
              });
              if (context.mounted) ref.invalidate(_pausedQuizProvider);
            },
          ));
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}
