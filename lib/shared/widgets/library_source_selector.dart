import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../features/library/data/library_repository.dart';
import '../../features/library/domain/library_model.dart';

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
        _ModeToggle(
          useLibrary: useLibrary,
          onChanged: onModeChanged,
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: useLibrary
              ? _LibraryPicker(
                  key: const ValueKey('library'),
                  selectedFile: selectedFile,
                  onFileSelected: onFileSelected,
                  onGoToLibrary: () => context.go('/library'),
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

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.useLibrary,
    required this.onChanged,
  });

  final bool useLibrary;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ModeTab(
          label: 'Topico manual',
          selected: !useLibrary,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 8),
        _ModeTab(
          label: 'Da biblioteca',
          selected: useLibrary,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

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
          height: 40,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
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

class _LibraryPicker extends ConsumerWidget {
  const _LibraryPicker({
    required this.selectedFile,
    required this.onFileSelected,
    required this.onGoToLibrary,
    super.key,
  });

  final LibraryFile? selectedFile;
  final ValueChanged<LibraryFile?> onFileSelected;
  final VoidCallback onGoToLibrary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(libraryFilesProvider);

    return filesAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (files) {
        if (files.isEmpty) {
          return _EmptyLibraryHint(onGoToLibrary: onGoToLibrary);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: files.map((file) {
            final isSelected = selectedFile?.id == file.id;

            return GestureDetector(
              onTap: () => onFileSelected(isSelected ? null : file),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.1)
                      : AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      isSelected ? 'OK' : 'ARQ',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.nome,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${file.categoria} - ${file.conteudo.length} chars',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.primary,
                        size: 18,
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

class _EmptyLibraryHint extends StatelessWidget {
  const _EmptyLibraryHint({required this.onGoToLibrary});

  final VoidCallback onGoToLibrary;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onGoToLibrary,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 22,
              color: AppColors.textMuted,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Biblioteca vazia',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Toque aqui para adicionar materiais de estudo',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppColors.textMuted,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
