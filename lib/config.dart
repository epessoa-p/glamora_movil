/// Configuración de compilación.
///
/// La URL de la API se cambia sin tocar código:
///   flutter run --dart-define=API_URL=http://10.0.2.2:8000/api/v1
/// (10.0.2.2 es el "localhost" de la PC vista desde el emulador de Android).
class AppConfig {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://glamora.sczsoft.net/api/v1',
  );

  static const appVersion = '0.1.0';
}
