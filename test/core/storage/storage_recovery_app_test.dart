import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/core/storage/storage_recovery_app.dart';

void main() {
  testWidgets('mantem tela segura quando a recuperacao falha', (tester) async {
    await tester.pumpWidget(
      StorageRecoveryApp(
        onRetry: () => throw StateError('keystore unavailable'),
        onRecovered: () async {},
      ),
    );

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ainda não foi possível'), findsOneWidget);
  });
}
