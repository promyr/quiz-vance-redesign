import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/premium_entry_mode.dart';

const _kLastShownKey = 'premium_upsell_last_shown_date';

Future<bool> shouldShowPremiumUpsell() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(_kLastShownKey);
  final today = DateTime.now().toIso8601String().substring(0, 10);
  return stored != today;
}

Future<void> markPremiumUpsellShown() async {
  final prefs = await SharedPreferences.getInstance();
  final today = DateTime.now().toIso8601String().substring(0, 10);
  await prefs.setString(_kLastShownKey, today);
}

Future<void> showPremiumUpsell(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.7),
    builder: (_) => const _PremiumUpsellSheet(),
  );
}

class _PremiumUpsellSheet extends StatelessWidget {
  const _PremiumUpsellSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: AppColors.goldGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFE66D).withOpacity(0.35),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFF1A1200),
                size: 30,
              ),
            ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
            const SizedBox(height: 16),
            const Text(
              'Quiz Vance Premium',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 80.ms),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFE66D).withOpacity(0.15),
                    const Color(0xFFFFB347).withOpacity(0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFFFE66D).withOpacity(0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFFFFE66D),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: 'Seu primeiro dia é ',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                          TextSpan(
                            text: 'Premium grátis',
                            style: TextStyle(
                              color: Color(0xFFFFE66D),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              height: 1.45,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' para explorar tudo sem custo no dia do cadastro.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.06, end: 0),
            const SizedBox(height: 18),
            ..._benefits.asMap().entries.map((entry) {
              final index = entry.key;
              final benefit = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check_rounded,
                          color: AppColors.primary,
                          size: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            benefit.title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (benefit.subtitle != null)
                            Text(
                              benefit.subtitle!,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                )
                    .animate()
                    .fadeIn(delay: Duration(milliseconds: 200 + index * 50))
                    .slideX(begin: -0.04, end: 0),
              );
            }),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                context.push(premiumRouteForEntry(PremiumEntryMode.subscribe));
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFE66D).withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      color: Color(0xFF1A1200),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Quero ser Premium',
                      style: TextStyle(
                        color: Color(0xFF1A1200),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.05, end: 0),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Agora não',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 560.ms),
          ],
        ),
      ),
    );
  }
}

class _Benefit {
  const _Benefit(this.title, {this.subtitle});

  final String title;
  final String? subtitle;
}

const _benefits = [
  _Benefit(
    'Quizzes ilimitados com IA',
    subtitle: 'Gere questões sobre qualquer tema, sem restrições.',
  ),
  _Benefit(
    'Simulados completos cronometrados',
    subtitle: 'Monte sessões longas, com mais contexto e menos atrito.',
  ),
  _Benefit(
    'Flashcards com repetição espaçada',
    subtitle: 'Use o algoritmo FSRS para revisar com mais eficiência.',
  ),
  _Benefit(
    'Plano de estudo personalizado por IA',
    subtitle: 'Receba um roteiro semanal ajustado ao seu objetivo.',
  ),
  _Benefit(
    'Biblioteca de materiais de estudo',
    subtitle: 'Gere pacotes didáticos e reaproveite conteúdo na revisão.',
  ),
  _Benefit(
    'Questões dissertativas com correção IA',
    subtitle: 'Veja feedback detalhado nas respostas abertas.',
  ),
  _Benefit(
    'Rankings, XP e conquistas',
    subtitle: 'Mantenha motivação com sinais reais de progresso.',
  ),
];
