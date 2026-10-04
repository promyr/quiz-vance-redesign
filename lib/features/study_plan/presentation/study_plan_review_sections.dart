part of 'study_plan_screen.dart';

extension _StudyPlanReviewSections on _StudyPlanScreenState {
  Future<void> _editNoticeSubject([int? index]) async {
    final analysis = _noticeAnalysis;
    if (analysis == null) return;
    final subject = index == null
        ? const StudyPlanNoticeSubject(
            name: '',
            topics: [],
            evidence: 'Incluída manualmente',
            peso: null,
            numQuestoes: null)
        : analysis.subjects[index];
    final edited = await showDialog<StudyPlanNoticeSubject>(
        context: context,
        builder: (_) => NoticeSubjectEditor(subject: subject));
    if (!mounted || edited == null) return;
    _updatePlanState(() {
      final subjects = [...analysis.subjects];
      if (index == null) {
        subjects.add(edited);
        _selectedSubjectIndexes.add(subjects.length - 1);
      } else {
        subjects[index] = edited;
      }
      _noticeAnalysis = StudyPlanNoticeAnalysis(
          jobTitle: analysis.jobTitle,
          subjects: subjects,
          concursoInfo: analysis.concursoInfo,
          cronograma: analysis.cronograma,
          cargosPopup: analysis.cargosPopup);
    });
  }

  Widget _buildReviewPhase() {
    final analysis = _noticeAnalysis;
    if (analysis == null) {
      return _buildConfigPhase();
    }

    final crono = analysis.cronograma;
    final concurso = analysis.concursoInfo;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar',
                    onPressed: () =>
                        _updatePlanState(() => _phase = _PlanPhase.config),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Revise o conteúdo do edital',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  // ── Cabeçalho do concurso ────────────────────────
                  if (concurso != null && concurso.orgao.isNotEmpty)
                    _ConcursoInfoCard(concurso: concurso, cronograma: crono),

                  if (crono != null && crono.dataProva.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.event_available_rounded,
                              color: AppColors.success, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(
                            'Data da prova extraída do edital: ${_formatDisplayDate(crono.dataProva)}',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          )),
                        ],
                      ),
                    ),
                  if (crono == null || crono.dataProva.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'A data da prova não foi encontrada no edital.',
                        style: TextStyle(color: AppColors.warning),
                      ),
                    ),

                  const SizedBox(height: 4),
                  Text(
                    analysis.jobTitle.isEmpty
                        ? _objectiveCtrl.text.trim()
                        : analysis.jobTitle,
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${analysis.subjects.length} disciplinas • ${analysis.subjects.fold<int>(0, (acc, s) => acc + s.topics.length)} tópicos',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              _updatePlanState(() {
                                _selectedSubjectIndexes = Set<int>.from(
                                  List<int>.generate(
                                    analysis.subjects.length,
                                    (i) => i,
                                  ),
                                );
                              });
                            },
                            child: const Text(
                              'Marcar todas',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              _updatePlanState(() {
                                _selectedSubjectIndexes.clear();
                              });
                            },
                            child: const Text(
                              'Desmarcar',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                      onPressed: () => _editNoticeSubject(),
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar disciplina')),
                  ...analysis.subjects.asMap().entries.map((entry) {
                    final index = entry.key;
                    final subject = entry.value;
                    final selected = _selectedSubjectIndexes.contains(index);
                    return Card(
                      color: AppColors.surface,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: CheckboxListTile(
                        value: selected,
                        activeColor: AppColors.primary,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) {
                          _updatePlanState(() {
                            if (value == true) {
                              _selectedSubjectIndexes.add(index);
                            } else {
                              _selectedSubjectIndexes.remove(index);
                            }
                          });
                        },
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                subject.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (subject.peso != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Peso ${subject.peso}',
                                  style: const TextStyle(
                                    color: AppColors.primaryLight,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (subject.numQuestoes != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${subject.numQuestoes}Q',
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subject.topics.join(' • '),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                              TextButton.icon(
                                  onPressed: () => _editNoticeSubject(index),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text(
                                      'Editar disciplina e tópicos')),
                              if (subject.evidence.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Base no edital: ${subject.evidence}',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: AppButton(
                label:
                    'Criar plano (${_selectedSubjectIndexes.length} de ${analysis.subjects.length} selecionadas)',
                isLoading: _loading,
                onPressed: _generatePlan,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Converte YYYY-MM-DD → DD/MM/YYYY para exibição
}
