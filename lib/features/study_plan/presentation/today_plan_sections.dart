part of 'today_plan_screen.dart';

class _StudySessionCard extends StatelessWidget {
  const _StudySessionCard({
    required this.session,
    required this.isLoading,
    required this.onToggleComplete,
    required this.onStartQuiz,
    required this.onStartFlashcards,
    required this.onReadMaterial,
    required this.onReschedule,
  });

  final StudyPlanItem session;
  final bool isLoading;
  final VoidCallback onToggleComplete;
  final VoidCallback onStartQuiz;
  final VoidCallback onStartFlashcards;
  final VoidCallback onReadMaterial;
  final VoidCallback onReschedule;

  Color get _priorityColor {
    switch (session.prioridade) {
      case 1:
        return AppColors.error;
      case 2:
        return AppColors.accent;
      case 3:
      default:
        return AppColors.success;
    }
  }

  String get _priorityLabel {
    switch (session.prioridade) {
      case 1:
        return 'Alta';
      case 2:
        return 'Média';
      case 3:
      default:
        return 'Baixa';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: session.isCompleted
            ? AppColors.surface.withOpacity(0.5)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: session.isCompleted
              ? AppColors.success.withOpacity(0.3)
              : (session.isInProgress
                  ? AppColors.primary.withOpacity(0.5)
                  : AppColors.border),
          width: session.isInProgress ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header da sessão
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _priorityColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Prioridade $_priorityLabel',
                            style: TextStyle(
                              color: _priorityColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '~${session.duracaoMin} min',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      session.subject,
                      style: TextStyle(
                        color: session.isCompleted
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        decoration: session.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (session.tema.isNotEmpty &&
                        session.tema != session.subject) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Tópico: ${session.tema}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  session.isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: session.isCompleted
                      ? AppColors.success
                      : AppColors.textMuted,
                  size: 24,
                ),
                onPressed: onToggleComplete,
              ),
            ],
          ),

          // Subtópicos Chips
          if (session.subtopics.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: session.subtopics.map((st) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Text(
                    st,
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),

          // Ações Rápidas da Sessão
          Row(
            children: [
              Expanded(
                child: _SessionActionButton(
                  icon: Icons.quiz_rounded,
                  label: 'Fazer Quiz',
                  color: AppColors.primary,
                  onTap: isLoading ? null : onStartQuiz,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SessionActionButton(
                  icon: Icons.style_rounded,
                  label: 'Flashcards',
                  color: AppColors.success,
                  onTap: isLoading ? null : onStartFlashcards,
                ),
              ),
              if (session.sourceDocumentIds.isNotEmpty) ...[
                const SizedBox(width: 8),
                _IconButtonSmall(
                  icon: Icons.menu_book_rounded,
                  tooltip: 'Ler PDF',
                  onTap: isLoading ? null : onReadMaterial,
                ),
              ],
              const SizedBox(width: 8),
              _IconButtonSmall(
                icon: Icons.edit_calendar_rounded,
                tooltip: 'Reagendar',
                onTap: isLoading ? null : onReschedule,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionActionButton extends StatelessWidget {
  const _SessionActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButtonSmall extends StatelessWidget {
  const _IconButtonSmall({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: AppColors.textMuted, size: 18),
        ),
      ),
    );
  }
}
