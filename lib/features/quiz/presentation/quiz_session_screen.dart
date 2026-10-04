import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/local_storage.dart';
import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/exceptions/provider_rate_limit_exception.dart';
import '../../../core/exceptions/premium_limit_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/floating_xp_overlay.dart';
import '../../error_notebook/providers/error_notebook_provider.dart';
import '../../study_plan/application/study_plan_coordinator.dart';
import '../../study_plan/data/study_plan_repository.dart';
import '../../study_plan/domain/study_plan_model.dart';
import '../data/quiz_repository.dart';
import '../domain/question_model.dart';
import '../domain/quiz_generation_params.dart';
import '../../../core/content/relevant_study_material.dart';
import '../../../shared/application/account_scoped_preferences.dart';
import '../data/quiz_recovery_store.dart';

export '../domain/quiz_generation_params.dart';

part 'quiz_session_sections.dart';
part 'quiz_session_initial_generation.dart';
part 'quiz_session_recovery.dart';

class QuizSessionScreen extends ConsumerStatefulWidget {
  const QuizSessionScreen({
    super.key,
    required this.questions,
    this.generationParams,
    this.infiniteMode = false,
    this.isErrorRevisionMode = false,
    this.recoveryKey,
  });

  /// Questões iniciais carregadas pela tela de configuração.
  final List<Question> questions;
  final String? recoveryKey;

  /// Parâmetros para buscar mais questões (obrigatório no modo infinito).
  final QuizGenerationParams? generationParams;

  /// Quando true, ativa o modo infinito com prefetch automático.
  final bool infiniteMode;

  /// Quando true, ativa o modo de revisão do Caderno de Erros.
  final bool isErrorRevisionMode;

  @override
  ConsumerState<QuizSessionScreen> createState() => _QuizSessionScreenState();
}

class _QuizSessionScreenState extends ConsumerState<QuizSessionScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  String? _selectedOptionId;
  bool _answered = false;
  bool _finishing = false;
  final List<QuestionAnswer> _answers = [];
  late final Stopwatch _stopwatch;
  Timer? _timer;
  int _elapsed = 0;

  /// Lista dinâmica de questões (cresce no modo infinito).
  late final List<Question> _questions;

  /// Controle de prefetch para evitar chamadas duplicadas.
  bool _isFetching = false;
  bool _fetchFailed = false;
  bool _showFloatingXp = false;
  bool _zenMode = false;
  bool _loadingInitial = false;
  String? _initialError;
  String? _preparedContent;
  bool _contentPrepared = false;
  int _restoredSeconds = 0;
  bool _restoring = true;
  late final String? _sessionAccount;
  final _recoveryStore = QuizRecoveryStore();

  /// Tamanho do batch para prefetch.
  static const _batchSize = 5;

  /// Posição dentro do batch que dispara o prefetch (4ª questão = índice 3).
  static const _prefetchTrigger = 3;

  @override
  void initState() {
    super.initState();
    _questions = List<Question>.from(widget.questions);
    _stopwatch = Stopwatch();
    _sessionAccount = AccountScopedPreferences.instance.activeAccountId;
    WidgetsBinding.instance.addObserver(this);
    _loadingInitial = _questions.isEmpty && widget.generationParams != null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreOrStart());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Usa o Stopwatch como fonte de verdade — não acumula drift quando o
      // app vai para background e o timer continua contando sozinho.
      if (mounted) {
        setState(
            () => _elapsed = _restoredSeconds + _stopwatch.elapsed.inSeconds);
        if (_elapsed > 0 && _elapsed % 15 == 0) _saveSessionLocally();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _saveSessionLocally();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  void _updateQuizState(VoidCallback update) {
    if (mounted) setState(update);
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

      if (mounted && _sameAccount && newQuestions.isNotEmpty) {
        setState(() {
          _questions.addAll(newQuestions);
          _isFetching = false;
        });
        _saveSessionLocally();
      } else if (mounted) {
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
    final isCorrect = optionId == _current.correctOptionId;
    if (isCorrect) {
      HapticFeedback.lightImpact();
      _showFloatingXp = true;
      if (widget.isErrorRevisionMode) {
        ref
            .read(errorNotebookNotifierProvider.notifier)
            .markQuestionMastered(_current.id);
      }
    } else {
      HapticFeedback.mediumImpact();
    }

    setState(() {
      _selectedOptionId = optionId;
      _answered = true;
    });

    _saveSessionLocally();

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
      _saveSessionLocally();
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz({bool completed = true}) async {
    if (_finishing) return;
    _finishing = true;
    await _recoveryStore.clear(_recoveryKey).catchError((Object _) {});
    try {
      unawaited(LocalStorage.instance
          .clearActiveQuizSession('quiz_session_current')
          .catchError((Object _) {}));
    } catch (_) {}

    // Registra a resposta atual se ainda não foi adicionada.
    if (_answered && _answers.length <= _currentIndex) {
      _answers.add(QuestionAnswer(
        question: _current,
        selectedOptionId: _selectedOptionId,
        isCorrect: _selectedOptionId == _current.correctOptionId,
      ));
    }

    final correct = _answers.where((a) => a.isCorrect).length;

    // Só a sessão explicitamente iniciada pelo plano recebe este resultado.
    final params = widget.generationParams;
    if (completed && params?.planId != null && params?.studySessionId != null) {
      await _recordStudySessionResult(correct: correct);
    }

    if (!mounted) return;
    final resultExtra = <String, dynamic>{
      'result': QuizResult(
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        total: _answers.length,
        correct: correct,
        xpEarned: correct * 10,
        timeTaken:
            Duration(seconds: _restoredSeconds + _stopwatch.elapsed.inSeconds),
        answers: _answers,
        topic: widget.generationParams?.topic,
      ),
    };
    if (params?.planId != null) {
      resultExtra['studyPlanId'] = params!.planId;
      context.pushReplacementNamed('quizResult', extra: resultExtra);
    } else {
      context.goNamed('quizResult', extra: resultExtra);
    }
  }

  String _formatElapsed() {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_questions.isEmpty && widget.generationParams != null) {
      return _buildInitialQuizState();
    }
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
    final answeredCorrectly = _selectedOptionId == _current.correctOptionId;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _showExitConfirmation();
      },
      child: Scaffold(
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
                    Semantics(
                      button: true,
                      label: 'Voltar e fechar quiz',
                      child: GestureDetector(
                        onTap: () => _showExitConfirmation(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                              child: Text('←',
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 18))),
                        ),
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
                    // XP chip com animação flutuante
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.xpGold.withOpacity(0.15),
                            border: Border.all(
                                color: AppColors.xpGold.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text('+${answeredCount * 10} XP',
                              style: const TextStyle(
                                  color: AppColors.xpGold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (_showFloatingXp)
                          Positioned(
                            top: -10,
                            right: 0,
                            child: FloatingXpAnimation(
                              xp: 10,
                              onComplete: () {
                                if (mounted) {
                                  setState(() => _showFloatingXp = false);
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Botão Modo Zen
                    IconButton(
                      icon: Icon(
                        _zenMode
                            ? Icons.self_improvement_rounded
                            : Icons.spa_outlined,
                        color:
                            _zenMode ? AppColors.success : AppColors.textMuted,
                        size: 20,
                      ),
                      tooltip: _zenMode
                          ? 'Desativar Modo Zen'
                          : 'Ativar Modo Zen (Foco)',
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() => _zenMode = !_zenMode);
                      },
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
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
                      // Header da pergunta: Categoria e Botão de Áudio (TTS)
                      Row(
                        children: [
                          if (_current.topic != null)
                            Flexible(
                                child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.15),
                                border: Border.all(
                                    color: AppColors.primary.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                  '${_getTopicIcon(_current.topic!)} ${_current.topic!}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            )),
                          const Spacer(),
                          Semantics(
                            button: true,
                            label: 'Ouvir enunciado da questão por áudio',
                            child: IconButton(
                              icon: const Icon(
                                Icons.volume_up_rounded,
                                color: AppColors.primaryLight,
                                size: 20,
                              ),
                              tooltip: 'Ouvir enunciado da questão',
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Leitura por voz ativada para este enunciado.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ],
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
                          borderColor = AppColors.error;
                          bgColor = AppColors.error.withOpacity(0.12);
                          letterBg = AppColors.error;
                          letterColor = Colors.white;
                          textColor = AppColors.error;
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
                                      color: AppColors.error, size: 18),
                              ],
                            ),
                          )
                              .animate(delay: (e.key * 60).ms)
                              .fadeIn()
                              .slideX(begin: 0.05),
                        );
                      }),

                      // Explicação do Assunto & Gabarito Comentado
                      if (_answered)
                        Container(
                          margin: const EdgeInsets.only(top: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: answeredCorrectly
                                ? AppColors.success.withOpacity(0.08)
                                : AppColors.primary.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: answeredCorrectly
                                  ? AppColors.success.withOpacity(0.35)
                                  : AppColors.primary.withOpacity(0.30),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: answeredCorrectly
                                          ? AppColors.success.withOpacity(0.16)
                                          : AppColors.primary.withOpacity(0.16),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      answeredCorrectly
                                          ? Icons.check_circle_rounded
                                          : Icons.lightbulb_rounded,
                                      color: answeredCorrectly
                                          ? AppColors.success
                                          : AppColors.primary,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      answeredCorrectly
                                          ? 'Você acertou! Explicação do Assunto'
                                          : 'Gabarito Comentado & Explicação do Assunto',
                                      style: TextStyle(
                                        color: answeredCorrectly
                                            ? AppColors.success
                                            : AppColors.primary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_current.topic != null &&
                                  _current.topic!.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Text(
                                    _current.topic!,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              if (correctOption != null) ...[
                                Text(
                                  correctOptionLetter == null
                                      ? 'Resposta correta: ${correctOption.text}'
                                      : 'Resposta correta: Letra $correctOptionLetter • ${correctOption.text}',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              Text(
                                _current.getEffectiveExplanation(
                                    widget.generationParams?.topic),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  height: 1.5,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(),

                      // 📚 Referência na Apostila
                      if (_answered && (_current.source?.hasData ?? false))
                        _SourceReferenceCard(source: _current.source!)
                            .animate(delay: 80.ms)
                            .fadeIn(),

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
      ),
    );
  }

  // ── Diálogo de confirmação ao sair ──────────────────────────────

  void _showExitConfirmation() {
    if (_answers.isEmpty && !_answered) {
      _saveSessionLocally();
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
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
              ? 'Você respondeu ${_answers.length} questões. Deseja ver seu resultado ou continuar praticando?'
              : 'As questões respondidas serão salvas. Deseja encerrar este quiz?',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveSessionLocally();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
            child: const Text('Pausar e sair'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continuar',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          if (_isInfinite && (_answers.isNotEmpty || _answered))
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
              _finishQuiz(completed: false);
            },
            child:
                const Text('Sair', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }
}
