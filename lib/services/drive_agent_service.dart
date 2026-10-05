import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class DriveAgentException implements Exception {
  final String message;
  DriveAgentException(this.message);
  @override
  String toString() => message;
}

/// Talks to the backend /drive/* endpoints (admin-only, Firebase ID token).
class DriveAgentService {
  DriveAgentService._();

  static Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final base = ApiConfig.baseUrl;
    if (base == null) {
      throw DriveAgentException('Server URL not configured (API_BASE_URL).');
    }
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw DriveAgentException('Please sign in again.');

    final uri = Uri.parse('$base$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    try {
      final http.Response r = method == 'GET'
          ? await http.get(uri, headers: headers).timeout(timeout)
          : await http
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(timeout);
      final dynamic data =
          r.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        return data is Map<String, dynamic> ? data : <String, dynamic>{};
      }
      final detail = data is Map ? data['detail'] : null;
      throw DriveAgentException(
          detail is String ? detail : 'Server error (${r.statusCode})');
    } on DriveAgentException {
      rethrow;
    } on TimeoutException {
      throw DriveAgentException('Server timed out.');
    } on http.ClientException {
      throw DriveAgentException('Cannot reach the server.');
    } on FormatException {
      throw DriveAgentException('Unexpected server response.');
    }
  }

  static Future<Map<String, dynamic>> plan(String url, String category) =>
      _call('POST', '/drive/plan',
          body: {'folder_url': url, 'category': category},
          timeout: const Duration(seconds: 120));

  static Future<void> start(String url, String category,
          {bool retryFailed = false,
          int? limit,
          Map<String, Map<String, dynamic>> edits = const {}}) =>
      _call('POST', '/drive/start', body: {
        'folder_url': url,
        'category': category,
        'retry_failed': retryFailed,
        if (limit != null) 'limit': limit,
        if (edits.isNotEmpty) 'edits': edits, // file_id -> edited fields only
      });

  static Future<void> stop() => _call('POST', '/drive/stop');

  static Future<Map<String, dynamic>> status() => _call('GET', '/drive/status');

  static Future<int> retryFailed() async {
    final r = await _call('POST', '/drive/retry-failed');
    return (r['reset'] as num?)?.toInt() ?? 0;
  }
}
