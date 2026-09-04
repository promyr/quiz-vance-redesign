import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

import 'app/app.dart';
import 'core/notifications/streak_notif.dart';
import 'core/observability/app_observability.dart';
import 'core/storage/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final observability = AppObservability.instance;

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF0F172A),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFF59E0B),
                  size: 48,
                ),
                SizedBox(height: 16),
                Text(
                  'Ops! Ocorreu um erro na exibição.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Tente voltar à tela anterior ou reiniciar o aplicativo.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

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

  try {
    if (Platform.isAndroid) {
      open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    }
    await LocalStorage.instance.init();
    observability.trackEvent('app.storage_initialized');
  } catch (error, stackTrace) {
    observability.reportError('app.storage_init_failed', error, stackTrace);
  }

  try {
    await StreakNotif.instance.init();
    await StreakNotif.instance.scheduleDailyReminder();
    observability.trackEvent('app.notifications_ready');
  } catch (error, stackTrace) {
    observability.reportError(
      'app.notifications_failed',
      error,
      stackTrace,
    );
    // Notificacoes nao podem impedir o app de iniciar em desktop.
  }

  runZonedGuarded(
    () {
      observability.trackEvent('app.startup_complete');
      runApp(const ProviderScope(child: QuizVanceApp()));
    },
    (error, stackTrace) {
      observability.reportError('flutter.zone_error', error, stackTrace);
    },
  );
}
