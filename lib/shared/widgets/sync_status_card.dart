import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

enum SyncStatusState { syncing, saved, pending }

class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({
    super.key,
    required this.state,
    required this.message,
    this.onRetry,
  });

  final SyncStatusState state;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    late final Color accentColor;
    late final IconData icon;
    late final String title;

    switch (state) {
      case SyncStatusState.syncing:
        accentColor = AppColors.primary;
        icon = Icons.sync_rounded;
        title = 'Sincronizando resultado';
        break;
      case SyncStatusState.saved:
        accentColor = AppColors.success;
        icon = Icons.check_circle_rounded;
        title = 'Resultado salvo';
        break;
      case SyncStatusState.pending:
        accentColor = AppColors.accent;
        icon = Icons.cloud_off_rounded;
        title = 'Sincronizacao pendente';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (state == SyncStatusState.pending && onRetry != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accentColor.withOpacity(0.4)),
                ),
                child: Text(
                  'Tentar novamente',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
