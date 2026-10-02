import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/core/network/backend_warmup.dart';

void main() {
  test('warmUp deduplica chamadas simultaneas ao health check', () async {
    final response = Completer<void>();
    var calls = 0;
    final warmup = BackendWarmup(
      ping: () {
        calls += 1;
        return response.future;
      },
    );

    final first = warmup.warmUp();
    final second = warmup.warmUp();

    expect(calls, 1);
    response.complete();
    expect(await first, BackendWarmupResult.ready);
    expect(await second, BackendWarmupResult.ready);
  });

  test('warmUp absorve indisponibilidade sem bloquear o aplicativo', () async {
    final warmup = BackendWarmup(
      ping: () async => throw TimeoutException('cold start'),
    );

    expect(await warmup.warmUp(), BackendWarmupResult.unavailable);
  });

  test('somente retorno ao primeiro plano dispara novo aquecimento', () {
    expect(
      shouldWarmBackendOnLifecycleState(AppLifecycleState.resumed),
      isTrue,
    );
    expect(
      shouldWarmBackendOnLifecycleState(AppLifecycleState.paused),
      isFalse,
    );
    expect(
      shouldWarmBackendOnLifecycleState(AppLifecycleState.inactive),
      isFalse,
    );
  });
}
