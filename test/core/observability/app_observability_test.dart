import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/core/observability/app_observability.dart';

void main() {
  test('mantém somente o número máximo de eventos recentes', () {
    final observability = AppObservability(maxEntries: 2);

    observability.trackEvent('event.one');
    observability.trackEvent('event.two');
    observability.trackEvent('event.three');

    expect(
      observability.recentEvents.map((event) => event.name).toList(),
      equals(<String>['event.two', 'event.three']),
    );
  });

  test('reportError registra evento de erro com stack trace', () {
    final observability = AppObservability(maxEntries: 5);
    final stackTrace = StackTrace.current;

    observability.reportError(
      'quiz.generate_failed',
      StateError('boom'),
      stackTrace,
      attributes: const <String, Object?>{'provider': 'gemini'},
    );

    final event = observability.recentEvents.single;
    expect(event.name, equals('quiz.generate_failed'));
    expect(event.level, equals(AppEventLevel.error));
    expect(event.error, isA<StateError>());
    expect(event.stackTrace, equals(stackTrace));
    expect(event.attributes['provider'], equals('gemini'));
  });
}
