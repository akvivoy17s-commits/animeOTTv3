import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../ui/media.dart';
import '../ui/neo.dart';
import '../ui/refresh.dart';
import '../ui/save_menu.dart';
import 'playlist_videos.dart';
import 'video_play.dart';

typedef _Doc = DocumentSnapshot<Map<String, dynamic>>;

/// SaveList: the CURRENT USER's own saved playlists and movie videos.
/// Stored per user in `users/{uid}/saved`, so nobody else's Save / Remove
/// can change this list. Live (snapshots): "Remove" makes the card vanish.
class SavedPage extends StatefulWidget {
  const SavedPage({super.key});

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  StreamSubscription? _authSub;
  StreamSubscription? _savedSub;

  // saved entries of this user: key -> savedAt
  final Map<String, DateTime> _savedAt = {};
  // cache of the real playlist / video documents, key -> doc
  final Map<String, _Doc> _cache = {};

  List<_Doc> _series = [];
  List<_Doc> _movies = [];
  bool _loaded = false;
  bool _error = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final q = _search.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
    // emits the current user immediately and again on login / logout
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) => _bind(u?.uid));
  }

  void _bind(String? uid) {
    _savedSub?.cancel();
    _cache.clear();
    _savedAt.clear();
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _series = [];
        _movies = [];
        _loaded = true;
        _error = false;
      });
      return;
    }
    if (mounted) setState(() => _loaded = false);
    _savedSub = SaveService.savedRef(uid).snapshots().listen(_onSaved, onError: _onError);
  }

  Future<void> _onSaved(QuerySnapshot<Map<String, dynamic>> snap) async {
    final gen = ++_gen;
    final entries = <String, Map<String, dynamic>>{};
    for (final d in snap.docs) {
      entries[d.id] = d.data();
    }
    _savedAt
      ..clear()
      ..addEntries(entries.entries.map((e) {
        final t = e.value['savedAt'];
        return MapEntry(e.key, t is Timestamp ? t.toDate() : DateTime.now());
      }));

    // forget removed items, fetch only the new ones
    _cache.removeWhere((k, _) => !entries.containsKey(k));
    final missing = entries.entries.where((e) => !_cache.containsKey(e.key)).toList();
    try {
      final fetched = await Future.wait(missing.map((e) async {
        final col = e.value['collection']?.toString() ?? '';
        final id = e.value['itemId']?.toString() ?? '';
        if ((col != 'playlists' && col != 'videos') || id.isEmpty) return null;
        final doc = await FirebaseFirestore.instance.collection(col).doc(id).get();
        return MapEntry(e.key, doc);
      }));
      if (!mounted || gen != _gen) return; // a newer snapshot already arrived
      for (final f in fetched) {
        if (f != null && f.value.exists) _cache[f.key] = f.value;
      }
      _rebuildLists();
    } catch (e) {
      _onError(e);
    }
  }

  void _rebuildLists() {
    final series = <MapEntry<String, _Doc>>[];
    final movies = <MapEntry<String, _Doc>>[];
    _cache.forEach((k, doc) {
      (k.startsWith('playlists_') ? series : movies).add(MapEntry(k, doc));
    });
    int byNewest(MapEntry<String, _Doc> a, MapEntry<String, _Doc> b) =>
        (_savedAt[b.key] ?? DateTime.now()).compareTo(_savedAt[a.key] ?? DateTime.now());
    series.sort(byNewest);
    movies.sort(byNewest);
    if (!mounted) return;
    setState(() {
      _series = series.map((e) => e.value).toList();
      _movies = movies.map((e) => e.value).toList();
      _loaded = true;
      _error = false;
    });
  }

  void _onError(Object e) {
    debugPrint('Saved load error: $e');
    if (mounted) setState(() => _error = true);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _savedSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Widget _grid(GridSpec spec, List<_Doc> docs, bool isMovie) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: spec.pad),
      sliver: SliverGrid(
        gridDelegate: spec.delegate,
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final doc = docs[i];
            final d = doc.data() ?? <String, dynamic>{};
            final name = titleOf(d, isMovie ? 'Untitled Movie' : 'Untitled Series');
            return FadeIn(
              index: i,
              child: PosterCard(
                key: ValueKey('${isMovie ? 'm' : 's'}_${doc.id}'),
                title: name,
                thumb: thumbOf(d),
                badge: isMovie ? 'MOVIE' : 'SERIES',
                badgeColor: isMovie ? Neo.pink : Neo.cyan,
                sub: d['description']?.toString().trim(),
                icon: isMovie ? Icons.play_arrow_rounded : Icons.list_rounded,
                saveCollection: isMovie ? 'videos' : 'playlists',
                saveId: doc.id,
                saved: true,
                removeMode: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => isMovie
                        ? VideoPlayPage(videoId: doc.id, playlistId: '')
                        : PlaylistVideosPage(playlistId: doc.id, playlistName: name),
                  ),
                ),
              ),
            );
          },
          childCount: docs.length,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NeoRefresh(onRefresh: () async => _bind(SaveService.uid), child: LayoutBuilder(
        builder: (context, c) {
          final spec = GridSpec.of(c.maxWidth);
          final header = SliverToBoxAdapter(
            child: PageHeader(overline: 'Library // Saved', title: 'Saved', pad: spec.pad),
          );

          if (_error) {
            return CustomScrollView(
physics: const AlwaysScrollableScrollPhysics(), slivers: [
              header,
              const SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorState(text: 'Unable to load saved items'),
              ),
            ]);
          }

          if (!_loaded) {
            return CustomScrollView(
physics: const AlwaysScrollableScrollPhysics(), slivers: [header, SkeletonGrid(spec: spec)]);
          }

          if (_series.isEmpty && _movies.isEmpty) {
            return CustomScrollView(
physics: const AlwaysScrollableScrollPhysics(), slivers: [
              header,
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.bookmark_border_rounded,
                  text: 'Nothing saved yet',
                  sub: 'Tap the ••• button on a series or movie and choose Save',
                ),
              ),
            ]);
          }

          final series = _series.where((d) => matchesQuery(d.data() ?? const {}, _query)).toList();
          final movies = _movies.where((d) => matchesQuery(d.data() ?? const {}, _query)).toList();

          return CustomScrollView(
keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
physics: const AlwaysScrollableScrollPhysics(), slivers: [
              header,
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(spec.pad, 0, spec.pad, 16),
                  child: NeoSearchField(controller: _search, hint: 'Search saved...'),
                ),
              ),
              if (series.isEmpty && movies.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    text: 'No saved items found',
                    sub: 'Try a different keyword',
                  ),
                ),
              if (series.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(spec.pad, 4, spec.pad, 14),
                    child: SectionHeader(
                      title: 'Saved Series',
                      tag: '${series.length} saved',
                      color: Neo.cyan,
                    ),
                  ),
                ),
                _grid(spec, series, false),
              ],
              if (movies.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(spec.pad, 24, spec.pad, 14),
                    child: SectionHeader(
                      title: 'Saved Movies',
                      tag: '${movies.length} saved',
                      color: Neo.pink,
                    ),
                  ),
                ),
                _grid(spec, movies, true),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          );
        },
      )),
    );
  }
}
