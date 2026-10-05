import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../ui/media.dart';
import '../ui/neo.dart';
import '../ui/refresh.dart';
import '../ui/save_menu.dart';
import 'playlist_videos.dart';

class SeriesPage extends StatefulWidget {
  const SeriesPage({super.key});

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      final q = _search.text.trim().toLowerCase();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, c) {
          final spec = GridSpec.of(c.maxWidth);
          return NeoRefresh(onRefresh: () => refreshFromServer(const ['playlists']), child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('playlists')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              final header = SliverToBoxAdapter(
                child: PageHeader(overline: 'Library // Series', title: 'Series', pad: spec.pad),
              );
              final searchBar = SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(spec.pad, 0, spec.pad, 16),
                  child: NeoSearchField(controller: _search, hint: 'Search series...'),
                ),
              );

              if (snap.hasError) {
                return CustomScrollView(
keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
physics: const AlwaysScrollableScrollPhysics(), slivers: [
                  header,
                  searchBar,
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorState(text: 'Unable to load series'),
                  ),
                ]);
              }

              if (!snap.hasData) {
                return CustomScrollView(
keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
physics: const AlwaysScrollableScrollPhysics(), slivers: [header, searchBar, SkeletonGrid(spec: spec)]);
              }

              final all = snap.data!.docs;
              final docs = all.where((d) => matchesQuery(d.data(), _query)).toList();
              if (docs.isEmpty) {
                return CustomScrollView(
keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
physics: const AlwaysScrollableScrollPhysics(), slivers: [
                  header,
                  searchBar,
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.video_library_outlined,
                      text: _query.isEmpty ? 'No series available' : 'No series found',
                      sub: _query.isEmpty ? null : 'Try a different keyword',
                    ),
                  ),
                ]);
              }

              return CustomScrollView(
keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
physics: const AlwaysScrollableScrollPhysics(), slivers: [
                  header,
                  searchBar,
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(spec.pad, 4, spec.pad, 14),
                      child: SectionHeader(
                        title: 'All Series',
                        tag: '${docs.length} titles',
                        color: Neo.cyan,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: spec.pad),
                    sliver: SliverGrid(
                      gridDelegate: spec.delegate,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final doc = docs[i];
                          final data = doc.data();
                          final name = titleOf(data, 'Untitled Series');
                          return FadeIn(
                            index: i,
                            child: PosterCard(
                              title: name,
                              thumb: thumbOf(data),
                              badge: 'SERIES',
                              sub: data['description']?.toString().trim(),
                              icon: Icons.list_rounded,
                              saveCollection: 'playlists',
                              saveId: doc.id,
                              saved: isSavedData(data, 'playlists'),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PlaylistVideosPage(
                                    playlistId: doc.id,
                                    playlistName: name,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: docs.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              );
            },
          ));
        },
      ),
    );
  }
}
