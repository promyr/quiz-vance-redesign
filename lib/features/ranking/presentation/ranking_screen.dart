import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../data/ranking_repository.dart';

class RankingDisplayModel {
  const RankingDisplayModel({
    required this.podiumEntries,
    required this.listEntries,
    required this.listStartRank,
  });

  final List<RankingEntry> podiumEntries;
  final List<RankingEntry> listEntries;
  final int listStartRank;
}

RankingDisplayModel buildRankingDisplayModel(List<RankingEntry> entries) {
  if (entries.length < 3 || !hasReliableRankingPodium(entries)) {
    return RankingDisplayModel(
      podiumEntries: const [],
      listEntries: entries,
      listStartRank: 1,
    );
  }

  return RankingDisplayModel(
    podiumEntries: entries.take(3).toList(growable: false),
    listEntries: entries.skip(3).toList(growable: false),
    listStartRank: 4,
  );
}

class RankingScreen extends ConsumerStatefulWidget {
  const RankingScreen({super.key});

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen> {
  int _filterIndex = 0;
  final _filters = ['Semanal', 'Mensal', 'Global'];

  AsyncValue<List<RankingEntry>> get _rankingAsync {
    switch (_filterIndex) {
      case 1:
        return ref.watch(monthlyRankingProvider);
      case 2:
        return ref.watch(globalRankingProvider);
      default:
        return ref.watch(weeklyRankingProvider);
    }
  }

  String get _filterLabel => _filters[_filterIndex];

  @override
  Widget build(BuildContext context) {
    final rankingAsync = _rankingAsync;
    final me = ref.watch(authStateNotifierProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const AppBottomNav(currentIndex: 4),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('🏆 Ranking',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('📅', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(_filterLabel,
                          style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ],
              ),
            ),

            // ── Filter chips ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Row(
                children: _filters.asMap().entries.map((e) {
                  final isActive = e.key == _filterIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _filterIndex = e.key),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary : AppColors.surface,
                        border: Border.all(
                            color: isActive
                                ? AppColors.primary
                                : AppColors.border),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        e.value,
                        style: TextStyle(
                            color:
                                isActive ? Colors.white : AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),

            // ── Content ──────────────────────────────────────────────
            Expanded(
              child: rankingAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
                error: (e, _) => Center(
                    child: Text('$e',
                        style: const TextStyle(color: AppColors.accent))),
                data: (entries) {
                  final currentUserId = me?.userId;
                  final currentUserName = me?.name;
                  final visibleEntries = sanitizeRankingEntries(
                    entries,
                    currentUserId: currentUserId,
                    currentUserName: currentUserName,
                  );

                  if (visibleEntries.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🏆', style: TextStyle(fontSize: 48)),
                          SizedBox(height: 12),
                          Text(
                            'Nenhum participante ainda',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Complete quizzes para aparecer no ranking!',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  final displayModel = buildRankingDisplayModel(visibleEntries);
                  final top3 = displayModel.podiumEntries;
                  final rest = displayModel.listEntries;

                  return Column(
                    children: [
                      // ── Top 3 Pódio ─────────────────────────────
                      if (top3.length >= 3)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 2nd
                              _PodiumItem(
                                  entry: top3[1], position: 2, size: 48),
                              const SizedBox(width: 8),
                              // 1st (taller)
                              _PodiumItem(
                                  entry: top3[0], position: 1, size: 58),
                              const SizedBox(width: 8),
                              // 3rd
                              _PodiumItem(
                                  entry: top3[2], position: 3, size: 44),
                            ],
                          ).animate().fadeIn(duration: 400.ms),
                        ),

                      const SizedBox(height: 16),

                      // ── Lista ─────────────────────────────────────
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          itemCount: rest.length,
                          itemBuilder: (ctx, i) {
                            final entry = rest[i];
                            final rank = displayModel.listStartRank + i;
                            final isMe = entry.isCurrentUser ||
                                (currentUserId != null &&
                                    currentUserId.isNotEmpty &&
                                    entry.userId == currentUserId);
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? AppColors.primary.withOpacity(0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: isMe
                                    ? Border.all(
                                        color:
                                            AppColors.primary.withOpacity(0.3))
                                    : null,
                              ),
                              child: Row(children: [
                                SizedBox(
                                  width: 20,
                                  child: Text('$rank',
                                      style: TextStyle(
                                          color: isMe
                                              ? AppColors.primary
                                              : AppColors.textMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800),
                                      textAlign: TextAlign.center),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [
                                      AppColors.primary.withOpacity(0.7),
                                      AppColors.accent.withOpacity(0.7)
                                    ]),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                      child: Text(_initials(entry.name),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800))),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isMe ? '${entry.name} 👋' : entry.name,
                                        style: TextStyle(
                                            color: isMe
                                                ? AppColors.primary
                                                : AppColors.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700),
                                      ),
                                      if (entry.totalQuestoes > 0)
                                        Text(
                                          '${entry.totalQuestoes} questões · ${entry.accuracy.toStringAsFixed(0)}% acertos',
                                          style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 10),
                                        ),
                                      if (entry.streakDays > 0)
                                        Text(
                                          '🔥 ${entry.streakDays} dias',
                                          style: const TextStyle(
                                              color: AppColors.streakOrange,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600),
                                        ),
                                    ],
                                  ),
                                ),
                                Text('${entry.xp} XP',
                                    style: const TextStyle(
                                        color: AppColors.xpGold,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800)),
                              ]),
                            )
                                .animate(delay: (i * 40).ms)
                                .fadeIn()
                                .slideX(begin: 0.05);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final p = trimmed.split(' ').where((s) => s.isNotEmpty).toList();
    if (p.length >= 2) return '${p.first[0]}${p.last[0]}'.toUpperCase();
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }
}

class _PodiumItem extends StatelessWidget {
  const _PodiumItem(
      {required this.entry, required this.position, required this.size});
  final RankingEntry entry;
  final int position;
  final double size;

  static String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final p = trimmed.split(' ').where((s) => s.isNotEmpty).toList();
    if (p.length >= 2) return '${p.first[0]}${p.last[0]}'.toUpperCase();
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = {
      1: [const Color(0xFFF39C12), const Color(0xFFE67E22)],
      2: [const Color(0xFFBDC3C7), const Color(0xFF95A5A6)],
      3: [const Color(0xFFCD7F32), const Color(0xFFA0522D)],
    };
    final posColors = {
      1: [const Color(0xFFF39C12), '🥇 1°'],
      2: [const Color(0xFFBDC3C7), '🥈 2°'],
      3: [const Color(0xFFCD7F32), '🥉 3°'],
    };
    final grad = colors[position] ?? [AppColors.primary, AppColors.accent];
    final posData = posColors[position];
    final posColor = (posData?[0] as Color?) ?? Colors.grey;
    final posLabel = (posData?[1] as String?) ?? '';

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (position == 1) const Text('👑', style: TextStyle(fontSize: 18)),
          if (position != 1) const SizedBox(height: 20),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: grad), shape: BoxShape.circle),
            child: Center(
                child: Text(_initials(entry.name),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.28,
                        fontWeight: FontWeight.w800))),
          ),
          const SizedBox(height: 4),
          Text(entry.name.split(' ').first,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          Text('${entry.xp} XP',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          if (entry.totalQuestoes > 0)
            Text(
              '${entry.accuracy.toStringAsFixed(0)}%',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
            ),
          if (entry.streakDays > 0)
            Text(
              '🔥${entry.streakDays}d',
              style: const TextStyle(
                  color: AppColors.streakOrange,
                  fontSize: 9,
                  fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: posColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(posLabel,
                style: TextStyle(
                    color: posColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
