/// Configurações de ambiente do app.
/// Para trocar a URL em tempo de execução:
///   flutter run --dart-define=BACKEND_URL=http://192.168.1.100:8000
abstract class AppConfig {
  static const String clientAppId = 'quiz-vance-redesign';
  static const String rankingNamespace = 'quiz-vance-redesign-v2';
  static const String defaultBackendUrl =
      'https://quiz-vance-redesign-1.onrender.com';

  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: defaultBackendUrl,
  );

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static const String appName = 'Quiz Vance';
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '2.0.64+63',
  );
}
