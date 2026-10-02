import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../observability/app_observability.dart';

enum BackendWarmupResult { ready, unavailable }

typedef BackendPing = Future<void> Function();

bool shouldWarmBackendOnLifecycleState(AppLifecycleState state) {
  return state == AppLifecycleState.resumed;
}

/// Starts the backend while the user is still navigating to authentication.
///
/// Calls are deduplicated while a health check is in flight. Failures are
/// intentionally contained because warm-up is an optimization; the actual
/// request remains responsible for displaying an actionable error.
class BackendWarmup {
  BackendWarmup({
    required BackendPing ping,
    AppObservability? observability,
  })  : _ping = ping,
        _observability = observability ?? AppObservability.instance;

  static final BackendWarmup instance = BackendWarmup(
    ping: _productionPing,
  );

  final BackendPing _ping;
  final AppObservability _observability;
  Future<BackendWarmupResult>? _inFlight;

  Future<BackendWarmupResult> warmUp() {
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  Future<BackendWarmupResult> _run() async {
    final stopwatch = Stopwatch()..start();
    try {
      await _ping();
      _observability.trackEvent(
        'backend.warmup_ready',
        attributes: {'elapsed_ms': stopwatch.elapsedMilliseconds},
      );
      return BackendWarmupResult.ready;
    } catch (_) {
      _observability.trackEvent(
        'backend.warmup_unavailable',
        level: AppEventLevel.warning,
        attributes: {'elapsed_ms': stopwatch.elapsedMilliseconds},
      );
      return BackendWarmupResult.unavailable;
    }
  }

  static Future<void> _productionPing() async {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.backendUrl,
        connectTimeout: authWarmupTimeout,
        sendTimeout: authWarmupTimeout,
        receiveTimeout: authWarmupTimeout,
        headers: {
          'X-App-Version': AppConfig.appVersion,
          'X-Client-App': AppConfig.clientAppId,
        },
      ),
    );
    await dio.get<void>('/health/ready');
  }
}

const authWarmupTimeout = Duration(seconds: 75);
