import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/network/backend_warmup.dart';
import 'router.dart';
import '../shared/providers/offline_sync_provider.dart';
import '../shared/providers/auth_provider.dart';
import '../shared/providers/network_status_provider.dart';

class QuizVanceApp extends ConsumerStatefulWidget {
  const QuizVanceApp({super.key});

  @override
  ConsumerState<QuizVanceApp> createState() => _QuizVanceAppState();
}

class _QuizVanceAppState extends ConsumerState<QuizVanceApp>
    with WidgetsBindingObserver {
  Timer? _syncTimer;
  void _syncPending() {
    if (!mounted ||
        ref.read(authStateNotifierProvider).valueOrNull?.isAuthenticated !=
            true) {
      return;
    }
    unawaited(ref.read(offlineSyncCoordinatorProvider).synchronize());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTimer =
        Timer.periodic(const Duration(seconds: 60), (_) => _syncPending());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (shouldWarmBackendOnLifecycleState(state)) {
      unawaited(BackendWarmup.instance.warmUp());
      _syncPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateNotifierProvider, (_, next) {
      if (next.valueOrNull?.isAuthenticated == true) _syncPending();
    });
    if (ref.watch(authStateNotifierProvider).valueOrNull?.isAuthenticated ==
        true) {
      ref.listen(networkStatusNotifierProvider, (previous, online) {
        if (online && previous == false) _syncPending();
      });
    }
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Quiz Vance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: router,
    );
  }
}
