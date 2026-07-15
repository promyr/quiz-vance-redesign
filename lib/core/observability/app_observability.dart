import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _redactedValue = '[REDACTED]';
final _sensitiveAttributeName = RegExp(
  r'(authorization|cookie|credential|password|passwd|secret|token|api[_-]?key)',
  caseSensitive: false,
);
final _credentialInText = RegExp(
  r'(?:(?:bearer|basic)\s+[^\s,;]+)|(?:(?:password|passwd|secret|token|api[_-]?key|authorization)\s*[:=]\s*[^\s,;]+)',
  caseSensitive: false,
);

enum AppEventLevel {
  info,
  warning,
  error,
}

@immutable
class AppObservedEvent {
  const AppObservedEvent({
    required this.name,
    required this.level,
    required this.timestamp,
    this.attributes = const <String, Object?>{},
    this.error,
    this.stackTrace,
  });

  final String name;
  final AppEventLevel level;
  final DateTime timestamp;
  final Map<String, Object?> attributes;
  final Object? error;
  final StackTrace? stackTrace;
}

class AppObservability {
  AppObservability({this.maxEntries = 100});

  static final AppObservability instance = AppObservability();

  final int maxEntries;
  final ListQueue<AppObservedEvent> _recentEvents =
      ListQueue<AppObservedEvent>();

  List<AppObservedEvent> get recentEvents =>
      List<AppObservedEvent>.unmodifiable(_recentEvents);

  void trackEvent(
    String name, {
    AppEventLevel level = AppEventLevel.info,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    final safeAttributes = _sanitizeAttributes(attributes);
    final event = AppObservedEvent(
      name: name,
      level: level,
      timestamp: DateTime.now(),
      attributes: safeAttributes,
    );
    _record(event);
    developer.log(
      name,
      name: 'QuizVance',
      level: _developerLevel(level),
      error: safeAttributes.isEmpty ? null : safeAttributes,
    );
  }

  void reportError(
    String name,
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    final safeAttributes = _sanitizeAttributes(attributes);
    final safeError = error.runtimeType.toString();
    final event = AppObservedEvent(
      name: name,
      level: AppEventLevel.error,
      timestamp: DateTime.now(),
      attributes: safeAttributes,
      error: safeError,
      stackTrace: stackTrace,
    );
    _record(event);
    developer.log(
      name,
      name: 'QuizVance',
      level: 1000,
      error: safeError,
    );
  }

  void _record(AppObservedEvent event) {
    _recentEvents.addLast(event);
    while (_recentEvents.length > maxEntries) {
      _recentEvents.removeFirst();
    }
  }

  int _developerLevel(AppEventLevel level) {
    switch (level) {
      case AppEventLevel.info:
        return 800;
      case AppEventLevel.warning:
        return 900;
      case AppEventLevel.error:
        return 1000;
    }
  }

  Map<String, Object?> _sanitizeAttributes(Map<String, Object?> attributes) {
    return Map<String, Object?>.unmodifiable(
      attributes.map(
        (key, value) => MapEntry(
          key,
          _sensitiveAttributeName.hasMatch(key)
              ? _redactedValue
              : _sanitizeValue(value),
        ),
      ),
    );
  }

  Object? _sanitizeValue(Object? value) {
    if (value is Map) {
      return Map<String, Object?>.unmodifiable(
        value.map(
          (key, nestedValue) {
            final normalizedKey = key.toString();
            return MapEntry(
              normalizedKey,
              _sensitiveAttributeName.hasMatch(normalizedKey)
                  ? _redactedValue
                  : _sanitizeValue(nestedValue),
            );
          },
        ),
      );
    }
    if (value is Iterable) {
      return List<Object?>.unmodifiable(value.map(_sanitizeValue));
    }
    if (value is String) {
      return value.replaceAll(_credentialInText, _redactedValue);
    }
    return value;
  }
}

final appObservabilityProvider = Provider<AppObservability>(
  (ref) => AppObservability.instance,
);
