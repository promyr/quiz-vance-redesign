part of 'library_screen.dart';

enum _InputMode { text, file }

/// Formulário para adicionar novo arquivo.
///
/// Suporta dois modos:
/// - [_InputMode.text]: digitar/colar conteúdo manualmente
/// - [_InputMode.file]: importar PDF com extração de texto automática
class _AddFileForm extends StatefulWidget {
  const _AddFileForm({
    required this.onSave,
    required this.onCancel,
    required this.onUploadQueued,
    required this.documentRepository,
  });

  final Future<void> Function(String nome, String? categoria, String conteudo)
      onSave;
  final VoidCallback onCancel;
  final Future<void> Function(StudyDocument document) onUploadQueued;
  final StudyPlanRepository documentRepository;

  @override
  State<_AddFileForm> createState() => _AddFileFormState();
}

class _AddFileFormState extends State<_AddFileForm> {
  late TextEditingController _nomeCtrl;
  late TextEditingController _categoriaCtrl;
  late TextEditingController _conteudoCtrl;

  _InputMode _mode = _InputMode.text;
  bool _loading = false;
  bool _extracting = false;
  int _extractionProgress = 0;
  String? _pickedFileName;

  @override
  void initState() {
    super.initState();
    _nomeCtrl = TextEditingController();
    _categoriaCtrl = TextEditingController();
    _conteudoCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _categoriaCtrl.dispose();
    _conteudoCtrl.dispose();
    super.dispose();
  }

  /// Abre o seletor de arquivos e extrai texto de um PDF.

  Future<void> _pickFile() async {
    setState(() {
      _extracting = true;
      _extractionProgress = 0;
    });
    PickedStudyDocument? pickedDocument;
    try {
      pickedDocument = await pickStudyDocumentPdf();
      if (pickedDocument == null) return;
      final source = pickedDocument.source;
      final uploaded = await widget.documentRepository.uploadDocument(
        purpose: StudyDocumentPurpose.library,
        fileName: source.fileName,
        length: source.length,
        openRead: source.openRead,
        onProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() {
            _extractionProgress = (sent * 40 / total).round().clamp(0, 40);
          });
        },
      );
      if (!mounted) return;
      setState(() => _extractionProgress = 40);
      await widget.onUploadQueued(uploaded);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${pickedDocument.displayName}" foi enviado e continuara em segundo plano.',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
    } on StudyDocumentUploadException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userVisibleErrorMessage(
                error,
                fallback: 'Nao foi possivel importar o PDF.',
              ),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      await pickedDocument?.dispose();
      if (mounted) {
        setState(() {
          _extracting = false;
          if (_extractionProgress < 100) _extractionProgress = 0;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_nomeCtrl.text.trim().isEmpty || _conteudoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha nome e conteúdo')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.onSave(
        _nomeCtrl.text.trim(),
        _categoriaCtrl.text.trim().isEmpty ? null : _categoriaCtrl.text.trim(),
        _conteudoCtrl.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {}, // Previne fechar ao clicar dentro
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Título ────────────────────────────────────────────────
            const Text(
              'Adicionar Material',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),

            // ── Toggle de modo ────────────────────────────────────────
            Row(
              children: [
                _ModeTab(
                  label: 'Texto manual',
                  selected: _mode == _InputMode.text,
                  onTap: () => setState(() {
                    _mode = _InputMode.text;
                    _pickedFileName = null;
                  }),
                ),
                const SizedBox(width: 8),
                _ModeTab(
                  label: 'PDF',
                  selected: _mode == _InputMode.file,
                  onTap: () => setState(() => _mode = _InputMode.file),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_mode == _InputMode.text) ...[
              // ── Nome ───────────────────────────────────────────────
              const Text(
                'Nome/Título',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nomeCtrl,
                decoration: const InputDecoration(
                  hintText: 'Ex: Anotações de Química Orgânica',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 16),

              // ── Categoria ─────────────────────────────────────────
              const Text(
                'Categoria (opcional)',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _categoriaCtrl,
                decoration: const InputDecoration(
                  hintText: 'Ex: Química, Biologia, História…',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Conteúdo: texto ou arquivo ────────────────────────────
            Text(
              _mode == _InputMode.text ? 'Conteúdo' : 'Arquivo PDF',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            if (_mode == _InputMode.text)
              TextFormField(
                controller: _conteudoCtrl,
                minLines: 6,
                maxLines: 15,
                decoration: const InputDecoration(
                  hintText: 'Cole aqui o conteúdo do seu material de estudo…',
                  prefixIcon: Icon(Icons.description_outlined),
                  alignLabelWithHint: true,
                ),
              )
            else ...[
              // Botão de seleção de arquivo
              GestureDetector(
                onTap: _extracting ? null : _pickFile,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _pickedFileName != null
                          ? AppColors.success
                          : AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: _extracting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Processando PDF ($_extractionProgress%)',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _pickedFileName != null
                                    ? Icons.check_circle_rounded
                                    : Icons.upload_file_rounded,
                                color: _pickedFileName != null
                                    ? AppColors.success
                                    : AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _pickedFileName ?? 'Selecionar PDF',
                                style: TextStyle(
                                  color: _pickedFileName != null
                                      ? AppColors.success
                                      : AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              if (_extracting) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _extractionProgress / 100,
                  backgroundColor: AppColors.surface2,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Upload, extracao por paginas e OCR seletivo no servidor.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],

              // Preview do texto extraído
              if (_conteudoCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '📄 Texto extraído',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_conteudoCtrl.text.length} chars',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _conteudoCtrl.text.length > 200
                            ? '${_conteudoCtrl.text.substring(0, 200)}…'
                            : _conteudoCtrl.text,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),

            // ── Botões ─────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _loading ? null : widget.onCancel,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancelar',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_mode == _InputMode.text) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _loading ? null : _save,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Salvar',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab de seleção de modo de entrada no formulário.
class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withOpacity(0.12)
                : AppColors.surface2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.textMuted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
