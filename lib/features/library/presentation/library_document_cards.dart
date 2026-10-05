part of 'library_screen.dart';

class _DocumentProcessingCard extends StatelessWidget {
  const _DocumentProcessingCard({required this.document});

  final StudyDocument document;

  @override
  Widget build(BuildContext context) {
    final failed = document.status == StudyDocumentStatus.failed ||
        document.status == StudyDocumentStatus.needsReview;
    final label = switch (document.status) {
      StudyDocumentStatus.uploading => 'Enviando PDF',
      StudyDocumentStatus.extracting => 'Extraindo paginas e OCR',
      StudyDocumentStatus.mapping => 'Organizando material',
      StudyDocumentStatus.failed => 'Falha no processamento',
      StudyDocumentStatus.needsReview => 'PDF precisa de revisao',
      _ => 'Processando em segundo plano',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: failed ? AppColors.error : AppColors.primary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            document.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            failed
                ? (document.errorMessage ?? label)
                : '$label • ${document.progress}%',
            style: TextStyle(
              color: failed ? AppColors.error : AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (!failed) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: document.progress / 100,
              backgroundColor: AppColors.surface,
              color: AppColors.primary,
            ),
            const SizedBox(height: 6),
            const Text(
              'Pode sair desta tela. O servidor continuara o processamento.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card para exibir um arquivo da biblioteca.

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.file,
    required this.onDelete,
    required this.onGeneratePackage,
  });

  final LibraryFile file;
  final VoidCallback onDelete;
  final VoidCallback onGeneratePackage;

  @override
  Widget build(BuildContext context) {
    final formattedDate =
        '${file.criadoEm.day}/${file.criadoEm.month}/${file.criadoEm.year}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nome e categoria
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.nome,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${file.categoria ?? 'Geral'} • $formattedDate',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('🗑️', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Preview do conteúdo
          Text(
            file.conteudo.length > 80
                ? '${file.conteudo.substring(0, 80)}...'
                : file.conteudo,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          MaterialChapterButton(file: file),
          const SizedBox(height: 12),
          // Botão Gerar Pacote
          GestureDetector(
            onTap: onGeneratePackage,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary),
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '🧠 Gerar Pacote',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modos de entrada de conteúdo no formulário.
