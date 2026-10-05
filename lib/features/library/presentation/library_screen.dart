import 'material_chapter_picker.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_error_message.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../application/library_actions_coordinator.dart';
import '../application/library_document_recovery.dart';
import '../application/study_document_picker.dart';
import '../application/study_document_upload_source.dart';
import '../data/library_repository.dart';
import '../domain/library_model.dart';
import '../../study_plan/data/study_plan_repository.dart';
import '../../study_plan/domain/study_document.dart';

part 'library_document_cards.dart';
part 'library_add_file_form.dart';

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
  bool _recoveringDocuments = false;
  List<StudyDocument> _libraryDocuments = const [];
  Timer? _documentPollTimer;
  int _pollIntervalSeconds = 3;

  @override
  void initState() {
    super.initState();
    unawaited(_resumeLibraryDocuments());
  }

  @override
  void dispose() {
    _documentPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _resumeLibraryDocuments() async {
    if (_recoveringDocuments) return;
    _recoveringDocuments = true;
    try {
      final result = await LibraryDocumentRecovery(
        libraryRepository: ref.read(libraryRepositoryProvider),
        documentRepository: ref.read(studyPlanRepositoryProvider),
      ).resume();
      if (!mounted) return;
      setState(() => _libraryDocuments = result.documents);
      if (result.importedCount > 0) {
        ref.invalidate(libraryFilesProvider);
      }
      _documentPollTimer?.cancel();
      if (result.hasPending) {
        _documentPollTimer = Timer(
          Duration(seconds: _pollIntervalSeconds),
          () {
            if (!mounted) return;
            // Backoff exponencial para poupar bateria: 3s -> 6s -> 12s -> máx 24s
            _pollIntervalSeconds = (_pollIntervalSeconds * 2).clamp(3, 24);
            unawaited(_resumeLibraryDocuments());
          },
        );
      } else {
        _pollIntervalSeconds = 3;
      }
    } catch (_) {
      // Mantem os cards atuais e tenta novamente no proximo ciclo.
    } finally {
      _recoveringDocuments = false;
    }
  }

  Future<void> _onLibraryUploadQueued(StudyDocument document) async {
    if (!mounted) return;
    _pollIntervalSeconds = 3;
    setState(() {
      _showAddDialog = false;
      _libraryDocuments = [
        document,
        ..._libraryDocuments.where((item) => item.id != document.id),
      ];
    });
    await _resumeLibraryDocuments();
  }

  @override
  Widget build(BuildContext context) {
    final filesAsync = ref.watch(libraryFilesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
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
                      const Spacer(),
                      PopupMenuButton<String>(
                        tooltip: 'Menu da Biblioteca',
                        icon: const Icon(Icons.more_vert_rounded,
                            color: AppColors.textPrimary),
                        color: AppColors.surface,
                        onSelected: (value) {
                          if (value == 'studyPlan') {
                            context.push('/study-plan');
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'studyPlan',
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month_rounded,
                                    color: AppColors.primary, size: 20),
                                SizedBox(width: 12),
                                Expanded(
                                    child: Text('Plano de estudos',
                                        style: TextStyle(
                                            color: AppColors.textPrimary))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // ── Card Destaque: Plano de Estudos ─────────────────
                Consumer(
                  builder: (context, ref, _) {
                    final activePlanAsync = ref.watch(activePlanProvider);
                    return activePlanAsync.when(
                      data: (plan) {
                        final hasActivePlan = plan != null;
                        final completedCount = hasActivePlan
                            ? plan.items.where((i) => i.isCompleted).length
                            : 0;
                        final totalCount =
                            hasActivePlan ? plan.items.length : 0;
                        final pct = hasActivePlan ? plan.totalProgress : 0.0;

                        return Container(
                          margin: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.surface,
                                AppColors.primary.withOpacity(0.10),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.35),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () => context.push('/study-plan'),
                            borderRadius: BorderRadius.circular(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.primary.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.calendar_month_rounded,
                                        color: AppColors.primaryLight,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Plano de Estudos',
                                            style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text(
                                            hasActivePlan
                                                ? plan.objetivo
                                                : 'Cronograma com base em editais ou disciplinas',
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.primary.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            hasActivePlan ? 'Abrir' : 'Criar',
                                            style: const TextStyle(
                                              color: AppColors.primaryLight,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 13,
                                            color: AppColors.primaryLight,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (hasActivePlan) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: pct,
                                            minHeight: 5,
                                            backgroundColor: AppColors.surface2,
                                            valueColor:
                                                const AlwaysStoppedAnimation<
                                                    Color>(
                                              AppColors.success,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '$completedCount/$totalCount sessões',
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  },
                ),

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
                      final visibleDocuments = _libraryDocuments
                          .where(
                            (document) =>
                                document.status != StudyDocumentStatus.ready &&
                                document.status != StudyDocumentStatus.deleted,
                          )
                          .toList(growable: false);
                      if (files.isEmpty && visibleDocuments.isEmpty) {
                        return _buildEmptyState();
                      }
                      return _buildFilesList(files, visibleDocuments);
                    },
                  ),
                ),

                // ── Botão fixo ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: GestureDetector(
                    key: const Key('libraryAddMaterialButton'),
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
                          documentRepository:
                              ref.read(studyPlanRepositoryProvider),
                          onUploadQueued: _onLibraryUploadQueued,
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
      ),
    );
  }

  /// Lista de arquivos com cards.
  Widget _buildFilesList(
    List<LibraryFile> files,
    List<StudyDocument> documents,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          for (final document in documents)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _DocumentProcessingCard(document: document),
            ),
          ...List.generate(
            files.length,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FileCard(
                file: files[index],
                onDelete: () => _deleteFile(files[index].id),
                onGeneratePackage: () => _generatePackage(files[index]),
              ),
            ),
          ),
        ].animate(interval: 60.ms).fadeIn().slideY(begin: 0.05, end: 0),
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
