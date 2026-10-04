part of 'quiz_session_screen.dart';

extension _QuizRecovery on _QuizSessionScreenState {
  String get _recoveryKey {
    if (widget.recoveryKey != null) return widget.recoveryKey!;
    final p = widget.generationParams;
    if (p?.planId != null && p?.studySessionId != null) {
      return 'plan:${p!.planId}/session:${p.studySessionId}';
    }
    return jsonEncode({
      'questions': widget.questions.map((q) => q.id).toList(),
      'topic': p?.topic,
      'difficulty': p?.difficulty,
      'document': p?.documentId,
      'infinite': widget.infiniteMode,
      'revision': widget.isErrorRevisionMode
    });
  }

  bool get _sameAccount =>
      _sessionAccount == AccountScopedPreferences.instance.activeAccountId;
  Future<void> _restoreOrStart() async {
    final saved = await _recoveryStore
        .load(_recoveryKey)
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    if (!mounted || !_sameAccount) return;
    var restored = false;
    try {
      if (saved != null) {
        final questions = (saved['questions'] as List)
            .map((q) => Question.fromJson(Map<String, dynamic>.from(q as Map)))
            .toList();
        final index = saved['index'] as int;
        final answers = (saved['answers'] as List).map((a) {
          final value = a as Map;
          final question = Question.fromJson(
              Map<String, dynamic>.from(value['question'] as Map));
          final selected = value['selected'] as String?;
          return QuestionAnswer(
              question: question,
              selectedOptionId: selected,
              isCorrect: selected == question.correctOptionId);
        }).toList();
        if (questions.isNotEmpty &&
            questions.every(
                (q) => q.options.isNotEmpty && q.correctOption != null) &&
            index >= 0 &&
            index < questions.length &&
            answers.length == index) {
          _questions
            ..clear()
            ..addAll(questions);
          _answers
            ..clear()
            ..addAll(answers);
          _currentIndex = index;
          _selectedOptionId = saved['selected'] as String?;
          _answered = saved['answered'] == true &&
              _current.options.any((o) => o.id == _selectedOptionId);
          _restoredSeconds = (saved['elapsed'] as int? ?? 0).clamp(0, 86400);
          _elapsed = _restoredSeconds;
          restored = true;
        }
      }
    } catch (_) {
      /* A partial/corrupt checkpoint cannot prevent a fresh quiz. */
    }
    _updateQuizState(() {
      _restoring = false;
      _loadingInitial = _questions.isEmpty;
    });
    if (_questions.isEmpty && widget.generationParams != null) {
      await _generateInitialQuiz();
    } else if (_questions.isNotEmpty) {
      _stopwatch.start();
      if (restored) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sessão retomada de onde você parou.')));
      }
      _saveSessionLocally();
    }
  }

  void _saveSessionLocally() {
    if (_finishing || _restoring || _questions.isEmpty || !_sameAccount) return;
    unawaited(_recoveryStore.save(_recoveryKey, {
      'params': widget.generationParams?.toJson(),
      'infinite': widget.infiniteMode,
      'revision': widget.isErrorRevisionMode,
      'questions': _questions.map((q) => q.toJson()).toList(),
      'answers': _answers
          .map((a) =>
              {'question': a.question.toJson(), 'selected': a.selectedOptionId})
          .toList(),
      'index': _currentIndex,
      'selected': _selectedOptionId,
      'answered': _answered,
      'elapsed': _restoredSeconds + _stopwatch.elapsed.inSeconds,
    }).catchError((Object _) {}));
  }
}
