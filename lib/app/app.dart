import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/network/backend_warmup.dart';
import 'router.dart';

class QuizVanceApp extends ConsumerStatefulWidget {
  const QuizVanceApp({super.key});

  @override
  ConsumerState<QuizVanceApp> createState() => _QuizVanceAppState();
}

class _QuizVanceAppState extends ConsumerState<QuizVanceApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (shouldWarmBackendOnLifecycleState(state)) {
      unawaited(BackendWarmup.instance.warmUp());
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Quiz Vance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: router,
    );
  }
}
