/// Build-time environment. Set with --dart-define, never with secrets:
///   flutter build apk --dart-define=ENV=dev --dart-define=API_URL=http://192.168.1.20:3000
class AppConfig {
  const AppConfig._();

  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static bool get isProd => env == 'production';
  static bool get isDev => env == 'dev';
}
