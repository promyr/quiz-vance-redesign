import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/conquistas/presentation/conquistas_screen.dart';
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
import '../features/settings/presentation/admin_master_keys_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/simulado/presentation/simulado_config_screen.dart';
import '../features/simulado/presentation/simulado_result_screen.dart';
import '../features/simulado/presentation/simulado_review_screen.dart';
import '../features/simulado/presentation/simulado_screen.dart';
import '../features/simulado/data/simulado_recovery_store.dart';
import '../features/stats/presentation/stats_screen.dart';
import '../features/study_plan/presentation/study_plan_screen.dart';
import '../features/study_plan/presentation/today_plan_screen.dart';
import '../features/estudar/presentation/estudar_screen.dart';
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
  bool isAdmin = false,
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

  if (isAuthenticated &&
      (location == '/api-keys' || location == '/settings/api-keys')) {
    return '/settings';
  }

  if (isAuthenticated && location.startsWith('/admin/') && !isAdmin) {
    return '/';
  }

  if (isAuthenticated && (isLoginRoute || isOnboardingRoute)) {
    return '/';
  }

  return null;
}

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(onboardingGateProvider, (_, __) => notifyListeners());
  }
}

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(_routerRefreshProvider);

  final router = GoRouter(
    initialLocation: _bootRoute,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final onboardingState = ref.read(onboardingGateProvider);
      final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;
      final isAdmin = authState.valueOrNull?.isAdmin ?? false;
      final bootstrapLoading = isAppBootstrapLoading(
        authLoading: authState.isLoading,
        authHasValue: authState.hasValue,
        onboardingLoading: onboardingState.isLoading,
        onboardingHasValue: onboardingState.hasValue,
      );

      return resolveAppRedirect(
        authLoading: bootstrapLoading,
        isAuthenticated: isAuthenticated,
        isAdmin: isAdmin,
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
        builder: (context, state) => OnboardingScreen(
          onCompleted: () async {
            ref.invalidate(onboardingGateProvider);
            await ref.read(onboardingGateProvider.future);
          },
        ),
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
        path: '/estudar',
        name: 'estudar',
        builder: (context, state) => const EstudarScreen(),
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
                recoveryKey: extra?['recoveryKey'] as String?,
                questions: (extra?['questions'] as List<dynamic>? ?? const [])
                    .whereType<Question>()
                    .toList(),
                generationParams:
                    extra?['generationParams'] as QuizGenerationParams?,
                infiniteMode: (extra?['infiniteMode'] as bool?) ?? false,
                isErrorRevisionMode:
                    (extra?['isErrorRevisionMode'] as bool?) ?? false,
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
              return QuizResultScreen(
                result: result,
                studyPlanId: extra?['studyPlanId'] as String?,
              );
            },
          ),
        ],
      ),
      GoRoute(path: '/flashcards', redirect: (_, __) => '/estudar'),
      GoRoute(path: '/flashcards/review', redirect: (_, __) => '/estudar'),
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
                checkpoint: extra?['checkpoint'] as SimuladoCheckpoint?,
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
        path: '/admin/keys',
        name: 'adminKeys',
        builder: (context, state) => const AdminMasterKeysScreen(),
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
        path: '/today-plan',
        name: 'todayPlan',
        builder: (context, state) => const TodayPlanScreen(),
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
  ref.onDispose(router.dispose);
  return router;
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
