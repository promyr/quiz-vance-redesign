import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import 'app_pressable.dart';

class _NavItem {
  const _NavItem(
      {required this.emoji, required this.label, required this.route});
  final String emoji;
  final String label;
  final String route;
}

const _navItems = [
  _NavItem(emoji: '🏠', label: 'Início', route: '/'),
  _NavItem(emoji: '🧠', label: 'Quiz', route: '/quiz'),
  _NavItem(emoji: '🗂️', label: 'Cards', route: '/flashcards'),
  _NavItem(emoji: '📚', label: 'Biblioteca', route: '/library'),
  _NavItem(emoji: '📊', label: 'Ranking', route: '/ranking'),
  _NavItem(emoji: '👤', label: 'Perfil', route: '/profile'),
];

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(_navItems.length, (i) {
              final item = _navItems[i];
              final isActive = i == currentIndex;
              return Expanded(
                child: AppPressable(
                  onPressed: () => context.go(item.route),
                  semanticLabel: item.label,
                  semanticHint:
                      isActive ? 'Aba atual' : 'Abrir aba ${item.label}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.emoji,
                        style: TextStyle(fontSize: isActive ? 22 : 20),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                      ),
                      if (isActive)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
