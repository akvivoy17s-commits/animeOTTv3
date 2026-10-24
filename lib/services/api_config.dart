/// Backend (FastAPI) base URL used by the Drive Agent.
/// Override if needed: flutter run --dart-define=API_BASE_URL=https://other-host.com
class ApiConfig {
  ApiConfig._();

  static const String _default = 'https://animeott-backend.onrender.com';
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String? get baseUrl {
    final url = _override.isNotEmpty ? _override : _default;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
}