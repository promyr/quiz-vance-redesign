import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final event = AppObservedEvent(
      name: name,
      level: level,
      timestamp: DateTime.now(),
      attributes: Map<String, Object?>.unmodifiable(attributes),
    );
    _record(event);
    developer.log(
      name,
      name: 'QuizVance',
      level: _developerLevel(level),
      error: attributes.isEmpty ? null : attributes,
    );
  }

  void reportError(
    String name,
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> attributes = const <String, Object?>{},
  }) {
    final event = AppObservedEvent(
      name: name,
      level: AppEventLevel.error,
      timestamp: DateTime.now(),
      attributes: Map<String, Object?>.unmodifiable(attributes),
      error: error,
      stackTrace: stackTrace,
    );
    _record(event);
    developer.log(
      name,
      name: 'QuizVance',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
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
}

final appObservabilityProvider = Provider<AppObservability>(
  (ref) => AppObservability.instance,
);
