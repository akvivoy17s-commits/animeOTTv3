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
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final base = ApiConfig.baseUrl;
    if (base == null) {
      throw DriveAgentException('Server URL not configured (API_BASE_URL).');
    }
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw DriveAgentException('Please sign in again.');

    final uri = Uri.parse('$base$path');
    // Render free tier sleeps: wake it up first (cold start can take ~60s).
    if (path != '/health') await _warm(base);
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

  static DateTime? _lastWarm;

  /// Pings /health once every 4 min (long timeout) so real calls don't hit a sleeping server.
  static Future<void> _warm(String base) async {
    final now = DateTime.now();
    if (_lastWarm != null && now.difference(_lastWarm!).inMinutes < 4) return;
    try {
      await http
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 90));
      _lastWarm = DateTime.now();
    } catch (_) {}
  }

  /// Call when the Drive Agent page opens.
  static Future<void> warmUp() async {
    final base = ApiConfig.baseUrl;
    if (base != null) await _warm(base);
  }

  /// Preview runs as a server-side job: start it, then poll until done (no single long request).
  static Future<Map<String, dynamic>> plan(String url, String category) async {
    try {
      await _call('POST', '/drive/plan/start',
          body: {'folder_url': url, 'category': category},
          timeout: const Duration(seconds: 90));
    } on DriveAgentException catch (e) {
      if (!e.message.contains('already in progress')) rethrow; // else just keep polling
    }
    final end = DateTime.now().add(const Duration(minutes: 8));
    while (DateTime.now().isBefore(end)) {
      await Future.delayed(const Duration(seconds: 2));
      Map<String, dynamic> r;
      try {
        r = await _call('GET', '/drive/plan/result');
      } on DriveAgentException catch (e) {
        if (e.message == 'Server timed out.' ||
            e.message == 'Cannot reach the server.') {
          continue; // transient: keep polling
        }
        rethrow;
      }
      switch (r['state']) {
        case 'done':
          return Map<String, dynamic>.from(r['result'] as Map);
        case 'error':
          throw DriveAgentException(
              (r['error'] as String?)?.isNotEmpty == true
                  ? r['error'] as String
                  : 'Preview failed.');
        case 'idle':
          throw DriveAgentException('Preview was interrupted. Try again.');
      }
    }
    throw DriveAgentException('Preview is taking too long. Try again.');
  }

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

  static Future<Map<String, dynamic>> status() async {
    try {
      return await _call('GET', '/drive/status');
    } on DriveAgentException catch (e) {
      if (e.message != 'Server timed out.') rethrow;
      return _call('GET', '/drive/status'); // one silent retry
    }
  }

  static Future<int> retryFailed() async {
    final r = await _call('POST', '/drive/retry-failed');
    return (r['reset'] as num?)?.toInt() ?? 0;
  }

  /// Tell the Drive Agent that videos were deleted from the app so it forgets them
  /// (they will show as new if detected again). Best-effort: never throws, because
  /// the server also self-heals on the next Preview/Start.
  static Future<void> forget(
      {List<String> videoIds = const [], List<String> urls = const []}) async {
    if (videoIds.isEmpty && urls.isEmpty) return;
    const n = 500;
    try {
      for (var i = 0; i < videoIds.length || i < urls.length; i += n) {
        await _call('POST', '/drive/forget', body: {
          'video_ids': videoIds.skip(i).take(n).toList(),
          'urls': urls.skip(i).take(n).toList(),
        });
      }
    } catch (_) {}
  }
}
