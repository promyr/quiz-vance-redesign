import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_error_message.dart';

void main() {
  group('extractApiErrorMessage', () {
    test('extracts plain detail string', () {
      final message = extractApiErrorMessage({
        'detail': 'Configure sua chave de API antes de continuar.',
      });

      expect(message, 'Configure sua chave de API antes de continuar.');
    });

    test('extracts fastapi validation list', () {
      final message = extractApiErrorMessage({
        'detail': [
          {
            'loc': ['body', 'topic'],
            'msg': 'Field required',
          },
        ],
      });

      expect(message, 'topic: Field required');
    });

    test('falls back to message and error fields', () {
      expect(
        extractApiErrorMessage({'message': 'Provider invalido'}),
        'Provider invalido',
      );
      expect(
        extractApiErrorMessage({'error': 'Falha ao gerar quiz'}),
        'Falha ao gerar quiz',
      );
    });
  });

  group('userVisibleErrorMessage', () {
    test('keeps short explicit exception messages', () {
      final message = userVisibleErrorMessage(
        Exception('Configure sua chave de API.'),
        fallback: 'fallback',
      );

      expect(message, 'Configure sua chave de API.');
    });

    test('keeps remote service message', () {
      final message = userVisibleErrorMessage(
        const RemoteServiceException('Servidor indisponivel.'),
        fallback: 'fallback',
      );

      expect(message, 'Servidor indisponivel.');
    });

    test('falls back for technical errors', () {
      final message = userVisibleErrorMessage(
        const FormatException('payload invalido'),
        fallback: 'Mensagem generica',
      );

      expect(message, 'Mensagem generica');
    });
  });
}
