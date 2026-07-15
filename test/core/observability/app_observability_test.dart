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

  test('reportError registra tipo do erro sem mensagem sensivel', () {
    final observability = AppObservability(maxEntries: 5);
    final stackTrace = StackTrace.current;

    observability.reportError(
      'quiz.generate_failed',
      StateError('password=segredo-supersecreto'),
      stackTrace,
      attributes: const <String, Object?>{
        'provider': 'gemini',
        'access_token': 'jwt-secreto',
      },
    );

    final event = observability.recentEvents.single;
    expect(event.name, equals('quiz.generate_failed'));
    expect(event.level, equals(AppEventLevel.error));
    expect(event.error, equals('StateError'));
    expect(event.stackTrace, equals(stackTrace));
    expect(event.attributes['provider'], equals('gemini'));
    expect(event.attributes['access_token'], equals('[REDACTED]'));
    expect(event.toString(), isNot(contains('segredo-supersecreto')));
    expect(event.toString(), isNot(contains('jwt-secreto')));
  });

  test('trackEvent mascara segredos aninhados e tokens bearer', () {
    final observability = AppObservability(maxEntries: 5);

    observability.trackEvent(
      'network.failed',
      attributes: const <String, Object?>{
        'headers': <String, Object?>{
          'Authorization': 'Bearer token-secreto',
        },
        'password': 'senha-secreta',
      },
    );

    final serialized = observability.recentEvents.single.attributes.toString();
    expect(serialized, isNot(contains('token-secreto')));
    expect(serialized, isNot(contains('senha-secreta')));
    expect(serialized, contains('[REDACTED]'));
  });
}
