import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';
import 'package:quiz_vance_flutter/features/auth/presentation/login_screen.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAuthRepository authRepository;

  Future<void> pumpLoginScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) => authRepository),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    authRepository = _MockAuthRepository();
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession.none(),
    );
  });

  testWidgets('login screen does not expose backend internals', (tester) async {
    await pumpLoginScreen(tester);

    expect(find.textContaining('Servidor:'), findsNothing);
    expect(find.textContaining('backend'), findsNothing);
    expect(find.textContaining('Use o mesmo backend'), findsNothing);
  });

  testWidgets('login screen shows official logo and polished copy',
      (tester) async {
    await pumpLoginScreen(tester);

    expect(find.text('Quiz Vance'), findsOneWidget);
    expect(find.text('ID de acesso ou e-mail'), findsOneWidget);
    expect(find.text('Digite seu ID ou e-mail'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
