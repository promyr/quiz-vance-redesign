import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../data/quiz_repository.dart';
import '../domain/question_model.dart';

/// Parâmetros de geração para o modo infinito.
class QuizGenerationParams {
  const QuizGenerationParams({
    required this.topic,
    required this.difficulty,
    required this.aiProvider,
    this.conteudo,
  });

  final String topic;
  final String difficulty;
  final String aiProvider;
  final String? conteudo;
}

class QuizSessionScreen extends ConsumerStatefulWidget {
  const QuizSessionScreen({
    super.key,
    required this.questions,
    this.generationParams,
    this.infiniteMode = false,
  });

  /// Questões iniciais carregadas pela tela de configuração.
  final List<Question> questions;

  /// Parâmetros para buscar mais questões (obrigatório no modo infinito).
  final QuizGenerationParams? generationParams;

  /// Quando true, ativa o modo infinito com prefetch automático.
  final bool infiniteMode;

  @override
  ConsumerState<QuizSessionScreen> createState() => _QuizSessionScreenState();
}

class _QuizSessionScreenState extends ConsumerState<QuizSessionScreen> {
  int _currentIndex = 0;
  String? _selectedOptionId;
  bool _answered = false;
  final List<QuestionAnswer> _answers = [];
  late final Stopwatch _stopwatch;
  Timer? _timer;
  int _elapsed = 0;

  /// Lista dinâmica de questões (cresce no modo infinito).
  late final List<Question> _questions;

  /// Controle de prefetch para evitar chamadas duplicadas.
  bool _isFetching = false;
  bool _fetchFailed = false;

  /// Tamanho do batch para prefetch.
  static const _batchSize = 5;

  /// Posição dentro do batch que dispara o prefetch (4ª questão = índice 3).
  static const _prefetchTrigger = 3;

  @override
  void initState() {
    super.initState();
    _questions = List<Question>.from(widget.questions);
    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Usa o Stopwatch como fonte de verdade — não acumula drift quando o
      // app vai para background e o timer continua contando sozinho.
      if (mounted) setState(() => _elapsed = _stopwatch.elapsed.inSeconds);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  Question get _current => _questions[_currentIndex];

  bool get _isInfinite =>
      widget.infiniteMode && widget.generationParams != null;

  /// Verifica se devemos disparar o prefetch com base na posição atual.
  bool get _shouldPrefetch {
    if (!_isInfinite || _isFetching || _fetchFailed) return false;
    // Dispara quando está na posição _prefetchTrigger de qualquer batch.
    // Batch 0: índices 0-4, trigger no 3
    // Batch 1: índices 5-9, trigger no 8
    // Batch N: trigger no (N * _batchSize) + _prefetchTrigger
    return (_currentIndex % _batchSize) == _prefetchTrigger;
  }

  /// Busca mais questões em background.
  Future<void> _prefetchQuestions() async {
    if (_isFetching || _fetchFailed) return;
    final params = widget.generationParams;
    if (params == null) return;

    setState(() => _isFetching = true);

    try {
      final repo = ref.read(quizRepositoryProvider);
      final newQuestions = await repo.generate(
        topic: params.topic,
        difficulty: params.difficulty,
        quantity: _batchSize,
        aiProvider: params.aiProvider,
        conteudo: params.conteudo,
      );

      if (mounted && newQuestions.isNotEmpty) {
        setState(() {
          _questions.addAll(newQuestions);
          _isFetching = false;
        });
      } else {
        setState(() => _isFetching = false);
      }
    } catch (_) {
      // Falha silenciosa — o usuário finaliza o batch atual e vê resultado.
      if (mounted) {
        setState(() {
          _isFetching = false;
          _fetchFailed = true;
        });
      }
    }
  }

  void _selectOption(String optionId) {
    if (_answered) return;
    setState(() {
      _selectedOptionId = optionId;
      _answered = true;
    });

    // Verifica prefetch após responder.
    if (_shouldPrefetch) {
      _prefetchQuestions();
    }
  }

  void _next() {
    _answers.add(QuestionAnswer(
      question: _current,
      selectedOptionId: _selectedOptionId,
      isCorrect: _selectedOptionId == _current.correctOptionId,
    ));

    if (_currentIndex + 1 < _questions.length) {
      setState(() {
        _currentIndex++;
        _selectedOptionId = null;
        _answered = false;
      });
    } else {
      _finishQuiz();
    }
  }

  void _finishQuiz() {
    // Registra a resposta atual se ainda não foi adicionada.
    if (_answered && _answers.length <= _currentIndex) {
      _answers.add(QuestionAnswer(
        question: _current,
        selectedOptionId: _selectedOptionId,
        isCorrect: _selectedOptionId == _current.correctOptionId,
      ));
    }

    final correct = _answers.where((a) => a.isCorrect).length;
    context.goNamed('quizResult', extra: {
      'result': QuizResult(
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        total: _answers.length,
        correct: correct,
        xpEarned: correct * 10,
        timeTaken: _stopwatch.elapsed,
        answers: _answers,
        topic: widget.generationParams?.topic,
      ),
    });
  }

  String _formatElapsed() {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
      return const Scaffold(
        backgroundColor: AppColors.background,
        body:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final total = _questions.length;
    final answeredCount = _currentIndex + 1;
    final correctOption = _current.correctOption;
    final correctOptionLetter = _current.correctOptionLetter;
    final explanation = _current.explanation?.trim();
    final hasExplanation = explanation != null && explanation.isNotEmpty;
    final answeredCorrectly = _selectedOptionId == _current.correctOptionId;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Row(
                children: [
                  // Back button
                  GestureDetector(
                    onTap: () => _showExitConfirmation(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                          child: Text('←',
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 16))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Progress / counter
                  Expanded(
                    child: _isInfinite
                        ? _buildInfiniteProgress(answeredCount)
                        : _buildFixedProgress(answeredCount, total),
                  ),
                  const SizedBox(width: 12),
                  // XP chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.xpGold.withOpacity(0.15),
                      border:
                          Border.all(color: AppColors.xpGold.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text('+${answeredCount * 10} XP',
                        style: const TextStyle(
                            color: AppColors.xpGold,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Pergunta ─────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category badge
                    if (_current.topic != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text('⚖️ ${_current.topic!}',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),

                    const SizedBox(height: 14),

                    // Question text
                    Text(
                      _current.text,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.5),
                    ).animate().fadeIn(duration: 300.ms),

                    const SizedBox(height: 20),

                    // Options
                    ..._current.options.asMap().entries.map((e) {
                      final option = e.value;
                      final isSelected = _selectedOptionId == option.id;
                      // Usa correctOptionId como única fonte de verdade para
                      // evitar inconsistência com o booleano is_correct da opção.
                      final isCorrect =
                          _answered && option.id == _current.correctOptionId;
                      final isWrong = _answered &&
                          isSelected &&
                          option.id != _current.correctOptionId;

                      Color borderColor = AppColors.border;
                      Color bgColor = AppColors.surface;
                      Color letterBg = AppColors.surface2;
                      Color letterColor = AppColors.textMuted;
                      Color textColor = AppColors.textPrimary;

                      if (isCorrect) {
                        borderColor = AppColors.success;
                        bgColor = AppColors.success.withOpacity(0.12);
                        letterBg = AppColors.success;
                        letterColor = Colors.white;
                        textColor = AppColors.success;
                      } else if (isWrong) {
                        borderColor = AppColors.accent;
                        bgColor = AppColors.accent.withOpacity(0.12);
                        letterBg = AppColors.accent;
                        letterColor = Colors.white;
                        textColor = AppColors.accent;
                      } else if (isSelected) {
                        borderColor = AppColors.primary;
                        bgColor = AppColors.primary.withOpacity(0.08);
                        letterBg = AppColors.primary;
                        letterColor = Colors.white;
                      }

                      return GestureDetector(
                        onTap: () => _selectOption(option.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor, width: 2),
                          ),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                    color: letterBg,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Center(
                                  child: Text(
                                    String.fromCharCode(65 + e.key),
                                    style: TextStyle(
                                        color: letterColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(option.text,
                                    style: TextStyle(
                                        color: textColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        height: 1.4)),
                              ),
                              if (isCorrect)
                                const Icon(Icons.check_circle_rounded,
                                    color: AppColors.success, size: 18),
                              if (isWrong)
                                const Icon(Icons.cancel_rounded,
                                    color: AppColors.accent, size: 18),
                            ],
                          ),
                        )
                            .animate(delay: (e.key * 60).ms)
                            .fadeIn()
                            .slideX(begin: 0.05),
                      );
                    }),

                    // Explanation
                    if (_answered && (correctOption != null || hasExplanation))
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: answeredCorrectly
                              ? AppColors.success.withOpacity(0.10)
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: answeredCorrectly
                                ? AppColors.success.withOpacity(0.35)
                                : AppColors.border,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              answeredCorrectly
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.info_outlined,
                              color: answeredCorrectly
                                  ? AppColors.success
                                  : AppColors.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (correctOption != null) ...[
                                    const Text(
                                      'Resposta correta',
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      correctOptionLetter == null
                                          ? correctOption.text
                                          : '$correctOptionLetter • ${correctOption.text}',
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                  if (correctOption != null && hasExplanation)
                                    const SizedBox(height: 10),
                                  if (hasExplanation)
                                    Text(
                                      explanation,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                        height: 1.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(),

                    // Indicador de carregamento de novas questões
                    if (_isFetching)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textMuted,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Carregando mais questões...',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Footer buttons ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
              child: AnimatedOpacity(
                opacity: _answered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: _isInfinite
                    ? _buildInfiniteFooter()
                    : _buildFixedFooter(total),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Progress Widgets ──────────────────────────────────────────────

  Widget _buildFixedProgress(int answeredCount, int total) {
    final progress = answeredCount / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(AppColors.success),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$answeredCount de $total',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildInfiniteProgress(int answeredCount) {
    return Row(
      children: [
        // Ícone de infinito
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: const Text(
            '∞',
            style: TextStyle(
                color: AppColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 10),
        // Contador de questões respondidas
        Text(
          'Questão $answeredCount',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        // Timer
        Text(
          _formatElapsed(),
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── Footer Widgets ────────────────────────────────────────────────

  Widget _buildFixedFooter(int total) {
    final isLast = _currentIndex + 1 >= total;
    return GestureDetector(
      onTap: _answered ? _next : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: AppColors.primary.withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 8))
          ],
        ),
        child: Center(
          child: Text(
            isLast ? 'Ver resultado' : 'Próxima questão',
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  Widget _buildInfiniteFooter() {
    final hasNext = _currentIndex + 1 < _questions.length;
    return Row(
      children: [
        // Botão Finalizar
        Expanded(
          child: GestureDetector(
            onTap: _answered ? _finishQuiz : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Text(
                  'Finalizar',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Botão Próxima
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _answered ? (hasNext ? _next : _finishQuiz) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withOpacity(0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8))
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasNext ? 'Próxima questão' : 'Ver resultado',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800),
                    ),
                    if (_isFetching && !hasNext) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Diálogo de confirmação ao sair ──────────────────────────────

  void _showExitConfirmation() {
    if (_answers.isEmpty && !_answered) {
      context.go('/');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sair do quiz?',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        content: Text(
          _isInfinite
              ? 'Você respondeu ${_answers.length} questões. Deseja ver o resultado ou descartar?'
              : 'Seu progresso será perdido.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continuar',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          if (_isInfinite && _answers.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _finishQuiz();
              },
              child: const Text('Ver resultado',
                  style: TextStyle(color: AppColors.primary)),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/');
            },
            child:
                const Text('Sair', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }
}
