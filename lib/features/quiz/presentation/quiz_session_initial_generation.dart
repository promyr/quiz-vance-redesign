part of 'quiz_session_screen.dart';

extension _InitialQuizGeneration on _QuizSessionScreenState {
  Future<void> _generateInitialQuiz() async {
    final params = widget.generationParams;
    if (!mounted || params == null || !_sameAccount) return;
    _updateQuizState(() {
      _loadingInitial = true;
      _initialError = null;
    });
    try {
      var content = _contentPrepared ? _preparedContent : params.conteudo;
      if (!_contentPrepared && content == null && params.documentId != null) {
        try {
          content = await ref
              .read(studyPlanRepositoryProvider)
              .getDocumentContent(params.documentId!);
        } catch (_) {
          // O tópico do plano continua suficiente quando o PDF está indisponível.
        }
      }
      if (!mounted || !_sameAccount) return;
      if (!_contentPrepared) {
        _preparedContent = content == null
            ? null
            : selectRelevantStudyMaterial(content, params.topic);
        _contentPrepared = content != null || params.documentId == null;
      }
      final questions = await ref.read(quizRepositoryProvider).generate(
            topic: params.topic,
            difficulty: params.difficulty,
            quantity: params.quantity,
            aiProvider: params.aiProvider,
            conteudo: _preparedContent,
            documentId: params.documentId,
          );
      if (!mounted || !_sameAccount) return;
      if (questions.isEmpty) throw const FormatException('empty quiz');
      if (params.planId != null && params.studySessionId != null) {
        try {
          await ref.read(studyPlanCoordinatorProvider).updateSessionResult(
                planId: params.planId!,
                sessionId: params.studySessionId!,
                status: StudySessionStatus.inProgress,
              );
          ref.invalidate(activePlanProvider);
          ref.invalidate(allPlansProvider);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Quiz iniciado. Não foi possível salvar o progresso do plano agora.')));
          }
        }
      }
      if (!mounted || !_sameAccount) return;
      _updateQuizState(() {
        _questions.addAll(questions);
        _loadingInitial = false;
      });
      _stopwatch.start();
      _saveSessionLocally();
    } catch (error) {
      if (!mounted || !_sameAccount) return;
      _updateQuizState(() {
        _loadingInitial = false;
        _initialError = switch (error) {
          RemoteServiceException e => e.message,
          ProviderRateLimitException e => e.message,
          PremiumLimitException e => e.message,
          _ =>
            'Não foi possível gerar as perguntas desta sessão. Tente novamente.',
        };
      });
    }
  }

  Future<void> _recordStudySessionResult({required int correct}) async {
    final params = widget.generationParams!;
    try {
      await ref.read(studyPlanCoordinatorProvider).updateSessionResult(
            planId: params.planId!,
            sessionId: params.studySessionId!,
            status: StudySessionStatus.completed,
            correctAnswers: correct,
            incorrectAnswers: _answers.length - correct,
            timeSpentMinutes:
                ((_restoredSeconds + _stopwatch.elapsed.inSeconds) ~/ 60)
                    .clamp(1, 120),
            score: _answers.isNotEmpty ? correct / _answers.length * 100 : 0,
          );
      ref.invalidate(activePlanProvider);
      ref.invalidate(allPlansProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Não foi possível salvar a conclusão da sessão no plano.')));
      }
    }
  }

  Widget _buildInitialQuizState() => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
            title: const Text('Quiz do plano'),
            leading: BackButton(
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/today-plan'))),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.generationParams!.topic,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 18)),
                    const SizedBox(height: 20),
                    if (_loadingInitial) ...[
                      const CircularProgressIndicator(color: AppColors.primary),
                      const SizedBox(height: 16),
                      const Text('Preparando as perguntas da sessão...',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ] else ...[
                      Text(_initialError ?? 'Nenhuma pergunta foi gerada.',
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _generateInitialQuiz,
                          child: const Text('Tentar novamente')),
                    ],
                  ],
                ))),
      );
}
