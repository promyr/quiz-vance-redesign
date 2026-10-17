import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/settings/application/admin_biometric_auth_coordinator.dart';
import 'package:quiz_vance_flutter/features/settings/data/admin_biometric_auth_service.dart';
import 'package:quiz_vance_flutter/features/settings/data/admin_master_keys_service.dart';
import 'package:quiz_vance_flutter/features/settings/domain/admin_authorization.dart';
import 'package:quiz_vance_flutter/features/settings/presentation/admin_master_keys_screen.dart';

class _MockAdminBiometrics extends Mock
    implements AdminBiometricAuthCoordinator {}

void main() {
  testWidgets('leaving admin cancels mutation after delayed biometrics',
      (tester) async {
    final biometrics = _MockAdminBiometrics();
    final authorization = Completer<AdminAuthorization>();
    var serviceReads = 0;
    when(biometrics.canAuthorize).thenAnswer((_) async => true);
    when(() => biometrics.authorize(scope: AdminStepUpScope.deleteAiKey))
        .thenAnswer((_) => authorization.future);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        adminBiometricAuthCoordinatorProvider.overrideWithValue(biometrics),
        adminMasterKeysListProvider.overrideWith((_) async => const [
              MasterApiKeyEntry(
                id: 'key-1',
                provider: 'groq',
                maskedKey: '••••test',
                label: 'Principal',
                priority: 1,
                isActive: true,
                healthStatus: 'healthy',
              ),
            ]),
        adminMasterKeysServiceProvider.overrideWith((_) {
          serviceReads++;
          throw StateError('mutation must not start after leaving admin');
        }),
      ],
      child: const MaterialApp(home: AdminMasterKeysScreen()),
    ));
    await tester.pumpAndSettle();
    final deleteButton = find.byIcon(Icons.delete_outline_rounded);
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pump();
    verify(() => biometrics.authorize(scope: AdminStepUpScope.deleteAiKey))
        .called(1);

    await tester.pumpWidget(const SizedBox.shrink());
    authorization.complete(AdminAuthorization.biometric('test-authorization'));
    await tester.pump();

    expect(serviceReads, 0);
    expect(tester.takeException(), isNull);
  });
}
