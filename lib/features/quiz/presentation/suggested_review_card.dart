import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../error_notebook/providers/error_notebook_provider.dart';
import '../../error_notebook/domain/review_suggestion.dart';

class SuggestedReviewCard extends ConsumerWidget {
  const SuggestedReviewCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestion = suggestErrorReview(
        ref.watch(errorNotebookNotifierProvider).valueOrNull ?? []);
    if (suggestion == null) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sugestão de revisão',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                          '${suggestion.topic}: ${suggestion.questions.length} questões com erros ainda pendentes.'),
                      TextButton.icon(
                          onPressed: () => context.pushNamed('quizSession',
                                  extra: {
                                    'questions': suggestion.questions,
                                    'isErrorRevisionMode': true
                                  }),
                          icon: const Icon(Icons.replay),
                          label: const Text('Revisar agora')),
                    ]))));
  }
}
