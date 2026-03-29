import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../data/history_repository.dart';
import '../domain/activity_entry.dart';

class ActivityHistoryScreen extends ConsumerWidget {
  const ActivityHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(activityHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.textPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '📋 Histórico',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => ref.invalidate(activityHistoryProvider),
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                    tooltip: 'Atualizar',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: historyAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (err, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        color: AppColors.textMuted,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Não foi possível carregar o histórico',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(activityHistoryProvider),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
                data: (entries) {
                  if (entries.isEmpty) {
                    return const EmptyStateWidget(
                      emoji: '📭',
                      title: 'Nenhuma atividade ainda',
                      subtitle:
                          'Complete um quiz ou simulado para ver seu histórico aqui.',
                    );
                  }
                  return _HistoryList(entries: entries);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lista de atividades ───────────────────────────────────────────────────────

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.entries});

  final List<ActivityEntry> entries;

  @override
  Widget build(BuildContext context) {
    // Agrupa por data (dia)
    final grouped = <String, List<ActivityEntry>>{};
    for (final e in entries) {
      final local = e.createdAt.toLocal();
      final key =
          '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
      grouped.putIfAbsent(key, () => []).add(e);
    }

    final days = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        final dayEntries = grouped[day]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DayHeader(date: day, entries: dayEntries),
            const SizedBox(height: 8),
            ...dayEntries.asMap().entries.map(
                  (e) => _ActivityCard(entry: e.value, index: i * 10 + e.key),
                ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

// ── Cabeçalho do dia ─────────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.entries});

  final String date;
  final List<ActivityEntry> entries;

  String _relativeDate() {
    final now = DateTime.now();
    final parts = date.split('/');
    final day = DateTime(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
    final diff = now.difference(day).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    return date;
  }

  @override
  Widget build(BuildContext context) {
    final totalXp = entries.fold(0, (sum, e) => sum + e.xpEarned);
    return Row(
      children: [
        Text(
          _relativeDate(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(height: 1, color: AppColors.border),
        ),
        if (totalXp > 0) ...[
          const SizedBox(width: 8),
          Text(
            '+$totalXp XP',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Card de uma sessão ────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.entry, required this.index});

  final ActivityEntry entry;
  final int index;

  Color get _accuracyColor {
    if (entry.accuracy >= 80) return AppColors.success;
    if (entry.accuracy >= 50) return AppColors.streakOrange;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final local = entry.createdAt.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Ícone de accuracy
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _accuracyColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '${entry.accuracy.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: _accuracyColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.correct} acertos de ${entry.total} questões',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.close_rounded,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${entry.wrong} erros',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.access_time_rounded,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      time,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // XP ganho
          if (entry.xpEarned > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+${entry.xpEarned} XP',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: index * 30))
        .fadeIn()
        .slideY(begin: 0.04, end: 0);
  }
}
