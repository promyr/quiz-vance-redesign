import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/app/startup_failure_app.dart';

void main() {
  testWidgets('shows a recoverable startup failure', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      StartupFailureApp(onRetry: () async => retries++),
    );

    expect(
        find.text('Nao foi possivel abrir seus dados locais'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    expect(retries, 1);
  });
}
