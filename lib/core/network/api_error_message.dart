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

String translateApiErrorMessage(String rawMessage) {
  final lower = rawMessage.trim().toLowerCase();

  if (lower.contains('resource_exhausted') ||
      lower.contains('quota exceeded') ||
      lower.contains('rate limit')) {
    return 'Cota de geração excedida no provedor de IA. Tente novamente mais tarde ou verifique suas Chaves de API.';
  }
  if (lower.contains('invalid credentials') ||
      lower.contains('invalid email or password') ||
      lower.contains('user not found')) {
    return 'Credenciais inválidas. Verifique seu ID/e-mail ou senha e tente novamente.';
  }
  if (lower.contains('code is invalid') ||
      lower.contains('invalid code') ||
      lower.contains('code expired') ||
      lower.contains('invalid_code')) {
    return 'O código informado é inválido ou expirou. Solicite um novo código por e-mail.';
  }
  if (lower.contains('email already registered') ||
      lower.contains('user already exists') ||
      lower.contains('already in use')) {
    return 'Este e-mail ou ID de acesso já está em uso por outra conta.';
  }
  if (lower.contains('field required') || lower.contains('missing required field')) {
    return 'Preencha todos os campos obrigatórios para continuar.';
  }
  if (lower.contains('internal server error')) {
    return 'Ocorreu um erro temporário no servidor. Tente novamente em alguns instantes.';
  }
  if (lower.contains('unauthorized') || lower.contains('could not validate credentials')) {
    return 'Sessão expirada. Faça login novamente para continuar.';
  }
  if (lower.contains('network error') || lower.contains('failed to connect')) {
    return 'Falha na conexão de rede. Verifique sua internet e tente novamente.';
  }

  return rawMessage;
}

String userVisibleErrorMessage(
  Object error, {
  required String fallback,
  int maxLength = 180,
}) {
  if (error is RemoteServiceException) {
    return translateApiErrorMessage(error.message);
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

  return translateApiErrorMessage(normalized);
}

RemoteServiceException buildRemoteServiceException(
  DioException error, {
  required String fallback,
  String? connectivityFallback,
}) {
  final detail = extractApiErrorMessage(error.response?.data);
  if (detail != null) {
    return RemoteServiceException(translateApiErrorMessage(detail));
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
