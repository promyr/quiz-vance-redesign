import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/quiz/domain/question_model.dart';
import '../domain/simulado_review.dart';

class SimuladoReviewScreen extends StatefulWidget {
  const SimuladoReviewScreen({super.key, required this.result});

  final QuizResult? result;

  @override
  State<SimuladoReviewScreen> createState() => _SimuladoReviewScreenState();
}

class _SimuladoReviewScreenState extends State<SimuladoReviewScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    if (result == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/simulado');
      });
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final wrongAnswers = reviewableSimuladoAnswers(result);
    if (wrongAnswers.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 68,
                  color: AppColors.success,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nenhum erro para revisar',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Você acertou todas as questões deste simulado.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                _ActionButton(
                  label: 'Voltar ao resultado',
                  onTap: () => context.pop(),
                  primary: true,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_currentIndex >= wrongAnswers.length) {
      _currentIndex = wrongAnswers.length - 1;
    }

    final answer = wrongAnswers[_currentIndex];
    final question = answer.question;
    final selectedOption = _findOptionById(question, answer.selectedOptionId);
    final selectedOptionLetter =
        _findOptionLetterById(question, answer.selectedOptionId);
    final correctOption = question.correctOption;
    final correctOptionLetter = question.correctOptionLetter;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Revisão dos erros',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_currentIndex + 1} / ${wrongAnswers.length}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (question.topic != null &&
                        question.topic!.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.28),
                          ),
                        ),
                        child: Text(
                          question.topic!,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const Text(
                      'Questão que você errou',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      question.text,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ...question.options.asMap().entries.map((entry) {
                      final option = entry.value;
                      final letter = String.fromCharCode(65 + entry.key);
                      final isSelected = option.id == answer.selectedOptionId;
                      final isCorrect = option.id == question.correctOptionId;

                      var borderColor = AppColors.border;
                      var backgroundColor = AppColors.surface;
                      var badgeColor = AppColors.surface2;
                      var badgeTextColor = AppColors.textMuted;
                      var textColor = AppColors.textPrimary;
                      String? trailingLabel;

                      if (isCorrect) {
                        borderColor = AppColors.success;
                        backgroundColor = AppColors.success.withOpacity(0.12);
                        badgeColor = AppColors.success;
                        badgeTextColor = Colors.white;
                        textColor = AppColors.success;
                        trailingLabel = 'Correta';
                      } else if (isSelected) {
                        borderColor = AppColors.accent;
                        backgroundColor = AppColors.accent.withOpacity(0.12);
                        badgeColor = AppColors.accent;
                        badgeTextColor = Colors.white;
                        textColor = AppColors.accent;
                        trailingLabel = 'Sua resposta';
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  letter,
                                  style: TextStyle(
                                    color: badgeTextColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.text,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 13,
                                      fontWeight: isCorrect || isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      height: 1.45,
                                    ),
                                  ),
                                  if (trailingLabel != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      trailingLabel,
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    _AnswerSummaryCard(
                      title: 'Você marcou',
                      label: selectedOption == null
                          ? 'Sem resposta'
                          : selectedOptionLetter == null
                              ? selectedOption.text
                              : '$selectedOptionLetter • ${selectedOption.text}',
                      color: selectedOption == null
                          ? AppColors.textMuted
                          : AppColors.accent,
                    ),
                    const SizedBox(height: 10),
                    _AnswerSummaryCard(
                      title: 'Resposta correta',
                      label: correctOption == null
                          ? 'Não informada'
                          : correctOptionLetter == null
                              ? correctOption.text
                              : '$correctOptionLetter • ${correctOption.text}',
                      color: AppColors.success,
                    ),
                    if (question.explanation != null &&
                        question.explanation!.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Explicação',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              question.explanation!,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
              child: Row(
                children: [
                  if (_currentIndex > 0) ...[
                    Expanded(
                      child: _ActionButton(
                        label: 'Anterior',
                        onTap: () => setState(() => _currentIndex--),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: _currentIndex > 0 ? 1 : 2,
                    child: _ActionButton(
                      label: _currentIndex + 1 < wrongAnswers.length
                          ? 'Próximo erro'
                          : 'Voltar ao resultado',
                      onTap: () {
                        if (_currentIndex + 1 < wrongAnswers.length) {
                          setState(() => _currentIndex++);
                          return;
                        }
                        context.pop();
                      },
                      primary: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

QuizOption? _findOptionById(Question question, String? optionId) {
  if (optionId == null) return null;
  for (final option in question.options) {
    if (option.id == optionId) {
      return option;
    }
  }
  return null;
}

String? _findOptionLetterById(Question question, String? optionId) {
  if (optionId == null) return null;
  final index = question.options.indexWhere((option) => option.id == optionId);
  if (index < 0) return null;
  return String.fromCharCode(65 + index);
}

class _AnswerSummaryCard extends StatelessWidget {
  const _AnswerSummaryCard({
    required this.title,
    required this.label,
    required this.color,
  });

  final String title;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: primary ? AppColors.primaryGradient : null,
          color: primary ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: primary ? null : Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: primary ? Colors.white : AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
