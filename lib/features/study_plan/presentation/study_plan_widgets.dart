part of 'study_plan_screen.dart';

class _StudyItemCard extends StatelessWidget {
  const _StudyItemCard({
    required this.item,
    required this.onToggle,
  });

  final StudyPlanItem item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isPriority = item.prioridade == 1;

    return GestureDetector(
      onTap: onToggle,
      child: Opacity(
        opacity: item.concluido ? 0.5 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isPriority ? AppColors.accent : AppColors.border,
              width: isPriority ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Checkbox
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color:
                      item.concluido ? AppColors.success : AppColors.surface2,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color:
                        item.concluido ? AppColors.success : AppColors.border,
                  ),
                ),
                child: item.concluido
                    ? const Center(
                        child: Icon(Icons.check_rounded,
                            size: 12, color: AppColors.background),
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Conteúdo
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.tema,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.atividade,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Chips de duração
                    Chip(
                      label: Text('⏱ ${item.duracaoMin}min',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                      backgroundColor: AppColors.surface2,
                      side:
                          const BorderSide(color: AppColors.border, width: 0.5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label para seções.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary,
          ),
    );
  }
}

/// Botão com estilo outline.
class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Novos componentes de UI ────────────────────────────────────────────────

/// Bottom sheet para o usuário selecionar o cargo do edital.
class _CargoSelectionSheet extends StatelessWidget {
  const _CargoSelectionSheet({required this.cargos});

  final List<CargoNoticeItem> cargos;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Selecione o cargo',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'O conteúdo programático será filtrado para o cargo selecionado.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: cargos.length,
                itemBuilder: (ctx, i) {
                  final cargo = cargos[i];
                  return Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(ctx).pop(cargo),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cargo.titulo,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (cargo.escolaridade.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      cargo.escolaridade,
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (cargo.vagas != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color:
                                          AppColors.primary.withOpacity(0.4)),
                                ),
                                child: Text(
                                  '${cargo.vagas} vaga${cargo.vagas == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                    color: AppColors.primaryLight,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right_rounded,
                                color: AppColors.textMuted, size: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Card com informações do concurso extraídas do edital.
class _ConcursoInfoCard extends StatelessWidget {
  const _ConcursoInfoCard({
    required this.concurso,
    required this.cronograma,
  });

  final ConcursoInfo concurso;
  final CronogramaEdital? cronograma;

  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '–';
    final parts = iso.split('-');
    if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    return iso;
  }

  @override
  Widget build(BuildContext context) {
    final crono = cronograma;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: concurso.isSuspenso
              ? AppColors.error.withOpacity(0.5)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  concurso.orgao,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: concurso.isSuspenso
                      ? AppColors.error.withOpacity(0.15)
                      : AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  concurso.statusEdital,
                  style: TextStyle(
                    color: concurso.isSuspenso
                        ? AppColors.error
                        : AppColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (concurso.banca.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Banca: ${concurso.banca}',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
          if (crono != null) ...[
            const SizedBox(height: 10),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                if (crono.inscricoesFim.isNotEmpty)
                  _InfoChip(
                      icon: Icons.edit_calendar_outlined,
                      label: 'Inscrições até ${_fmt(crono.inscricoesFim)}'),
                if (crono.dataProva.isNotEmpty)
                  _InfoChip(
                      icon: Icons.event_rounded,
                      label: 'Prova: ${_fmt(crono.dataProva)}',
                      highlight: crono.dataProvaDefinida),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 13,
            color: highlight ? AppColors.primaryLight : AppColors.textMuted),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: highlight ? AppColors.primaryLight : AppColors.textMuted,
            fontSize: 12,
            fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
