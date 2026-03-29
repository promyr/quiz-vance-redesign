import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/quiz/domain/question_model.dart';

/// Tela de execução do Simulado — recebe questões e duração já configurados.
///
/// A geração das questões é responsabilidade de [SimuladoConfigScreen].
class SimuladoScreen extends ConsumerStatefulWidget {
  const SimuladoScreen({
    super.key,
    required this.questions,
    required this.durationSeconds,
  });

  final List<Question> questions;

  /// Duração total em segundos (ex: 3600 = 1h).
  final int durationSeconds;

  @override
  ConsumerState<SimuladoScreen> createState() => _SimuladoScreenState();
}

class _SimuladoScreenState extends ConsumerState<SimuladoScreen> {
  final Map<int, String> _answers = {};
  int _currentIndex = 0;
  late int _remainingSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.durationSeconds;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Guard: widget pode ter sido desmontado entre ticks
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        _finish();
      }
    });
  }

  void _finish() {
    _timer?.cancel();
    // Guard: evita navegar após widget desmontado (ex: usuário saiu enquanto timer corria)
    if (!mounted) return;
    final questions = widget.questions;
    int correct = 0;
    final answers = <QuestionAnswer>[];
    for (var i = 0; i < questions.length; i++) {
      final selected = _answers[i];
      final isCorrect = selected == questions[i].correctOptionId;
      if (isCorrect) correct++;
      answers.add(QuestionAnswer(question: questions[i], selectedOptionId: selected, isCorrect: isCorrect));
    }
    final result = QuizResult(
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      total: questions.length,
      correct: correct,
      xpEarned: correct * 5,
      timeTaken: Duration(seconds: widget.durationSeconds - _remainingSeconds),
      answers: answers,
    );
    context.goNamed('simuladoResult', extra: {'result': result});
  }

  String get _timeLabel {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sair do simulado?',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: const Text('Seu progresso será perdido.',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continuar', style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () { Navigator.pop(context); context.go('/'); },
            child: Text('Sair', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.questions;

    // Guard: lista vazia não deve chegar aqui, mas evita divisão por zero e crash
    if (questions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final q = questions[_currentIndex];
    final answered = _answers[_currentIndex];
    final progress = (_currentIndex + 1) / questions.length;
    final isTimeLow = _remainingSeconds < 300;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Row(children: [
              GestureDetector(
                onTap: _confirmExit,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
                  child: const Center(child: Text('✕', style: TextStyle(color: AppColors.textPrimary, fontSize: 14))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(AppColors.success),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${_currentIndex + 1}/${questions.length}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: isTimeLow ? AppColors.accent.withOpacity(0.15) : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isTimeLow ? AppColors.accent : AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timer_rounded, color: isTimeLow ? AppColors.accent : AppColors.textMuted, size: 12),
                  const SizedBox(width: 3),
                  Text(_timeLabel, style: TextStyle(
                    color: isTimeLow ? AppColors.accent : AppColors.textMuted,
                    fontWeight: FontWeight.w700, fontSize: 12,
                  )),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Questão ──────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (q.topic != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      ),
                      child: Text(q.topic!, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  const SizedBox(height: 12),
                  Text(q.text,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600, height: 1.55)
                  ).animate().fadeIn(duration: 300.ms),
                  const SizedBox(height: 18),
                  ...q.options.asMap().entries.map((e) {
                    final opt = e.value;
                    final isSelected = answered == opt.id;
                    final letter = String.fromCharCode(65 + e.key);
                    return GestureDetector(
                      onTap: () => setState(() => _answers[_currentIndex] = opt.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withOpacity(0.10) : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 2 : 1),
                        ),
                        child: Row(children: [
                          Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: isSelected ? AppColors.primary : AppColors.surface2,
                              border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                            ),
                            child: Center(child: Text(letter, style: TextStyle(
                              color: isSelected ? Colors.white : AppColors.textMuted,
                              fontWeight: FontWeight.w700, fontSize: 12,
                            ))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(opt.text, style: TextStyle(
                            color: isSelected ? AppColors.primary : AppColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            fontSize: 13,
                          ))),
                        ]),
                      ).animate(delay: (e.key * 50).ms).fadeIn(),
                    );
                  }),
                ],
              ),
            ),
          ),

          // ── Navegação ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
            child: Row(children: [
              if (_currentIndex > 0) ...[
                GestureDetector(
                  onTap: () => setState(() => _currentIndex--),
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                    child: const Center(child: Text('←', style: TextStyle(color: AppColors.textPrimary, fontSize: 18))),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _currentIndex + 1 < questions.length
                    ? GestureDetector(
                        onTap: () => setState(() => _currentIndex++),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
                          child: const Center(child: Text('Próxima →', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800))),
                        ),
                      )
                    : GestureDetector(
                        onTap: _finish,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: AppColors.successGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: AppColors.success.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 6))],
                          ),
                          child: const Center(child: Text('Finalizar Simulado ✓', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800))),
                        ),
                      ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
