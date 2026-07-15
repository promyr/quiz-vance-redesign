import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

import 'app/app.dart';
import 'app/startup_failure_app.dart';
import 'core/notifications/streak_notif.dart';
import 'core/observability/app_observability.dart';
import 'core/storage/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final observability = AppObservability.instance;

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    observability.reportError(
      'flutter.framework_error',
      details.exception,
      details.stack ?? StackTrace.current,
      attributes: <String, Object?>{
        if (details.library != null) 'library': details.library,
        if (details.context != null)
          'context': details.context!.toDescription(),
      },
    );
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    observability.reportError(
      'flutter.platform_error',
      error,
      stackTrace,
    );
    return false;
  };

  await runZonedGuarded(
    () => _startApplication(observability),
    (error, stackTrace) {
      observability.reportError('flutter.zone_error', error, stackTrace);
    },
  );
}

Future<void> _startApplication(AppObservability observability) async {
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }

  try {
    await LocalStorage.instance.init();
    observability.trackEvent('app.storage_initialized');
  } catch (error, stackTrace) {
    observability.reportError('app.storage_failed', error, stackTrace);
    runApp(
      StartupFailureApp(
        onRetry: () => _startApplication(observability),
      ),
    );
    return;
  }

  try {
    await StreakNotif.instance.init();
    await StreakNotif.instance.scheduleDailyReminder();
    observability.trackEvent('app.notifications_ready');
  } catch (error, stackTrace) {
    observability.reportError('app.notifications_failed', error, stackTrace);
  }

  observability.trackEvent('app.startup_complete');
  runApp(const ProviderScope(child: QuizVanceApp()));
}
