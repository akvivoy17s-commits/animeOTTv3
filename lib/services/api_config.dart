import 'package:flutter/foundation.dart';

/// Backend (FastAPI) base URL used by the Drive Agent.
/// Release: flutter build <apk|web> --release --dart-define=API_BASE_URL=https://api.yourdomain.com
class ApiConfig {
  ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// null => not configured (only possible in release builds).
  static String? get baseUrl {
    if (_override.isNotEmpty) {
      return _override.endsWith('/')
          ? _override.substring(0, _override.length - 1)
          : _override;
    }
    if (kReleaseMode) return null; // never fall back to localhost in release
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'https://animeottv3.onrender.com'; // Android emulator -> host PC
    }
    return 'https://animeottv3.onrender.com';
  }
}
