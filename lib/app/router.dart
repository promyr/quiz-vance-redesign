import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/conquistas/presentation/conquistas_screen.dart';
import '../features/flashcard/presentation/flashcard_hub_screen.dart';
import '../features/flashcard/presentation/flashcard_screen.dart';
import '../features/history/presentation/activity_history_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/library/domain/library_model.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/library/presentation/study_package_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/open_quiz/presentation/open_quiz_screen.dart';
import '../features/profile/domain/premium_entry_mode.dart';
import '../features/profile/presentation/premium_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/quiz/domain/question_model.dart';
import '../features/quiz/presentation/quiz_config_screen.dart';
import '../features/quiz/presentation/quiz_result_screen.dart';
import '../features/quiz/presentation/quiz_session_screen.dart'
    show QuizGenerationParams, QuizSessionScreen;
import '../features/ranking/presentation/ranking_screen.dart';
import '../features/settings/presentation/api_keys_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/simulado/presentation/simulado_config_screen.dart';
import '../features/simulado/presentation/simulado_result_screen.dart';
import '../features/simulado/presentation/simulado_review_screen.dart';
import '../features/simulado/presentation/simulado_screen.dart';
import '../features/stats/presentation/stats_screen.dart';
import '../features/study_plan/presentation/study_plan_screen.dart';
import '../shared/providers/auth_provider.dart';

const _bootRoute = '/boot';

final onboardingGateProvider = FutureProvider<bool>((ref) async {
  try {
    return await shouldShowOnboarding().timeout(const Duration(seconds: 2));
  } catch (_) {
    // O onboarding nao pode bloquear o bootstrap do app.
    return false;
  }
});

bool isAppBootstrapLoading({
  required bool authLoading,
  required bool authHasValue,
  required bool onboardingLoading,
  required bool onboardingHasValue,
}) {
  final authBootstrapping = authLoading && !authHasValue;
  final onboardingBootstrapping = onboardingLoading && !onboardingHasValue;
  return authBootstrapping || onboardingBootstrapping;
}

String? resolveAppRedirect({
  required bool authLoading,
  required bool isAuthenticated,
  required bool shouldShowOnboardingFlag,
  required String location,
  String? pendingLocation,
}) {
  final isBootRoute = location == _bootRoute;
  final isLoginRoute = location == '/login';
  final isOnboardingRoute = location == '/onboarding';

  if (authLoading) {
    if (isBootRoute) return null;
    final from = Uri.encodeComponent(location);
    return '$_bootRoute?from=$from';
  }

  if (isBootRoute) {
    if (shouldShowOnboardingFlag) return '/onboarding';
    if (!isAuthenticated) return '/login';

    final target = pendingLocation;
    if (target != null &&
        target.isNotEmpty &&
        target != _bootRoute &&
        target != '/login' &&
        target != '/onboarding') {
      return target;
    }

    return '/';
  }

  if (!isOnboardingRoute && shouldShowOnboardingFlag) {
    return '/onboarding';
  }

  if (!isAuthenticated && !isLoginRoute && !isOnboardingRoute) {
    return '/login';
  }

  if (isAuthenticated && (isLoginRoute || isOnboardingRoute)) {
    return '/';
  }

  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final onboardingState = ref.watch(onboardingGateProvider);

  return GoRouter(
    initialLocation: _bootRoute,
    redirect: (context, state) {
      final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;
      final bootstrapLoading = isAppBootstrapLoading(
        authLoading: authState.isLoading,
        authHasValue: authState.hasValue,
        onboardingLoading: onboardingState.isLoading,
        onboardingHasValue: onboardingState.hasValue,
      );

      return resolveAppRedirect(
        authLoading: bootstrapLoading,
        isAuthenticated: isAuthenticated,
        shouldShowOnboardingFlag: onboardingState.valueOrNull ?? false,
        location: state.matchedLocation,
        pendingLocation: state.uri.queryParameters['from'],
      );
    },
    routes: [
      GoRoute(
        path: _bootRoute,
        name: 'boot',
        builder: (context, state) => const _BootstrapScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/quiz',
        name: 'quizConfig',
        builder: (context, state) => const QuizConfigScreen(),
        routes: [
          GoRoute(
            path: 'session',
            name: 'quizSession',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return QuizSessionScreen(
                questions: (extra?['questions'] as List<dynamic>? ?? const [])
                    .whereType<Question>()
                    .toList(),
                generationParams:
                    extra?['generationParams'] as QuizGenerationParams?,
                infiniteMode: (extra?['infiniteMode'] as bool?) ?? false,
              );
            },
          ),
          GoRoute(
            path: 'result',
            name: 'quizResult',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              final result = extra?['result'] as QuizResult?;
              if (result == null) {
                return const HomeScreen();
              }
              return QuizResultScreen(result: result);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/flashcards',
        name: 'flashcards',
        builder: (context, state) => const FlashcardHubScreen(),
        routes: [
          GoRoute(
            path: 'review',
            name: 'flashcardsReview',
            builder: (context, state) => const FlashcardScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/simulado',
        name: 'simulado',
        builder: (context, state) => const SimuladoConfigScreen(),
        routes: [
          GoRoute(
            path: 'session',
            name: 'simuladoSession',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return SimuladoScreen(
                questions: (extra?['questions'] as List<dynamic>? ?? const [])
                    .whereType<Question>()
                    .toList(),
                durationSeconds: (extra?['durationSeconds'] as int?) ?? 3600,
              );
            },
          ),
          GoRoute(
            path: 'result',
            name: 'simuladoResult',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return SimuladoResultScreen(result: extra?['result']);
            },
          ),
          GoRoute(
            path: 'review',
            name: 'simuladoReview',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return SimuladoReviewScreen(result: extra?['result']);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/ranking',
        name: 'ranking',
        builder: (context, state) => const RankingScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/premium',
        name: 'premium',
        builder: (context, state) => PremiumScreen(
          entryMode:
              premiumEntryModeFromQuery(state.uri.queryParameters['entry']),
        ),
      ),
      GoRoute(
        path: '/conquistas',
        name: 'conquistas',
        builder: (context, state) => const ConquistasScreen(),
      ),
      GoRoute(
        path: '/stats',
        name: 'stats',
        builder: (context, state) => const StatsScreen(),
      ),
      GoRoute(
        path: '/history',
        name: 'history',
        builder: (context, state) => const ActivityHistoryScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'api-keys',
            name: 'apiKeys',
            builder: (context, state) => const ApiKeysScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/open-quiz',
        name: 'openQuiz',
        builder: (context, state) => const OpenQuizScreen(),
      ),
      GoRoute(
        path: '/study-plan',
        name: 'studyPlan',
        builder: (context, state) => const StudyPlanScreen(),
      ),
      GoRoute(
        path: '/library',
        name: 'library',
        builder: (context, state) => const LibraryScreen(),
        routes: [
          GoRoute(
            path: 'package',
            name: 'libraryPackage',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              if (extra == null ||
                  extra['package'] is! StudyPackage ||
                  extra['file'] is! LibraryFile) {
                return const LibraryScreen();
              }
              return StudyPackageScreen(
                package: extra['package'] as StudyPackage,
                file: extra['file'] as LibraryFile,
              );
            },
          ),
        ],
      ),
    ],
  );
});

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
