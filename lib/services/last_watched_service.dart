import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Stores ONLY the single most recent video a user watched.
///
/// Path: users/{uid}/state/lastWatched
///
/// `set()` without merge replaces the whole document, so whenever a new
/// video is saved the previous one is overwritten automatically.
/// No separate delete step is needed.
class LastWatched {
  final String videoId;
  final String playlistId;
  final String title;
  final String thumbnail;
  final int positionSeconds;

  const LastWatched({
    required this.videoId,
    required this.playlistId,
    required this.title,
    required this.thumbnail,
    required this.positionSeconds,
  });

  Duration get position => Duration(seconds: positionSeconds);
}

class LastWatchedService {
  LastWatchedService._();

  static DocumentReference<Map<String, dynamic>>? _ref() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('state')
        .doc('lastWatched');
  }

  // ==========================================================
  // SAVE (overwrites the previous video)
  // ==========================================================

  static Future<void> save({
    required String videoId,
    required String playlistId,
    required String title,
    required String thumbnail,
    required int positionSeconds,
  }) async {
    try {
      final ref = _ref();
      if (ref == null || videoId.isEmpty) return;

      await ref.set({
        'videoId': videoId,
        'playlistId': playlistId,
        'title': title,
        'thumbnail': thumbnail,
        'positionSeconds': positionSeconds,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Never break video playback because of a save failure.
      // ignore: avoid_print
      print('LastWatched save error: $e');
    }
  }

  // ==========================================================
  // LOAD
  // ==========================================================

  static Future<LastWatched?> load() async {
    try {
      final ref = _ref();
      if (ref == null) return null;

      final snap = await ref.get();
      final data = snap.data();
      if (!snap.exists || data == null) return null;

      final videoId = (data['videoId'] ?? '').toString();
      if (videoId.isEmpty) return null;

      return LastWatched(
        videoId: videoId,
        playlistId: (data['playlistId'] ?? '').toString(),
        title: (data['title'] ?? '').toString(),
        thumbnail: (data['thumbnail'] ?? '').toString(),
        positionSeconds: (data['positionSeconds'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      // ignore: avoid_print
      print('LastWatched load error: $e');
      return null;
    }
  }
}
