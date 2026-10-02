import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/settings/data/admin_master_keys_service.dart';
import 'package:quiz_vance_flutter/features/settings/presentation/admin_key_test_feedback.dart';

void main() {
  testWidgets('shows sanitized status and diagnostic code', (tester) async {
    const result = ApiKeyTestResult(
      isValid: false,
      message: 'provider response containing a secret',
      latencyMs: 31,
      errorCode: 'payload_too_large',
      providerStatus: 413,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdminKeyTestFeedback(result: result),
        ),
      ),
    );

    expect(
      find.text(
        'A requisição excedeu o limite do provedor; a chave não foi recusada.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Código: payload_too_large · HTTP 413'),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('shows success without an error diagnostic', (tester) async {
    const result = ApiKeyTestResult(
      isValid: true,
      message: 'Chave funcional',
      latencyMs: 18,
      providerStatus: 200,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdminKeyTestFeedback(result: result),
        ),
      ),
    );

    expect(find.text('Chave funcional'), findsOneWidget);
    expect(find.textContaining('Código:'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });
}
