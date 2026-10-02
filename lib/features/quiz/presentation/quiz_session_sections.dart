part of 'quiz_session_screen.dart';

String _getTopicIcon(String topic) {
  final lower = topic.toLowerCase();
  if (lower.contains('bio') ||
      lower.contains('saúde') ||
      lower.contains('cel')) {
    return '🧬';
  }
  if (lower.contains('mat') ||
      lower.contains('alg') ||
      lower.contains('calc') ||
      lower.contains('núm')) {
    return '📐';
  }
  if (lower.contains('hist') ||
      lower.contains('brasil') ||
      lower.contains('guerra')) {
    return '📜';
  }
  if (lower.contains('quím') ||
      lower.contains('átom') ||
      lower.contains('reac')) {
    return '🧪';
  }
  if (lower.contains('fís') ||
      lower.contains('moli') ||
      lower.contains('ener')) {
    return '🔬';
  }
  if (lower.contains('port') ||
      lower.contains('gram') ||
      lower.contains('lit')) {
    return '📚';
  }
  if (lower.contains('geog') ||
      lower.contains('map') ||
      lower.contains('clima')) {
    return '🌍';
  }
  if (lower.contains('dir') ||
      lower.contains('le') ||
      lower.contains('const')) {
    return '⚖️';
  }
  if (lower.contains('ingl') || lower.contains('eng')) {
    return '🔤';
  }
  return '💡';
}

// ── Source Reference Card ──────────────────────────────────────────────────────

/// Card que exibe os metadados da fonte da questão (apostila e trecho).
/// Visível apenas quando a questão foi gerada a partir de um documento da
/// biblioteca e o backend populou o campo [QuestionSource].
class _SourceReferenceCard extends ConsumerStatefulWidget {
  const _SourceReferenceCard({required this.source});

  final QuestionSource source;

  @override
  ConsumerState<_SourceReferenceCard> createState() =>
      _SourceReferenceCardState();
}

class _SourceReferenceCardState extends ConsumerState<_SourceReferenceCard> {
  bool _expanded = false;
  bool _loadingPdf = false;

  Future<void> _openDocumentReader() async {
    final docId = widget.source.documentId;
    if (docId == null) {
      // Exibe modal informativo se não houver ID direto
      showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.source.document ?? 'Apostila',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (widget.source.page != null)
                Text(
                  'Página: ${widget.source.page}',
                  style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 12),
              if (widget.source.excerpt != null)
                Text(
                  '"${widget.source.excerpt}"',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.5),
                ),
            ],
          ),
        ),
      );
      return;
    }

    setState(() => _loadingPdf = true);
    try {
      final content =
          await ref.read(studyPlanRepositoryProvider).getDocumentContent(docId);
      final docInfo =
          await ref.read(studyPlanRepositoryProvider).getDocument(docId);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        docInfo.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                if (widget.source.page != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Página ${widget.source.page}',
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const Divider(color: AppColors.border),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Text(
                      content.isNotEmpty ? content : 'Conteúdo indisponível.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir a apostila.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final hasDocument = source.document?.trim().isNotEmpty ?? false;
    final hasChapter = source.chapter?.trim().isNotEmpty ?? false;
    final hasSection = source.section?.trim().isNotEmpty ?? false;
    final hasPage = source.page != null;
    final hasTopic = source.topic?.trim().isNotEmpty ?? false;
    final hasExcerpt = source.excerpt?.trim().isNotEmpty ?? false;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF1565C0).withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: Color(0xFF64B5F6),
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '📚 Referência na Apostila',
                  style: TextStyle(
                    color: Color(0xFF64B5F6),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Divider(color: Color(0xFF1E3A5F), height: 1),
          ),

          // ── Metadata list ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasDocument)
                  _MetaRow(
                      icon: '📖', label: 'Apostila', value: source.document!),
                if (hasChapter)
                  _MetaRow(
                      icon: '📑', label: 'Capítulo', value: source.chapter!),
                if (hasSection)
                  _MetaRow(icon: '📝', label: 'Seção', value: source.section!),
                if (hasPage)
                  _MetaRow(
                      icon: '📄', label: 'Página', value: '${source.page!}'),
                if (hasTopic)
                  _MetaRow(
                      icon: '🏷', label: 'Subtópico', value: source.topic!),
              ],
            ),
          ),

          // ── Excerpt ──────────────────────────────────────────────────────
          if (hasExcerpt) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Trecho utilizado na geração da questão:',
                      style: TextStyle(
                        color: Color(0xFF90CAF9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1628),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF1E3A5F),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '"${source.excerpt!}"',
                          maxLines: _expanded ? null : 4,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB0BEC5),
                            fontSize: 12,
                            height: 1.55,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        if (source.excerpt!.length > 200)
                          GestureDetector(
                            onTap: () => setState(() => _expanded = !_expanded),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _expanded ? 'Ver menos ▲' : 'Ver mais ▼',
                                style: const TextStyle(
                                  color: Color(0xFF64B5F6),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Action Button "Abrir na apostila" ────────────────────────────
          if (hasDocument)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loadingPdf ? null : _openDocumentReader,
                  icon: _loadingPdf
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('📖', style: TextStyle(fontSize: 14)),
                  label: Text(
                    hasPage
                        ? 'Ir para página ${source.page}'
                        : 'Abrir na apostila',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text(
            '$label:  ',
            style: const TextStyle(
              color: Color(0xFF90CAF9),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _QuizSessionScreenUiHelpers on _QuizSessionScreenState {
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
        Text(
          'Questão $answeredCount',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
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
                          color: Colors.white,
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
}
