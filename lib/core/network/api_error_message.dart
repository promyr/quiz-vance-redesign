import 'package:dio/dio.dart';

import '../exceptions/remote_service_exception.dart';

String? extractApiErrorMessage(Object? payload) {
  if (payload == null) return null;

  if (payload is String) {
    final normalized = payload.trim();
    return normalized.isEmpty ? null : normalized;
  }

  if (payload is Map) {
    final validationMessage = _extractValidationMessage(payload);
    if (validationMessage != null) return validationMessage;

    return extractApiErrorMessage(payload['detail']) ??
        extractApiErrorMessage(payload['message']) ??
        extractApiErrorMessage(payload['error']) ??
        extractApiErrorMessage(payload['errors']);
  }

  if (payload is List) {
    final messages = payload
        .map(extractApiErrorMessage)
        .whereType<String>()
        .map((message) => message.trim())
        .where((message) => message.isNotEmpty)
        .toSet()
        .toList();

    if (messages.isEmpty) return null;
    return messages.join('. ');
  }

  return null;
}

String userVisibleErrorMessage(
  Object error, {
  required String fallback,
  int maxLength = 180,
}) {
  if (error is RemoteServiceException) {
    return error.message;
  }

  final raw = error.toString().trim();
  final normalized = raw
      .replaceFirst(RegExp(r'^(Exception|Error):\s*'), '')
      .replaceFirst(RegExp(r'^(Exception|Error)\s*'), '')
      .trim();

  if (normalized.isEmpty || normalized.length > maxLength) {
    return fallback;
  }

  const technicalMarkers = [
    'DioException',
    'TypeError',
    'NoSuchMethodError',
    'StackTrace',
    'FormatException',
    'RangeError',
    'Assertion failed',
  ];

  if (technicalMarkers.any(normalized.contains)) {
    return fallback;
  }

  return normalized;
}

RemoteServiceException buildRemoteServiceException(
  DioException error, {
  required String fallback,
  String? connectivityFallback,
}) {
  final detail = extractApiErrorMessage(error.response?.data);
  if (detail != null) {
    return RemoteServiceException(detail);
  }

  if (_isConnectivityDioException(error)) {
    return RemoteServiceException(connectivityFallback ?? fallback);
  }

  return RemoteServiceException(fallback);
}

String? _extractValidationMessage(Map<dynamic, dynamic> payload) {
  final rawMessage = payload['msg'];
  if (rawMessage is! String || rawMessage.trim().isEmpty) return null;

  final message = rawMessage.trim();
  final rawLoc = payload['loc'];
  if (rawLoc is! List) return message;

  final path = rawLoc
      .map((segment) => segment.toString())
      .where((segment) => segment.isNotEmpty)
      .where((segment) => segment != 'body')
      .where((segment) => segment != 'query')
      .where((segment) => segment != 'path')
      .join('.');

  if (path.isEmpty) return message;
  return '$path: $message';
}

bool _isConnectivityDioException(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return true;
    case DioExceptionType.unknown:
      return error.response == null;
    case DioExceptionType.badCertificate:
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return false;
  }
}
