import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import 'app_pressable.dart';

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
}

const _navItems = [
  _NavItem(
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
    label: 'Hoje',
    route: '/',
  ),
  _NavItem(
    icon: Icons.auto_awesome_outlined,
    activeIcon: Icons.auto_awesome_rounded,
    label: 'Estudar',
    route: '/estudar',
  ),
  _NavItem(
    icon: Icons.local_library_outlined,
    activeIcon: Icons.local_library_rounded,
    label: 'Biblioteca',
    route: '/library',
  ),
  _NavItem(
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
    label: 'Perfil',
    route: '/profile',
  ),
];

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.90),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.border.withOpacity(0.8),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(_navItems.length, (i) {
                  final item = _navItems[i];
                  final isActive = i == currentIndex;
                  return Expanded(
                    child: AppPressable(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        context.go(item.route);
                      },
                      semanticLabel: item.label,
                      semanticHint:
                          isActive ? 'Aba atual' : 'Abrir aba ${item.label}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.primary.withOpacity(0.22)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              border: isActive
                                  ? Border.all(
                                      color: AppColors.primaryLight
                                          .withOpacity(0.4),
                                      width: 1,
                                    )
                                  : null,
                            ),
                            child: Icon(
                              isActive ? item.activeIcon : item.icon,
                              size: 20,
                              color: isActive
                                  ? AppColors.primaryLight
                                  : AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w500,
                              color: isActive
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
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
        ),
      ),
    );
  }
}
