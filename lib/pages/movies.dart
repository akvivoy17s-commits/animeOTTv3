import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../ui/media.dart';
import '../ui/neo.dart';
import '../ui/refresh.dart';
import 'video_play.dart';
import '../ui/save_menu.dart';

class MoviesPage extends StatefulWidget {
  const MoviesPage({super.key});

  @override
  State<MoviesPage> createState() => _MoviesPageState();
}

class _MoviesPageState extends State<MoviesPage> {
  static const int _pageSize = 20;

  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _all = [];
  int _shown = _pageSize;
  String _query = '';
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _search.addListener(_onSearch);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      _loading = !silent;
      _error = false;
    });
    try {
      // videos collection only; category is stored as 'movies'
      // (whereIn also accepts older 'Movies' documents)
      final snap = await FirebaseFirestore.instance
          .collection('videos')
          .where('category', whereIn: const ['movies', 'Movies'])
          .orderBy('createdAt', descending: true)
          .get();
      if (!mounted) return;
      setState(() {
        _all = snap.docs;
        _shown = _pageSize;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Movies loading error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _onSearch() {
    final q = _search.text.trim().toLowerCase();
    if (q == _query) return;
    setState(() {
      _query = q;
      _shown = _pageSize;
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 300 && _shown < _filtered.length) {
      setState(() => _shown += _pageSize);
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filtered {
    if (_query.isEmpty) return _all;
    bool has(Map<String, dynamic> d, String k) =>
        (d[k]?.toString().toLowerCase() ?? '').contains(_query);
    return _all.where((doc) {
      final d = doc.data();
      return has(d, 'title') ||
          has(d, 'name') ||
          has(d, 'description') ||
          has(d, 'episode') ||
          has(d, 'season');
    }).toList();
  }

  void _open(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VideoPlayPage(videoId: id, playlistId: '')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, c) {
          final spec = GridSpec.of(c.maxWidth);
          final list = _filtered;
          final visible = list.take(_shown).toList();

          return NeoRefresh(onRefresh: () => _load(silent: true), child: CustomScrollView(
physics: const AlwaysScrollableScrollPhysics(),
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: PageHeader(overline: 'Library // Movies', title: 'Movies', pad: spec.pad),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(spec.pad, 0, spec.pad, 16),
                  child: NeoSearchField(controller: _search, hint: 'Search movies...'),
                ),
              ),
              if (_loading)
                SkeletonGrid(spec: spec)
              else if (_error)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(text: 'Unable to load movies', onRetry: _load),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.movie_outlined,
                    text: _query.isEmpty ? 'No movies available' : 'No movies found',
                    sub: _query.isEmpty ? null : 'Try a different keyword',
                  ),
                )
              else ...[
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: spec.pad),
                  sliver: SliverGrid(
                    gridDelegate: spec.delegate,
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final doc = visible[i];
                        final d = doc.data();
                        return FadeIn(
                          index: i,
                          child: PosterCard(
                            title: titleOf(d, 'Untitled Movie'),
                            thumb: thumbOf(d),
                            badge: 'MOVIE',
                            badgeColor: Neo.pink,
                            saveCollection: 'videos',
                            saveId: doc.id,
                            saved: isSavedData(d, 'videos'),
                            sub: d['description']?.toString().trim(),
                            onTap: () => _open(doc.id),
                          ),
                        );
                      },
                      childCount: visible.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Center(
                      child: visible.length < list.length
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Neo.cyan),
                            )
                          : Text(
                              '${list.length} MOVIES // END',
                              style: const TextStyle(
                                color: Neo.muted,
                                fontFamily: Neo.mono,
                                fontSize: 10,
                                letterSpacing: 2,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ));
        },
      ),
    );
  }
}
