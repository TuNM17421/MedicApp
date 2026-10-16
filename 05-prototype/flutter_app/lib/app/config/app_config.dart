/// Build-time configuration. Only the backend URL is configured here; the
/// OpenAI key lives in `05-prototype/backend/.env` and never reaches the app.
abstract final class AppConfig {
  /// USB development: `adb reverse tcp:8080 tcp:8080` maps the phone's
  /// localhost to the computer running the backend.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );
}
