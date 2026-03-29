import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../../core/network/api_error_message.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../application/library_actions_coordinator.dart';
import '../data/library_repository.dart';
import '../domain/library_model.dart';

/// Tela principal da biblioteca de materiais de estudo.
///
/// Permite:
/// - Visualizar lista de arquivos salvos
/// - Adicionar novo material de estudo via formulário
/// - Gerar pacote de estudo a partir de um arquivo
/// - Deletar arquivo
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _showAddDialog = false;

  @override
  Widget build(BuildContext context) {
    final filesAsync = ref.watch(libraryFilesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: AppBottomNav(currentIndex: 3),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/'),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text(
                              '←',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '📚 Biblioteca',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ── Content ──────────────────────────────────────────
                Expanded(
                  child: filesAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (err, stack) => Center(
                      child: Text(
                        'Erro ao carregar: $err',
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                    data: (files) {
                      if (files.isEmpty) {
                        return _buildEmptyState();
                      }
                      return _buildFilesList(files);
                    },
                  ),
                ),

                // ── Botão fixo ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: GestureDetector(
                    onTap: () => setState(() => _showAddDialog = true),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Adicionar Material',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
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
          ),

          // ── Overlay do dialog de adicionar ────────────────────────
          if (_showAddDialog)
            Positioned.fill(
              child: Material(
                color: AppColors.background.withOpacity(0.96),
                child: SafeArea(
                  child: GestureDetector(
                    onTap: () => setState(() => _showAddDialog = false),
                    behavior: HitTestBehavior.opaque,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: GestureDetector(
                        onTap: () {}, // impede fechar ao tocar no form
                        child: _AddFileForm(
                          onSave: (nome, categoria, conteudo) async {
                            try {
                              await ref
                                  .read(libraryActionsCoordinatorProvider)
                                  .addFile(
                                    nome: nome,
                                    categoria: categoria,
                                    conteudo: conteudo,
                                  );
                              if (!context.mounted) return;
                              ref.invalidate(libraryFilesProvider);
                              setState(() => _showAddDialog = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Material adicionado com sucesso!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                      'Não foi possível adicionar o material. Tente novamente.'),
                                  backgroundColor: Colors.red,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                          onCancel: () =>
                              setState(() => _showAddDialog = false),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Widget de estado vazio quando nenhum arquivo existe.
  Widget _buildEmptyState() {
    return Center(
      child: EmptyStateWidget(
        emoji: '📂',
        title: 'Biblioteca vazia',
        subtitle:
            'Adicione seu primeiro material de estudo para gerar quizzes e flashcards personalizados.',
        ctaLabel: '+ Adicionar material',
        onCtaTap: () => setState(() => _showAddDialog = true),
      ),
    );
  }

  /// Lista de arquivos com cards.
  Widget _buildFilesList(List<LibraryFile> files) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: List.generate(
          files.length,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FileCard(
              file: files[index],
              onDelete: () => _deleteFile(files[index].id),
              onGeneratePackage: () => _generatePackage(files[index]),
            ),
          ),
        ).animate(interval: 60.ms).fadeIn().slideY(begin: 0.05, end: 0),
      ),
    );
  }

  /// Delete um arquivo e invalida o provider.
  Future<void> _deleteFile(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Confirmar exclusão',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Tem certeza que deseja deletar este material?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Deletar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(libraryActionsCoordinatorProvider).deleteFile(id);
      ref.invalidate(libraryFilesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Material deletado!'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  /// Gera um pacote de estudo para um arquivo.
  Future<void> _generatePackage(LibraryFile file) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      ),
    );

    try {
      final package =
          await ref.read(libraryActionsCoordinatorProvider).generatePackage(
                file,
              );

      if (mounted) {
        Navigator.pop(context);
        context.push(
          '/library/package',
          extra: {'package': package, 'file': file},
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final message = userVisibleErrorMessage(
          e,
          fallback: 'Não foi possível gerar o pacote. Tente novamente.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
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
enum _InputMode { text, file }

/// Formulário para adicionar novo arquivo.
///
/// Suporta dois modos:
/// - [_InputMode.text]: digitar/colar conteúdo manualmente
/// - [_InputMode.file]: importar PDF ou TXT com extração de texto automática
class _AddFileForm extends StatefulWidget {
  const _AddFileForm({
    required this.onSave,
    required this.onCancel,
  });

  final Future<void> Function(String nome, String? categoria, String conteudo)
      onSave;
  final VoidCallback onCancel;

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

  /// Abre o seletor de arquivos e extrai texto do PDF ou TXT.
  Future<void> _pickFile() async {
    setState(() => _extracting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final bytes = picked.bytes;
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível ler o arquivo')),
          );
        }
        return;
      }

      String text;
      final ext = picked.extension?.toLowerCase() ?? '';

      if (ext == 'pdf') {
        final doc = PdfDocument(inputBytes: bytes);
        text = PdfTextExtractor(doc).extractText();
        doc.dispose();
      } else {
        // TXT ou MD — leitura direta como UTF-8
        text = utf8.decode(bytes, allowMalformed: true);
      }

      // Normaliza espaçamento excessivo
      text = text
          .replaceAll(RegExp(r'[ \t]{3,}'), ' ')
          .replaceAll(RegExp(r'\n{4,}'), '\n\n')
          .trim();

      if (mounted) {
        setState(() {
          _pickedFileName = picked.name;
          _conteudoCtrl.text = text;
          // Auto-preenche nome somente se ainda vazio
          if (_nomeCtrl.text.trim().isEmpty) {
            final nameWithoutExt =
                picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');
            _nomeCtrl.text = nameWithoutExt;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Não foi possível processar o arquivo. Tente novamente.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _extracting = false);
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
                  label: '✍️  Digitar texto',
                  selected: _mode == _InputMode.text,
                  onTap: () => setState(() {
                    _mode = _InputMode.text;
                    _pickedFileName = null;
                  }),
                ),
                const SizedBox(width: 8),
                _ModeTab(
                  label: '📎  Importar arquivo',
                  selected: _mode == _InputMode.file,
                  onTap: () => setState(() => _mode = _InputMode.file),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Nome ─────────────────────────────────────────────────
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

            // ── Categoria ─────────────────────────────────────────────
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

            // ── Conteúdo: texto ou arquivo ────────────────────────────
            const Text(
              'Conteúdo',
              style: TextStyle(
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
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Extraindo texto…',
                                style: TextStyle(
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
                                _pickedFileName ?? 'Selecionar PDF ou TXT',
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
