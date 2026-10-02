import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../features/library/data/library_repository.dart';
import '../../features/library/domain/library_model.dart';

Future<LibraryFile?> showLibraryFilePickerModal(BuildContext context) {
  return showModalBottomSheet<LibraryFile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.7),
    builder: (_) => const _LibraryPickerSheet(),
  );
}

class LibrarySourceSelector extends ConsumerWidget {
  const LibrarySourceSelector({
    required this.useLibrary,
    required this.selectedFile,
    required this.onModeChanged,
    required this.onFileSelected,
    required this.manualChild,
    super.key,
  });

  final bool useLibrary;
  final LibraryFile? selectedFile;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<LibraryFile?> onFileSelected;
  final Widget manualChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => onModeChanged(false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 40,
                  decoration: BoxDecoration(
                    color: !useLibrary
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: !useLibrary ? AppColors.primary : AppColors.border,
                      width: !useLibrary ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Tópico manual',
                      style: TextStyle(
                        color: !useLibrary
                            ? AppColors.primary
                            : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight:
                            !useLibrary ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => onModeChanged(true),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 40,
                  decoration: BoxDecoration(
                    color: useLibrary
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: useLibrary ? AppColors.primary : AppColors.border,
                      width: useLibrary ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Da biblioteca',
                      style: TextStyle(
                        color: useLibrary
                            ? AppColors.primary
                            : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight:
                            useLibrary ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: useLibrary
              ? _InlineLibraryPicker(
                  selectedFile: selectedFile,
                  onFileSelected: onFileSelected,
                )
              : KeyedSubtree(
                  key: const ValueKey('manual'),
                  child: manualChild,
                ),
        ),
      ],
    );
  }
}

class _InlineLibraryPicker extends ConsumerWidget {
  const _InlineLibraryPicker({
    required this.selectedFile,
    required this.onFileSelected,
  });

  final LibraryFile? selectedFile;
  final ValueChanged<LibraryFile?> onFileSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(libraryFilesProvider);

    return filesAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (files) {
        if (files.isEmpty) {
          return GestureDetector(
            onTap: () => context.push('/library'),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.folder_open_rounded, color: AppColors.textMuted),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sua biblioteca está vazia. Toque para adicionar materiais.',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: files.map((file) {
            final isSelected = selectedFile?.id == file.id;
            return GestureDetector(
              onTap: () => onFileSelected(isSelected ? null : file),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.12)
                      : AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.description_rounded,
                      color:
                          isSelected ? AppColors.primary : AppColors.textMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        file.nome,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _LibraryPickerSheet extends ConsumerWidget {
  const _LibraryPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(libraryFilesProvider);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(
                Icons.collections_bookmark_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Materiais da Biblioteca',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Selecione um resumo ou apostila salva para a IA gerar questões baseadas nele:',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: filesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Não foi possível carregar os arquivos da biblioteca.',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
              data: (files) {
                if (files.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.folder_open_rounded,
                          size: 40,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Sua biblioteca está vazia',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Adicione resumos ou textos para gerar quizzes sobre seu próprio material.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            context.push('/library');
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Ir para Biblioteca'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).pop(file),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.description_rounded,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.nome,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${file.categoria} • ${(file.conteudo.length / 1000).toStringAsFixed(1)}k caracteres',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: AppColors.textMuted,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
