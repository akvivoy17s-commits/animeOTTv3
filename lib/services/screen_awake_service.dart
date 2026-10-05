import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device screen on ONLY while a video is playing.
/// Owner-based: the screen stays on while ANY owner is playing, so an old
/// player page disposing can never switch off a newer one (next video).
class ScreenAwakeService {
  ScreenAwakeService._();

  static final Set<Object> _owners = <Object>{};
  static bool _on = false;

  /// [owner] wants the screen on while [playing] is true.
  /// [refresh] re-asserts the OS lock (after app resume / web tab visible).
  static void set(Object owner, bool playing, {bool refresh = false}) {
    if (playing) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
    _apply(refresh: refresh);
  }

  static void release(Object owner) {
    _owners.remove(owner);
    _apply();
  }

  static Future<void> _apply({bool refresh = false}) async {
    final want = _owners.isNotEmpty;
    if (want == _on && !(refresh && want)) return; // only talk to OS on change
    _on = want;
    try {
      want ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (e) {
      if (_on == want) _on = !want; // allow a retry on the next update
      debugPrint('ScreenAwake error: $e');
    }
  }
}
