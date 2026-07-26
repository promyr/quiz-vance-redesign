import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../features/profile/presentation/premium_upsell_dialog.dart';

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    required this.quantity,
    required this.isPremium,
    required this.onChanged,
    this.maxFreeLimit = 10,
    this.infiniteMode = false,
    super.key,
  });

  final int quantity;
  final bool isPremium;
  final ValueChanged<int> onChanged;
  final int maxFreeLimit;
  final bool infiniteMode;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: infiniteMode ? 0.35 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: infiniteMode,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Botão Diminuir (-)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: quantity > 1
                          ? () {
                              HapticFeedback.selectionClick();
                              onChanged(quantity - 1);
                            }
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: quantity > 1
                              ? AppColors.surface
                              : AppColors.surface.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Icon(
                          Icons.remove_rounded,
                          color: quantity > 1
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Display Numeral Central
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$quantity',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            quantity == 1 ? 'questão' : 'questões',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Botão Aumentar (+)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (!isPremium && quantity >= maxFreeLimit) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Contas grátis geram até $maxFreeLimit questões por vez. Assine o Premium para ilimitado!',
                              ),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          showPremiumUpsell(context);
                          return;
                        }
                        onChanged(quantity + 1);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: (!isPremium && quantity >= maxFreeLimit)
                              ? AppColors.xpGold.withOpacity(0.15)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (!isPremium && quantity >= maxFreeLimit)
                                ? AppColors.xpGold.withOpacity(0.5)
                                : AppColors.border,
                          ),
                        ),
                        child: Icon(
                          (!isPremium && quantity >= maxFreeLimit)
                              ? Icons.lock_rounded
                              : Icons.add_rounded,
                          color: (!isPremium && quantity >= maxFreeLimit)
                              ? AppColors.xpGold
                              : AppColors.textPrimary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Chips de Atalho Numérico Rápido
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [3, 5, 10, 15, 20, 30].map((q) {
                    final isSelected = quantity == q;
                    final isLocked = !isPremium && q > maxFreeLimit;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (isLocked) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Para gerar $q questões de uma vez, assine o Premium!',
                              ),
                            ),
                          );
                          showPremiumUpsell(context);
                          return;
                        }
                        onChanged(q);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withOpacity(0.18)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : (isLocked
                                    ? AppColors.xpGold.withOpacity(0.3)
                                    : AppColors.border),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            if (isLocked) ...[
                              const Icon(
                                Icons.lock_rounded,
                                size: 10,
                                color: AppColors.xpGold,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              '$q',
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.primary
                                    : (isLocked
                                        ? AppColors.xpGold
                                        : AppColors.textSecondary),
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
