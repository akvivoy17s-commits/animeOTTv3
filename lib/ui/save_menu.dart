import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'neo.dart';

/// LEGACY: saved state used to live as a flag on the shared playlist/video
/// document (visible to every user). Saves are now per-user, stored under
/// `users/{uid}/saved/{collection}_{docId}`. The old flags are ignored, so
/// this always returns false; real state comes from [SaveService.isSaved].
bool isSavedData(Map<String, dynamic> data, String collection) => false;

/// Per-user save list. Every save is a document in the *current user's own*
/// `saved` sub-collection, so one user's Save / Remove never touches anyone
/// else's list (admin accounts are just users and work the same way).
class SaveService {
  static String? get uid => FirebaseAuth.instance.currentUser?.uid;

  static String keyFor(String collection, String id) => '${collection}_$id';

  static CollectionReference<Map<String, dynamic>> savedRef(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('saved');

  static Future<bool> isSaved(String collection, String id) async {
    final u = uid;
    if (u == null) return false;
    final snap = await savedRef(u).doc(keyFor(collection, id)).get();
    return snap.exists;
  }

  static Future<void> save(String collection, String id) {
    final u = uid;
    if (u == null) return Future.error('Please log in to save');
    return savedRef(u).doc(keyFor(collection, id)).set({
      'collection': collection,
      'itemId': id,
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> remove(String collection, String id) {
    final u = uid;
    if (u == null) return Future.error('Please log in first');
    return savedRef(u).doc(keyFor(collection, id)).delete();
  }
}

/// Vertical three-dot button. Tap -> small "Save" menu -> saves the item
/// into the current user's own save list.
class SaveMenuButton extends StatefulWidget {
  final String collection; // 'playlists' or 'videos'
  final String docId;
  final bool saved;
  final double size;

  /// Used on the SaveList page: menu shows "Remove" instead of "Save".
  final bool removeMode;
  final VoidCallback? onChanged;

  const SaveMenuButton({
    super.key,
    required this.collection,
    required this.docId,
    this.saved = false,
    this.size = 30,
    this.removeMode = false,
    this.onChanged,
  });

  @override
  State<SaveMenuButton> createState() => _SaveMenuButtonState();
}

class _SaveMenuButtonState extends State<SaveMenuButton> {
  late bool _saved = widget.saved;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant SaveMenuButton old) {
    super.didUpdateWidget(old);
    if (old.saved != widget.saved || old.docId != widget.docId) {
      _saved = widget.saved;
    }
  }

  Future<void> _open() async {
    // Sync with the current user's save list first, so cards that were
    // built earlier (Home / Movies / Series) never show a stale Saved state.
    if (!widget.removeMode) {
      try {
        final fresh = await SaveService.isSaved(widget.collection, widget.docId);
        if (mounted && fresh != _saved) setState(() => _saved = fresh);
      } catch (_) {}
    }
    if (!mounted) return;

    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context);
    final ovBox = overlay.context.findRenderObject() as RenderBox;
    final tl = box.localToGlobal(Offset.zero, ancestor: ovBox);
    final sz = ovBox.size;
    const w = 130.0, h = 44.0;
    var left = (tl.dx + box.size.width - w).clamp(8.0, sz.width - w - 8);
    var top = tl.dy + box.size.height + 4;
    if (top + h > sz.height - 8) top = tl.dy - h - 4;

    final remove = widget.removeMode;
    final enabled = remove || !_saved;
    _close();
    // Non-blocking menu: the translucent Listener only *observes* touches,
    // so the page underneath keeps scrolling while the menu is open.
    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _close(),
              onPointerSignal: (_) => _close(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: w,
            height: h,
            child: Material(
              color: Neo.surface,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Neo.line),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: enabled
                    ? () {
                        _close();
                        remove ? _remove() : _save();
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(
                        remove
                            ? Icons.bookmark_remove_rounded
                            : (_saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                        size: 18,
                        color: remove ? Neo.pink : Neo.cyan,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        remove ? 'Remove' : (_saved ? 'Saved' : 'Save'),
                        style: TextStyle(
                          color: enabled ? Neo.text : Neo.text.withValues(alpha: 0.5),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
  }

  OverlayEntry? _entry;

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await SaveService.save(widget.collection, widget.docId);
      if (mounted) setState(() => _saved = true);
      messenger?.showSnackBar(const SnackBar(
        content: Text('Saved'),
        duration: Duration(seconds: 1),
      ));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      _busy = false;
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await SaveService.remove(widget.collection, widget.docId);
      if (mounted) setState(() => _saved = false);
      widget.onChanged?.call();
      messenger?.showSnackBar(const SnackBar(
        content: Text('Removed from Saved'),
        duration: Duration(seconds: 1),
      ));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not remove: $e')));
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Icon(Icons.more_vert_rounded, size: 18, color: Colors.white),
      ),
    );
  }
}
