import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/auth/application/login_biometric_auth_coordinator.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';
import 'package:quiz_vance_flutter/features/auth/data/login_biometric_vault.dart';
import 'package:quiz_vance_flutter/features/auth/presentation/login_screen.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockLoginBiometricCoordinator extends Mock
    implements LoginBiometricAuthCoordinator {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAuthRepository authRepository;
  late _MockLoginBiometricCoordinator biometricCoordinator;

  Future<void> pumpLoginScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) => authRepository),
          loginBiometricAuthCoordinatorProvider
              .overrideWith((ref) => biometricCoordinator),
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
    biometricCoordinator = _MockLoginBiometricCoordinator();
    when(() => authRepository.restorePersistedSession()).thenAnswer(
      (_) async => const PersistedAuthSession.none(),
    );
    when(() => authRepository.getCachedUser()).thenAnswer(
      (_) async => null,
    );
    when(() => biometricCoordinator.canAuthenticate())
        .thenAnswer((_) async => false);
    when(() => biometricCoordinator.canUnlock()).thenAnswer((_) async => false);
    when(() => biometricCoordinator.clear()).thenAnswer((_) async {});
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

  testWidgets('login screen offers remembering the authenticated session',
      (tester) async {
    await pumpLoginScreen(tester);

    expect(find.byKey(const Key('standard_login_form')), findsOneWidget);
    expect(find.text('Lembrar meu login'), findsOneWidget);
    expect(
      tester.widget<Checkbox>(find.byType(Checkbox).first).value,
      isTrue,
    );
  });

  testWidgets(
      'remembered account pre-fills login ID and stays on standard login form',
      (tester) async {
    when(() => authRepository.getCachedUser()).thenAnswer(
      (_) async => {
        'id': '7',
        'login_id': 'promyr',
        'name': 'Belchior',
        'role': 'admin',
      },
    );

    await pumpLoginScreen(tester);

    expect(find.byKey(const Key('standard_login_form')), findsOneWidget);
    expect(find.byKey(const Key('session_unlock_panel')), findsNothing);
    expect(find.text('ID de acesso ou e-mail'), findsOneWidget);
    expect(find.text('Lembrar meu login'), findsOneWidget);
    expect(find.text('Esqueci minha senha'), findsOneWidget);

    final loginIdField = tester.widget<TextFormField>(
      find.byKey(const Key('login_id_field')),
    );
    expect(loginIdField.controller?.text, 'promyr');
  });

  testWidgets('when biometrics is ready, displays quick biometric access button',
      (tester) async {
    when(() => authRepository.getCachedUser()).thenAnswer(
      (_) async => {
        'id': '7',
        'login_id': 'promyr',
        'name': 'Belchior',
        'role': 'admin',
      },
    );
    when(() => biometricCoordinator.canAuthenticate())
        .thenAnswer((_) async => true);
    when(() => biometricCoordinator.canUnlock()).thenAnswer((_) async => true);

    await pumpLoginScreen(tester);

    expect(find.byKey(const Key('biometric_login_button')), findsOneWidget);
    expect(find.text('Entrar com digital como Belchior'), findsOneWidget);
    expect(find.text('ou entre com sua senha'), findsOneWidget);
    expect(find.byKey(const Key('standard_login_form')), findsOneWidget);
  });

  testWidgets('tapping biometric login button triggers unlock coordinator',
      (tester) async {
    when(() => authRepository.getCachedUser()).thenAnswer(
      (_) async => {
        'id': '7',
        'login_id': 'promyr',
        'name': 'Belchior',
        'role': 'admin',
      },
    );
    when(() => biometricCoordinator.canAuthenticate())
        .thenAnswer((_) async => true);
    when(() => biometricCoordinator.canUnlock()).thenAnswer((_) async => true);
    when(() => biometricCoordinator.unlock())
        .thenThrow(const LoginBiometricCancelled());

    await pumpLoginScreen(tester);

    final bioButton = find.byKey(const Key('biometric_login_button'));
    await tester.ensureVisible(bioButton);
    await tester.tap(bioButton);
    await tester.pump(const Duration(milliseconds: 100));

    verify(() => biometricCoordinator.unlock()).called(1);
  });

  testWidgets(
      'when device supports biometrics but not enrolled, offers enrollment checkbox',
      (tester) async {
    when(() => biometricCoordinator.canAuthenticate())
        .thenAnswer((_) async => true);
    when(() => biometricCoordinator.canUnlock()).thenAnswer((_) async => false);

    await pumpLoginScreen(tester);

    expect(find.byKey(const Key('biometric_login_button')), findsNothing);
    expect(find.byKey(const Key('enroll_biometrics_checkbox')), findsOneWidget);
    expect(
      find.text('Acessar com digital nos próximos logins'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('enroll_biometrics_checkbox')))
          .value,
      isTrue,
    );
  });
}
