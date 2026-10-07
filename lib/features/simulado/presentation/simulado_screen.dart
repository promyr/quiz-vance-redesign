import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/quiz/domain/question_model.dart';
import '../domain/exam_clock.dart';
import '../data/simulado_recovery_store.dart';
import '../../../shared/application/account_scoped_preferences.dart';

/// Tela de execução do Simulado — recebe questões e duração já configurados.
///
/// A geração das questões é responsabilidade de [SimuladoConfigScreen].
class SimuladoScreen extends ConsumerStatefulWidget {
  const SimuladoScreen({
    super.key,
    required this.questions,
    required this.durationSeconds,
    this.checkpoint,
  });

  final List<Question> questions;

  /// Duração total em segundos (ex: 3600 = 1h).
  final int durationSeconds;
  final SimuladoCheckpoint? checkpoint;

  @override
  ConsumerState<SimuladoScreen> createState() => _SimuladoScreenState();
}

class _SimuladoScreenState extends ConsumerState<SimuladoScreen>
    with WidgetsBindingObserver {
  final Map<int, String> _answers = {};
  int _currentIndex = 0;
  late int _remainingSeconds;
  Timer? _timer;
  late final ExamClock _clock;
  final _recovery = SimuladoRecoveryStore();
  late final DateTime _startedAt;
  late final String _sessionId;
  late final String? _account;
  bool _finishing = false;
  bool _exitDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _account = AccountScopedPreferences.instance.activeAccountId;
    _startedAt = widget.checkpoint?.startedAt ?? DateTime.now();
    _sessionId =
        widget.checkpoint?.sessionId ?? '${_startedAt.microsecondsSinceEpoch}';
    _answers.addAll(widget.checkpoint?.answers ?? {});
    _currentIndex = widget.checkpoint?.currentIndex ?? 0;
    _clock = ExamClock(
      durationSeconds: widget.durationSeconds,
      startedAt: _startedAt,
    );
    _remainingSeconds = _clock.remainingSecondsAt(DateTime.now());
    unawaited(_saveAttempt().catchError((Object _) {}));
    _startTimer();
    if (_remainingSeconds == 0 || widget.checkpoint?.completedAt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileClock();
    }
    if (state == AppLifecycleState.paused) {
      unawaited(_saveAttempt().catchError((Object _) {}));
    }
  }

  Future<void> _saveAttempt() async {
    if (_finishing ||
        _account != AccountScopedPreferences.instance.activeAccountId) {
      return;
    }
    await _recovery.save(_checkpoint());
  }

  SimuladoCheckpoint _checkpoint({DateTime? completedAt}) => SimuladoCheckpoint(
      sessionId: _sessionId,
      questions: widget.questions,
      durationSeconds: widget.durationSeconds,
      startedAt: _startedAt,
      completedAt: completedAt ?? widget.checkpoint?.completedAt,
      currentIndex: _currentIndex,
      answers: Map.of(_answers));

  void _moveTo(int index) {
    setState(() => _currentIndex = index);
    unawaited(_saveAttempt().catchError((Object _) {}));
  }

  void _answer(String id) {
    setState(() => _answers[_currentIndex] = id);
    unawaited(_saveAttempt().catchError((Object _) {}));
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Guard: widget pode ter sido desmontado entre ticks
      if (!mounted) return;
      _reconcileClock();
      if (_remainingSeconds == 0) {
        _finish();
      }
    });
  }

  void _reconcileClock() {
    if (!mounted) return;
    final remaining = _clock.remainingSecondsAt(DateTime.now());
    if (remaining != _remainingSeconds) {
      setState(() => _remainingSeconds = remaining);
    }
  }

  void _finish() {
    if (_finishing ||
        _account != AccountScopedPreferences.instance.activeAccountId) {
      return;
    }
    _finishing = true;
    _timer?.cancel();
    final completedAt = widget.checkpoint?.completedAt ?? DateTime.now();
    unawaited(_recovery
        .save(_checkpoint(completedAt: completedAt))
        .catchError((Object _) {}));
    // Guard: evita navegar após widget desmontado (ex: usuário saiu enquanto timer corria)
    if (!mounted) return;
    final questions = widget.questions;
    int correct = 0;
    final answers = <QuestionAnswer>[];
    for (var i = 0; i < questions.length; i++) {
      final selected = _answers[i];
      final isCorrect = selected == questions[i].correctOptionId;
      if (isCorrect) correct++;
      answers.add(QuestionAnswer(
          question: questions[i],
          selectedOptionId: selected,
          isCorrect: isCorrect));
    }
    final result = QuizResult(
      sessionId: _sessionId,
      total: questions.length,
      correct: correct,
      xpEarned: correct * 5,
      timeTaken: Duration(seconds: _clock.elapsedSecondsAt(completedAt)),
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
    if (_exitDialogOpen || _finishing) return;
    _exitDialogOpen = true;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sair do simulado?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: const Text(
            'Sua tentativa ficará salva para retomar. O prazo do simulado continua contando.',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Continuar',
                style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _saveAttempt();
                if (!mounted || !dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                context.go('/simulado');
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Não foi possível salvar a tentativa. Continue no simulado e tente novamente.'),
                  ));
                }
              }
            },
            child: Text('Sair', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    ).whenComplete(() => _exitDialogOpen = false);
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
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final q = questions[_currentIndex];
    final answered = _answers[_currentIndex];
    final progress = (_currentIndex + 1) / questions.length;
    final isTimeLow = _remainingSeconds < 300;

    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _confirmExit();
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(children: [
              // ── Header ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Row(children: [
                  Semantics(
                    button: true,
                    label: 'Sair do simulado',
                    child: GestureDetector(
                      onTap: _confirmExit,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Center(
                            child: Text('✕',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppColors.border,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.success),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${_currentIndex + 1}/${questions.length}',
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Semantics(
                    label: 'Tempo restante: $_timeLabel',
                    liveRegion: isTimeLow,
                    child: AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: isTimeLow
                            ? AppColors.accent.withOpacity(0.15)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isTimeLow
                                ? AppColors.accent
                                : AppColors.border),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.timer_rounded,
                            color: isTimeLow
                                ? AppColors.accent
                                : AppColors.textMuted,
                            size: 12),
                        const SizedBox(width: 3),
                        Text(_timeLabel,
                            style: TextStyle(
                              color: isTimeLow
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            )),
                      ]),
                    ),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                                color: AppColors.primary.withOpacity(0.3)),
                          ),
                          child: Text(q.topic!,
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      const SizedBox(height: 12),
                      Text(q.text,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  height: 1.55))
                          .animate()
                          .fadeIn(duration: 300.ms),
                      const SizedBox(height: 18),
                      ...q.options.asMap().entries.map((e) {
                        final opt = e.value;
                        final isSelected = answered == opt.id;
                        final letter = String.fromCharCode(65 + e.key);
                        return GestureDetector(
                          onTap: () => _answer(opt.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withOpacity(0.10)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: isSelected ? 2 : 1),
                            ),
                            child: Row(children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.surface2,
                                  border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.border),
                                ),
                                child: Center(
                                    child: Text(letter,
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : AppColors.textMuted,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(opt.text,
                                      style: TextStyle(
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.textPrimary,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
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
                      onTap: () => _moveTo(_currentIndex - 1),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border)),
                        child: const Center(
                            child: Text('←',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 18))),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: _currentIndex + 1 < questions.length
                        ? GestureDetector(
                            onTap: () => _moveTo(_currentIndex + 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Center(
                                  child: Text('Próxima →',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800))),
                            ),
                          )
                        : GestureDetector(
                            onTap: _finish,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                gradient: AppColors.successGradient,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          AppColors.success.withOpacity(0.35),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6))
                                ],
                              ),
                              child: const Center(
                                  child: Text('Finalizar Simulado ✓',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800))),
                            ),
                          ),
                  ),
                ]),
              ),
            ]),
          ),
        ));
  }
}
