/// Tela de onboarding exibida apenas no primeiro lançamento do app.
///
/// Fluxo:
///  1. Três slides animados apresentando o Quiz Vance.
///  2. Ao concluir (botão "Começar" no último slide), grava a flag
///     [_kOnboardingShownKey] em SharedPreferences e navega para '/'.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';

// ── Controle de exibição ───────────────────────────────────────────────────

const _kOnboardingShownKey = 'onboarding_shown_v1';

/// Retorna true se o onboarding ainda não foi exibido.
Future<bool> shouldShowOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return !(prefs.getBool(_kOnboardingShownKey) ?? false);
}

/// Marca o onboarding como concluído.
Future<void> markOnboardingShown() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingShownKey, true);
}

// ── Dados dos slides ───────────────────────────────────────────────────────

class _Slide {
  const _Slide({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color accentColor;
}

const _slides = [
  _Slide(
    emoji: '🧠',
    title: 'Bem-vindo ao Quiz Vance',
    subtitle:
        'Estude de forma inteligente com quizzes gerados por IA personalizados para o seu ritmo e nível.',
    accentColor: AppColors.primary,
  ),
  _Slide(
    emoji: '⚡',
    title: 'IA que trabalha por você',
    subtitle:
        'Gere questões sobre qualquer tema, faça simulados de concurso cronometrados e receba correções detalhadas.',
    accentColor: Color(0xFF7C3AED),
  ),
  _Slide(
    emoji: '🏆',
    title: 'Evolua e vença',
    subtitle:
        'Acumule XP, suba de nível, mantenha sua sequência de estudos e dispute o ranking com outros alunos.',
    accentColor: Color(0xFFF59E0B),
  ),
];

// ── Widget principal ───────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await markOnboardingShown();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Botão "Pular" ────────────────────────────────────────
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 18, 0),
                child: _currentPage < _slides.length - 1
                    ? GestureDetector(
                        onTap: _finish,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(
                            'Pular',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(height: 24),
              ),
            ),

            // ── Slides ───────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (ctx, i) => _SlideView(slide: _slides[i]),
              ),
            ),

            // ── Indicadores ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (i) {
                  final active = i == _currentPage;
                  final color = _slides[_currentPage].accentColor;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? color : AppColors.border,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  );
                }),
              ),
            ),

            // ── CTA ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: GestureDetector(
                onTap: _next,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _slides[_currentPage].accentColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _slides[_currentPage].accentColor.withOpacity(0.30),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _currentPage < _slides.length - 1 ? 'Próximo →' : 'Começar agora',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Slide individual ───────────────────────────────────────────────────────

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Emoji grande com glow
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: slide.accentColor.withOpacity(0.12),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: slide.accentColor.withOpacity(0.20),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Center(
              child: Text(slide.emoji, style: const TextStyle(fontSize: 52)),
            ),
          )
              .animate()
              .scale(duration: 450.ms, curve: Curves.elasticOut),

          const SizedBox(height: 36),

          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          )
              .animate()
              .fadeIn(delay: 100.ms)
              .slideY(begin: 0.06, end: 0),

          const SizedBox(height: 16),

          Text(
            slide.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              height: 1.6,
            ),
          )
              .animate()
              .fadeIn(delay: 180.ms)
              .slideY(begin: 0.06, end: 0),
        ],
      ),
    );
  }
}
