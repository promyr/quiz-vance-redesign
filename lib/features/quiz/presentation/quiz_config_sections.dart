part of 'quiz_config_screen.dart';

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _QuizQuotaBadge extends ConsumerWidget {
  const _QuizQuotaBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsNotifierProvider);

    return statsAsync.maybeWhen(
      data: (stats) {
        if (stats.isPremium) return const SizedBox.shrink();
        final remaining = stats.quizRestante ?? -1;
        final limit = stats.quizLimite ?? -1;
        if (remaining < 0 || limit < 0) return const SizedBox.shrink();

        final isExhausted = remaining == 0;
        return GestureDetector(
          onTap: () => showPremiumUpsell(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isExhausted
                  ? AppColors.error.withOpacity(0.12)
                  : AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isExhausted
                    ? AppColors.error.withOpacity(0.4)
                    : AppColors.primary.withOpacity(0.3),
              ),
            ),
            child: Text(
              isExhausted ? 'Limite atingido' : '$remaining/$limit hoje',
              style: TextStyle(
                color: isExhausted ? AppColors.error : AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _PersonalizedTopicChips extends ConsumerWidget {
  const _PersonalizedTopicChips({required this.onTopicSelected});

  final ValueChanged<String> onTopicSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentSubjectsState = ref.watch(recentSubjectsProvider);
    final errorState = ref.watch(errorNotebookNotifierProvider);

    final recentSubjects = recentSubjectsState.value ?? const [];

    final List<({String label, String topic, IconData icon, Color color})>
        suggestions = [];

    // 1. Tópicos do Caderno de Erros (se houver)
    errorState.whenData((errors) {
      if (errors.isNotEmpty) {
        final topics = errors
            .map((e) => e.topic)
            .where((t) => t.isNotEmpty && t != 'Geral')
            .toSet()
            .take(2);
        for (final t in topics) {
          suggestions.add((
            label: '⚠️ Revisar: $t',
            topic: t,
            icon: Icons.warning_amber_rounded,
            color: AppColors.error,
          ));
        }
      }
    });

    // 2. Fallbacks populares do ENEM se houver espaço
    final fallbacks = [
      (
        label: '🧬 Biologia',
        topic: 'Biologia: Fotossíntese e Genética',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.success
      ),
      (
        label: '📜 História',
        topic: 'História do Brasil',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.xpGold
      ),
      (
        label: '📐 Matemática',
        topic: 'Matemática e Geometria',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.accent
      ),
      (
        label: '🧪 Química',
        topic: 'Química Geral',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.primaryLight
      ),
    ];

    for (final fb in fallbacks) {
      if (suggestions.length >= 4) break;
      if (!suggestions.any((s) => s.topic == fb.topic)) {
        suggestions.add((
          label: fb.label,
          topic: fb.topic,
          icon: fb.icon,
          color: fb.color,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Seção de Matérias Pesquisadas Recentes da Conta
        if (recentSubjects.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    color: AppColors.primary,
                    size: 13,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Suas matérias recentes:',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  ref.read(recentSubjectsProvider.notifier).clearAll();
                },
                child: const Text(
                  'Limpar',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: recentSubjects.map((subject) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.35),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onTopicSelected(subject);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bookmark_rounded,
                            color: AppColors.primary,
                            size: 12,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            subject,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              ref
                                  .read(recentSubjectsProvider.notifier)
                                  .removeSubject(subject);
                            },
                            child: Icon(
                              Icons.close_rounded,
                              color: AppColors.primary.withOpacity(0.6),
                              size: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Sugestões complementares
        const Text(
          'Sugestões para seu perfil:',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: suggestions.map((item) {
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTopicSelected(item.topic);
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: item.color.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, color: item.color, size: 12),
                      const SizedBox(width: 5),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: item.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
