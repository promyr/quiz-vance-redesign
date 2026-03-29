import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/auth/presentation/login_screen.dart';

void main() {
  test('usesSharedBackend identifies the shared production backend', () {
    expect(usesSharedBackend('https://quiz-vance-redesign-backend.fly.dev'), isTrue);
    expect(usesSharedBackend('http://localhost:8000'), isFalse);
  });

  test('backendHostLabel extracts host when URL is valid', () {
    expect(
      backendHostLabel('https://quiz-vance-redesign-backend.fly.dev'),
      'quiz-vance-redesign-backend.fly.dev',
    );
    expect(
      backendHostLabel('http://localhost:8000'),
      'localhost',
    );
  });

  test('backendHostLabel preserves original value for invalid URLs', () {
    expect(backendHostLabel('backend-invalido'), 'backend-invalido');
  });
}
