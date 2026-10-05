import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/last_watched_service.dart';
import '../services/screen_awake_service.dart';
import '../ui/manage_ui.dart';
import '../ui/media.dart';
import '../ui/neo.dart';
import '../ui/refresh.dart';

class VideoPlayPage extends StatefulWidget {
  final String videoId;
  final String playlistId;

  /// Resume point (used by the "Continue Watching" popup).
  final Duration? startAt;

  const VideoPlayPage({
    super.key,
    required this.videoId,
    required this.playlistId,
    this.startAt,
  });

  @override
  State<VideoPlayPage> createState() => _VideoPlayPageState();
}

class _VideoPlayPageState extends State<VideoPlayPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  // Last watched tracking
  String _thumbnail = '';
  Timer? _saveTimer;
  bool _wasPlaying = false;

  // ============================================================
  // STATE
  // ============================================================

  bool _loading = true;
  bool _hasError = false;
  bool _fg = true; // app in foreground (screen-awake only matters then)
  bool _showControls = true;

  String _errorMessage = '';
  String _title = '';
  String _season = '';
  String _episode = '';
  String _videoUrl = '';

  double _playbackSpeed = 1.0;

  // More Videos
  List<DocumentSnapshot<Map<String, dynamic>>> _moreVideos = [];
  bool _moreVideosLoaded = false;

  // Previous / Next (episode order inside the playlist)
  String? _prevId;
  String? _nextId;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPage();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();

    // Save the final position BEFORE the controller is disposed.
    _saveLastWatched();

    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    ScreenAwakeService.release(this);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    super.dispose();
  }

  // ============================================================
  // LOAD COMPLETE PAGE
  // ============================================================

  Future<void> _loadPage() async {
    if (!mounted) return;

    _saveTimer?.cancel();
    ScreenAwakeService.release(this);
    _controller?.removeListener(_videoListener);
    await _controller?.dispose();
    _controller = null;

    setState(() {
      _loading = true;
      _hasError = false;
      _errorMessage = '';
      _showControls = true;
      _title = '';
      _season = '';
      _episode = '';
      _videoUrl = '';
      _moreVideos = [];
      _moreVideosLoaded = false;
    });

    try {
      // ----------------------------------------------------------
      // 1. LOAD VIDEO DOCUMENT
      // ----------------------------------------------------------

      final doc = await FirebaseFirestore.instance
          .collection('videos')
          .doc(widget.videoId)
          .get();

      if (!doc.exists) {
        throw Exception('Video not found in Firestore.');
      }

      final data = doc.data();

      if (data == null) {
        throw Exception('Video data is empty.');
      }

      // ----------------------------------------------------------
      // TITLE
      // ----------------------------------------------------------

      _title = _readString(data, [
        'title',
        'name',
        'videoTitle',
      ], fallback: 'Untitled Video');

      // ----------------------------------------------------------
      // SEASON
      // Current video only
      // ----------------------------------------------------------

      _season = _readString(data, ['season', 'seasonNumber']);

      // ----------------------------------------------------------
      // EPISODE
      // Supports multiple possible Firestore field names
      // ----------------------------------------------------------

      _episode = _readString(data, [
        'episodes',
        'episodeNumber',
        'episode',
        'episodeNo',
        'ep',
      ]);

      // ----------------------------------------------------------
      // VIDEO URL
      // ----------------------------------------------------------

      _videoUrl = _readString(data, ['videoUrl', 'url', 'videoURL']);

      if (_videoUrl.isEmpty) {
        throw Exception('Video URL is empty.');
      }

      // ----------------------------------------------------------
      // THUMBNAIL (stored with last watched)
      // ----------------------------------------------------------

      final rawThumb = _readString(data, [
        'thumbnail',
        'thumbnailUrl',
        'imageUrl',
        'posterUrl',
      ]);

      _thumbnail = _getThumbnailUrl(rawThumb.isNotEmpty ? rawThumb : _videoUrl);

      // ----------------------------------------------------------
      // 2. INITIALIZE ACTUAL VIDEO
      // ----------------------------------------------------------

      await _initializeVideo(_videoUrl);

      if (!mounted) return;

      // ----------------------------------------------------------
      // VIDEO READY
      // ----------------------------------------------------------

      setState(() {
        _loading = false;
      });

      debugPrint('VIDEO INITIALIZED - LOADING STOPPED');

      // Save immediately (overwrites previous last watched),
      // then keep updating every 15 seconds.
      _saveLastWatched();
      _startSaveTimer();

      // ----------------------------------------------------------
      // 3. LOAD MORE VIDEOS IN BACKGROUND
      // ----------------------------------------------------------

      _loadMoreVideosInBackground();
    } catch (e) {
      debugPrint('VIDEO PAGE LOAD ERROR: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _hasError = true;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ============================================================
  // READ STRING
  // ============================================================

  String _readString(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value != null) {
        final text = value.toString().trim();

        if (text.isNotEmpty) {
          return text;
        }
      }
    }

    return fallback;
  }

  // ============================================================
  // GOOGLE DRIVE FILE ID
  // ============================================================

  String? _extractDriveFileId(String url) {
    try {
      final uri = Uri.parse(url);

      final segments = uri.pathSegments;

      final dIndex = segments.indexOf('d');

      if (dIndex != -1 && dIndex + 1 < segments.length) {
        final id = segments[dIndex + 1].trim();

        if (id.isNotEmpty) {
          return id;
        }
      }

      final queryId = uri.queryParameters['id'];

      if (queryId != null && queryId.isNotEmpty) {
        return queryId;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // VIDEO URL CANDIDATES
  // ============================================================

  List<String> _buildVideoCandidates(String originalUrl) {
    final clean = originalUrl.trim();

    final candidates = <String>[];

    void add(String? value) {
      if (value == null) return;

      final url = value.trim();

      if (url.isEmpty) return;

      if (!candidates.contains(url)) {
        candidates.add(url);
      }
    }

    // Original URL
    add(clean);

    final fileId = _extractDriveFileId(clean);

    if (fileId != null && fileId.isNotEmpty) {
      add(
        'https://drive.google.com/uc'
        '?export=download&id=$fileId',
      );

      add(
        'https://drive.google.com/uc'
        '?export=download'
        '&confirm=t&id=$fileId',
      );

      add(
        'https://drive.usercontent.google.com/download'
        '?id=$fileId'
        '&export=download'
        '&confirm=t',
      );

      add(
        'https://drive.usercontent.google.com/download'
        '?id=$fileId'
        '&confirm=yes'
        '&export=download',
      );
    }

    return candidates;
  }

  // ============================================================
  // INITIALIZE VIDEO
  // ============================================================

  Future<void> _initializeVideo(String originalUrl) async {
    final candidates = _buildVideoCandidates(originalUrl);

    if (candidates.isEmpty) {
      throw Exception('No valid video URL found.');
    }

    for (final url in candidates) {
      VideoPlayerController? testController;

      try {
        debugPrint('Trying video URL: $url');

        testController = VideoPlayerController.networkUrl(
          Uri.parse(url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
        );

        await testController.initialize();

        await testController.setPlaybackSpeed(_playbackSpeed);

        // Resume from saved position (Continue Watching)
        final startAt = widget.startAt;
        if (startAt != null &&
            startAt > Duration.zero &&
            startAt < testController.value.duration) {
          await testController.seekTo(startAt);
        }

        if (!mounted) {
          await testController.dispose();
          return;
        }

        _controller = testController;

        _controller!.addListener(_videoListener);

        await _controller!.play();

        debugPrint('VIDEO INITIALIZED SUCCESSFULLY');

        return;
      } catch (e) {
        debugPrint('FAILED VIDEO URL: $url');

        debugPrint('VIDEO ERROR: $e');

        await testController?.dispose();
      }
    }

    throw Exception(
      'Google Drive video could not be loaded.\n\n'
      'Please check that the Drive file is accessible '
      'with the link.',
    );
  }

  // ============================================================
  // VIDEO LISTENER
  // ============================================================

  void _videoListener() {
    if (!mounted || _controller == null) {
      return;
    }

    if (_controller!.value.hasError) {
      debugPrint(
        'VideoPlayer error: '
        '${_controller!.value.errorDescription}',
      );
    }

    // Save when the user pauses
    final isPlaying = _controller!.value.isPlaying;
    if (_wasPlaying && !isPlaying) {
      _saveLastWatched();
    }
    _wasPlaying = isPlaying;
    ScreenAwakeService.set(this, isPlaying && _fg); // on only while playing

    if (!_loading) {
      setState(() {});
    }
  }

  // ============================================================
  // LAST WATCHED (Firestore)
  // ============================================================

  void _startSaveTimer() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_controller?.value.isPlaying == true) {
        _saveLastWatched();
      }
    });
  }

  void _saveLastWatched() {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        _title.isEmpty) {
      return;
    }

    final position = controller.value.position;
    final duration = controller.value.duration;

    // Video almost finished -> restart from the beginning next time
    final finished =
        duration > Duration.zero &&
        position >= duration - const Duration(seconds: 10);

    LastWatchedService.save(
      videoId: widget.videoId,
      playlistId: widget.playlistId,
      title: _title,
      thumbnail: _thumbnail,
      positionSeconds: finished ? 0 : position.inSeconds,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveLastWatched();
    }

    // Screen-awake: drop in background, re-assert on return (also web tab visible).
    if (state == AppLifecycleState.resumed) {
      _fg = true;
      ScreenAwakeService.set(this, _controller?.value.isPlaying ?? false,
          refresh: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _fg = false;
      ScreenAwakeService.release(this);
    }
  }

  // ============================================================
  // PLAY / PAUSE
  // ============================================================

  Future<void> _togglePlayPause() async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // SEEK
  // ============================================================

  Future<void> _seekBy(Duration amount) async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final current = controller.value.position;

    final duration = controller.value.duration;

    var target = current + amount;

    if (target < Duration.zero) {
      target = Duration.zero;
    }

    if (target > duration) {
      target = duration;
    }

    await controller.seekTo(target);

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // PLAYBACK SPEED
  // ============================================================

  Future<void> _changePlaybackSpeed(double speed) async {
    final controller = _controller;

    if (controller == null) {
      return;
    }

    await controller.setPlaybackSpeed(speed);

    if (!mounted) return;

    setState(() {
      _playbackSpeed = speed;
    });
  }

  // ============================================================
  // SETTINGS
  // ============================================================

  void _showSettings() {
    showNeoSheet<void>(
      context,
      title: 'Playback Speed',
      sub: 'SETTINGS',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final speed in const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
            _SpeedChip(
              speed: speed,
              selected: (_playbackSpeed - speed).abs() < 0.01,
              onTap: () async {
                await _changePlaybackSpeed(speed);
                if (!mounted) return;
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openFullscreen() async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    if (!mounted) return;

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) {
          return _FullscreenVideoPage(
            controller: controller,
            title: _title,
            playbackSpeed: _playbackSpeed,
            hasPrev: _prevId != null,
            hasNext: _nextId != null,
          );
        },
      ),
    );

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    if (result == 'prev') _goToVideo(_prevId);
    if (result == 'next') _goToVideo(_nextId);
  }

  // ============================================================
  // FORMAT DURATION
  // ============================================================

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;

    final minutes = duration.inMinutes.remainder(60);

    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // VIDEO PLAYER
  // ============================================================

  Widget _buildVideoPlayer() {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    final width = controller.value.size.width;

    final height = controller.value.size.height;

    double ratio = 16 / 9;

    if (width > 0 && height > 0) {
      ratio = width / height;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: ratio,
                child: VideoPlayer(controller),
              ),
            ),
          ),

          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _showControls ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_showControls,
              child: _buildVideoControls(),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // VIDEO CONTROLS
  // ============================================================

  Widget _buildVideoControls() {
    final controller = _controller!;
    final position = controller.value.position;
    final duration = controller.value.duration;

    final durationMs = duration.inMilliseconds;
    final positionMs = position.inMilliseconds;
    final safeMax = durationMs <= 0 ? 1 : durationMs;
    final safeValue = positionMs.clamp(0, safeMax).toDouble();
    final playing = controller.value.isPlaying;

    return Stack(
      children: [
        // ---------------- top bar ----------------
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.75),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                _controlButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  size: 38,
                  iconSize: 18,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Neo.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ---------------- center buttons ----------------
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _controlButton(
                icon: Icons.skip_previous_rounded,
                size: 40,
                iconSize: 24,
                enabled: _prevId != null,
                onTap: () => _goToVideo(_prevId),
              ),
              const SizedBox(width: 12),
              _controlButton(
                icon: Icons.replay_10_rounded,
                size: 46,
                iconSize: 24,
                onTap: () {
                  _seekBy(const Duration(seconds: -10));
                },
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Neo.cyan, Neo.violet],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Neo.cyan.withValues(alpha: 0.55),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Neo.bg,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              _controlButton(
                icon: Icons.forward_10_rounded,
                size: 46,
                iconSize: 24,
                onTap: () {
                  _seekBy(const Duration(seconds: 10));
                },
              ),
              const SizedBox(width: 12),
              _controlButton(
                icon: Icons.skip_next_rounded,
                size: 40,
                iconSize: 24,
                enabled: _nextId != null,
                onTap: () => _goToVideo(_nextId),
              ),
            ],
          ),
        ),

        // ---------------- bottom bar ----------------
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 14, 8, 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 22,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: Neo.cyan,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Neo.cyan.withValues(alpha: 0.2),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
                    child: Slider(
                      min: 0,
                      max: safeMax.toDouble(),
                      value: safeValue,
                      onChanged: (value) {
                        controller.seekTo(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                ),
                SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      Text(
                        '${_formatDuration(position)} / '
                        '${_formatDuration(duration)}',
                        style: const TextStyle(
                          color: Neo.text,
                          fontFamily: Neo.mono,
                          fontSize: 11.5,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _showSettings,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Neo.cyan.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            _fmtSpeed(_playbackSpeed),
                            style: const TextStyle(
                              color: Neo.cyan,
                              fontFamily: Neo.mono,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fullscreen',
                        onPressed: _openFullscreen,
                        color: Neo.text,
                        icon: const Icon(Icons.fullscreen_rounded, size: 26),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 46,
    double iconSize = 24,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: Colors.black.withValues(alpha: 0.5),
        shape: CircleBorder(side: BorderSide(color: Neo.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Neo.text, size: iconSize),
          ),
        ),
      ),
    );
  }

  void _goToVideo(String? id) {
    if (id == null || id.isEmpty || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayPage(videoId: id, playlistId: widget.playlistId),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Stack(
      children: [
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Neo.cyan),
              SizedBox(height: 16),
              Text(
                'LOADING STREAM',
                style: TextStyle(
                  color: Neo.muted,
                  fontFamily: Neo.mono,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorScreen() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, color: Neo.pink, size: 58),
                const SizedBox(height: 16),
                const Text(
                  'Unable to play video',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Neo.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage.isEmpty
                      ? 'The video could not be loaded.'
                      : _errorMessage,
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Neo.muted, fontSize: 13.5),
                ),
                const SizedBox(height: 24),
                NeoButton(
                  label: 'RETRY',
                  icon: Icons.refresh_rounded,
                  onTap: _loadPage,
                ),
                const SizedBox(height: 12),
                NeoGhostButton(
                  label: 'Go Back',
                  leading: const Icon(Icons.arrow_back_rounded,
                      color: Neo.text, size: 20),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtSpeed(double s) => s == s.roundToDouble() ? '${s.toInt()}x' : '${s}x';

  Future<List<String>> _getPlaylistVideoIds() async {
    if (widget.playlistId.trim().isEmpty) {
      return [];
    }

    final playlistRef = FirebaseFirestore.instance
        .collection('playlists')
        .doc(widget.playlistId);

    // ----------------------------------------------------------
    // 1. videoIds ARRAY
    // ----------------------------------------------------------

    try {
      final playlistDoc = await playlistRef.get();

      if (playlistDoc.exists) {
        final data = playlistDoc.data();

        if (data != null) {
          final dynamic videoIds = data['videoIds'];

          if (videoIds is List) {
            final ids = videoIds
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList();

            if (ids.isNotEmpty) {
              return ids;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Playlist document error: $e');
    }

    // ----------------------------------------------------------
    // 2. SUBCOLLECTION
    // ----------------------------------------------------------

    try {
      final subCollection = await playlistRef.collection('videos').get();

      if (subCollection.docs.isNotEmpty) {
        return subCollection.docs
            .map((doc) => doc.id)
            .where((id) => id.isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint('Playlist subcollection error: $e');
    }

    // ----------------------------------------------------------
    // 3. videos WHERE playlistId
    // ----------------------------------------------------------

    try {
      final query = await FirebaseFirestore.instance
          .collection('videos')
          .where('playlistId', isEqualTo: widget.playlistId)
          .get();

      return query.docs
          .map((doc) => doc.id)
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Playlist video query error: $e');

      return [];
    }
  }

  // ============================================================
  // GET EPISODE NUMBER
  // ============================================================

  int _getEpisodeNumber(Map<String, dynamic> data) {
    final episode = _readString(data, [
      'episodes',
      'episodeNumber',
      'episode',
      'episodeNo',
      'ep',
    ]);

    if (episode.isEmpty) {
      return 999999;
    }

    // Supports:
    // 1
    // "1"
    // "Episode 1"
    // "EP 10"

    final match = RegExp(r'\d+').firstMatch(episode);

    if (match == null) {
      return 999999;
    }

    return int.tryParse(match.group(0)!) ?? 999999;
  }

  // ============================================================
  // LOAD MORE VIDEOS
  // ============================================================

  Future<List<DocumentSnapshot<Map<String, dynamic>>>> _loadMoreVideos() async {
    final videoIds = await _getPlaylistVideoIds();

    if (videoIds.isEmpty) {
      return [];
    }

    // include current video so prev/next can be worked out
    final allIds = <String>{...videoIds, widget.videoId}.toList();

    final List<DocumentSnapshot<Map<String, dynamic>>> results = [];

    // ----------------------------------------------------------
    // LOAD ALL VIDEOS
    // ----------------------------------------------------------

    for (final id in allIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('videos')
            .doc(id)
            .get();

        if (doc.exists) {
          results.add(doc);
        }
      } catch (e) {
        debugPrint('Could not load video $id: $e');
      }
    }

    // ----------------------------------------------------------
    // SORT ASCENDING BY EPISODE
    // ----------------------------------------------------------

    results.sort((a, b) {
      final aData = a.data() ?? {};
      final bData = b.data() ?? {};

      final aEpisode = _getEpisodeNumber(aData);

      final bEpisode = _getEpisodeNumber(bData);

      final c = aEpisode.compareTo(bEpisode);
      return c != 0 ? c : a.id.compareTo(b.id);
    });

    final cur = results.indexWhere((d) => d.id == widget.videoId);
    _prevId = cur > 0 ? results[cur - 1].id : null;
    _nextId = (cur >= 0 && cur < results.length - 1) ? results[cur + 1].id : null;

    results.removeWhere((d) => d.id == widget.videoId);

    return results;
  }

  // ============================================================
  // LOAD MORE VIDEOS IN BACKGROUND
  // ============================================================

  Future<void> _loadMoreVideosInBackground() async {
    try {
      final relatedVideos = await _loadMoreVideos();

      if (!mounted) return;

      setState(() {
        _moreVideos = relatedVideos;
        _moreVideosLoaded = true;
      });

      debugPrint('MORE VIDEOS: ${_moreVideos.length}');
    } catch (e) {
      debugPrint('MORE VIDEOS LOAD ERROR: $e');

      if (!mounted) return;

      setState(() {
        _moreVideos = [];
        _moreVideosLoaded = true;
      });
    }
  }

  // ============================================================
  // THUMBNAIL URL
  // ============================================================

  String _getThumbnailUrl(String url) {
    final clean = url.trim();

    if (clean.isEmpty) {
      return '';
    }

    if (!clean.contains('drive.google.com')) {
      return clean;
    }

    final fileId = _extractDriveFileId(clean);

    if (fileId != null && fileId.isNotEmpty) {
      return 'https://drive.google.com/thumbnail'
          '?id=$fileId&sz=w800';
    }

    return clean;
  }

  // ============================================================
  // MORE VIDEOS
  // ============================================================

  Widget _buildRelatedVideos() {
    if (!_moreVideosLoaded || _moreVideos.isEmpty) {
      return const SizedBox.shrink();
    }

    int i = 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'More Videos',
            tag: '${_moreVideos.length} up next',
            color: Neo.violet,
          ),
          const SizedBox(height: 14),
          ..._moreVideos.map((doc) {
            final data = doc.data();

            if (data == null) {
              return const SizedBox.shrink();
            }

            final title = _readString(data, [
              'title',
              'name',
              'videoTitle',
            ], fallback: 'Untitled Video');

            final episode = _readString(data, [
              'episodes',
              'episodeNumber',
              'episode',
              'episodeNo',
              'ep',
            ]);

            final thumbnail = _readString(data, [
              'thumbnail',
              'thumbnailUrl',
              'imageUrl',
              'posterUrl',
            ]);

            return FadeIn(
              index: i++,
              child: _buildRelatedVideoCard(doc.id, title, thumbnail, episode),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRelatedVideoCard(
    String id,
    String title,
    String thumbnail,
    String episode,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Tilt3D(
        onTap: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) {
                return VideoPlayPage(videoId: id, playlistId: widget.playlistId);
              },
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Neo.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Neo.line),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 132,
                height: 76,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: thumbnail.isNotEmpty
                      ? NeoImage(_getThumbnailUrl(thumbnail))
                      : const ColoredBox(
                          color: Neo.bg2,
                          child: Center(
                            child: Icon(Icons.movie_outlined, color: Neo.muted),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (episode.isNotEmpty) ...[
                      _relatedInfoChip('EP $episode'),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Neo.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_outline_rounded, color: Neo.cyan),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _relatedInfoChip(String text) => NeoTag(text, color: Neo.cyan);

  Widget _buildVideoInfo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Neo.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_season.isNotEmpty) _infoChip('SEASON $_season', Neo.violet),
              if (_episode.isNotEmpty) _infoChip('EP $_episode', Neo.cyan),
              _infoChip('SPEED ${_fmtSpeed(_playbackSpeed)}', Neo.amber),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String text, Color color) => NeoTag(text, color: color);

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: Neo.bg,
      body: _hasError
          ? _buildErrorScreen()
          : _loading
              ? _buildLoadingScreen()
              : isLandscape
                  ? _buildLandscapePage()
                  : _buildPortraitPage(),
    );
  }

  Widget _buildPortraitPage() {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  boxShadow: [
                    BoxShadow(
                      color: Neo.cyan.withValues(alpha: 0.16),
                      blurRadius: 30,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _buildVideoPlayer(),
                ),
              ),
              Expanded(
                child: NeoRefresh(
                  onRefresh: _loadPage,
                  child: ListView(
                  physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics()),
                  children: [
                    _buildVideoInfo(),
                    _buildRelatedVideos(),
                  ],
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLandscapePage() {
    return SizedBox.expand(child: _buildVideoPlayer());
  }
}

class _FullscreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  final String title;
  final double playbackSpeed;
  final bool hasPrev;
  final bool hasNext;

  const _FullscreenVideoPage({
    required this.controller,
    required this.title,
    required this.playbackSpeed,
    this.hasPrev = false,
    this.hasNext = false,
  });

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  bool _showControls = true;

  late double _speed;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _speed = widget.playbackSpeed;

    widget.controller.addListener(_videoListener);
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    widget.controller.removeListener(_videoListener);

    super.dispose();
  }

  // ============================================================
  // LISTENER
  // ============================================================

  void _videoListener() {
    if (!mounted) return;

    setState(() {});
  }

  // ============================================================
  // FORMAT TIME
  // ============================================================

  String _formatTime(Duration duration) {
    final hours = duration.inHours;

    final minutes = duration.inMinutes.remainder(60);

    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // PLAY / PAUSE
  // ============================================================

  Future<void> _togglePlayPause() async {
    final controller = widget.controller;

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // SEEK
  // ============================================================

  Future<void> _seekBy(Duration amount) async {
    final controller = widget.controller;

    final position = controller.value.position;

    final duration = controller.value.duration;

    var target = position + amount;

    if (target < Duration.zero) {
      target = Duration.zero;
    }

    if (target > duration) {
      target = duration;
    }

    await controller.seekTo(target);

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // SPEED
  // ============================================================

  Future<void> _changeSpeed(double speed) async {
    await widget.controller.setPlaybackSpeed(speed);

    if (!mounted) return;

    setState(() {
      _speed = speed;
    });
  }

  // ============================================================
  // SPEED SETTINGS
  // ============================================================

  void _showSpeedSettings() {
    showNeoSheet<void>(
      context,
      title: 'Playback Speed',
      sub: 'SETTINGS',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final speed in const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
            _SpeedChip(
              speed: speed,
              selected: (_speed - speed).abs() < 0.01,
              onTap: () async {
                await _changeSpeed(speed);
                if (!mounted) return;
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _playButton() {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Neo.cyan, Neo.violet],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Neo.cyan.withValues(alpha: 0.55),
              blurRadius: 26,
            ),
          ],
        ),
        child: Icon(
          widget.controller.value.isPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          color: Neo.bg,
          size: 40,
        ),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback? onTap) {
    return Opacity(
      opacity: onTap == null ? 0.35 : 1,
      child: Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: CircleBorder(side: BorderSide(color: Neo.line)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(icon, color: Neo.text, size: 28),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final duration = controller.value.duration;
    final position = controller.value.position;

    final durationMs = duration.inMilliseconds;
    final positionMs = position.inMilliseconds;
    final safeMax = durationMs <= 0 ? 1 : durationMs;
    final safeValue = positionMs.clamp(0, safeMax).toDouble();

    final width = controller.value.size.width;
    final height = controller.value.size.height;

    double ratio = 16 / 9;
    if (width > 0 && height > 0) {
      ratio = width / height;
    }

    final speedText =
        _speed == _speed.roundToDouble() ? '${_speed.toInt()}x' : '${_speed}x';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: ratio,
                child: VideoPlayer(controller),
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _showControls ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Stack(
                  children: [
                    // top bar: back + title
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              color: Neo.text,
                              icon: const Icon(Icons.arrow_back_ios_new_rounded),
                            ),
                            Expanded(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Neo.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _circleButton(
                            Icons.skip_previous_rounded,
                            widget.hasPrev ? () => Navigator.pop(context, 'prev') : null,
                          ),
                          const SizedBox(width: 20),
                          _circleButton(Icons.replay_10_rounded, () {
                            _seekBy(const Duration(seconds: -10));
                          }),
                          const SizedBox(width: 28),
                          _playButton(),
                          const SizedBox(width: 28),
                          _circleButton(Icons.forward_10_rounded, () {
                            _seekBy(const Duration(seconds: 10));
                          }),
                          const SizedBox(width: 20),
                          _circleButton(
                            Icons.skip_next_rounded,
                            widget.hasNext ? () => Navigator.pop(context, 'next') : null,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 28, 14, 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.88),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                activeTrackColor: Neo.cyan,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayColor: Neo.cyan.withValues(alpha: 0.2),
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                ),
                              ),
                              child: Slider(
                                min: 0,
                                max: safeMax.toDouble(),
                                value: safeValue,
                                onChanged: (value) {
                                  controller.seekTo(
                                    Duration(milliseconds: value.toInt()),
                                  );
                                },
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _togglePlayPause,
                                  color: Neo.text,
                                  icon: Icon(
                                    controller.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                ),
                                Text(
                                  '${_formatTime(position)} / ${_formatTime(duration)}',
                                  style: const TextStyle(
                                    color: Neo.text,
                                    fontFamily: Neo.mono,
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _showSpeedSettings,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Neo.cyan.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Text(
                                      speedText,
                                      style: const TextStyle(
                                        color: Neo.cyan,
                                        fontFamily: Neo.mono,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  color: Neo.text,
                                  icon: const Icon(Icons.fullscreen_exit_rounded),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final double speed;
  final bool selected;
  final VoidCallback onTap;

  const _SpeedChip({
    required this.speed,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label =
        speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 76,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: selected
              ? const LinearGradient(colors: [Neo.cyan, Neo.violet])
              : null,
          color: selected ? null : Colors.black.withValues(alpha: 0.28),
          border: Border.all(color: selected ? Neo.cyan : Neo.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Neo.bg : Neo.text,
            fontFamily: Neo.mono,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
