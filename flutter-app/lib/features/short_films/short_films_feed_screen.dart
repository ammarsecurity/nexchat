import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import 'short_film_cache.dart';
import 'short_film_comments.dart';
import 'short_film_downloads.dart';
import 'short_film_engagement.dart';
import 'short_film_progress.dart';
import 'short_films_controller.dart';
import 'short_films_theme.dart';

/// views/ShortFilmsFeedView.vue — vertical snap feed; only the current ±1 players are alive.
class ShortFilmsFeedScreen extends ConsumerStatefulWidget {
  const ShortFilmsFeedScreen({super.key, this.startId, this.seriesId});
  final String? startId;
  final String? seriesId;

  @override
  ConsumerState<ShortFilmsFeedScreen> createState() => _ShortFilmsFeedScreenState();
}

class _ShortFilmsFeedScreenState extends ConsumerState<ShortFilmsFeedScreen> with WidgetsBindingObserver {
  PageController? _pages;
  List<ShortFilm> _films = const [];
  int _index = 0;
  bool _ready = false;
  bool _muted = true;
  bool _userPaused = false;
  bool _descExpanded = false;
  bool _scrolling = false;
  bool _scrubbing = false;
  bool _seriesMode = false;
  bool _requestingMore = false;
  bool _chromeVisible = true;
  bool _autoNextVisible = false;
  int _autoNextSec = 5;
  double _speed = 1.0;
  String? _skipFlash; // 'back' | 'fwd'
  Timer? _hideChromeTimer;
  Timer? _autoNextTimer;
  Timer? _skipFlashTimer;
  final Map<String, VideoPlayerController> _players = {};
  final Set<String> _playing = {};
  final Set<String> _failed = {};
  final Set<String> _endedHooked = {};
  final Set<String> _ensuring = {};
  final Set<String> _fileBacked = {};
  final Map<String, FilmEngagement> _engagement = {};
  final Set<String> _downloaded = {};
  StreamSubscription<String>? _cacheSub;
  static const _reactions = ['❤️', '🔥', '😂', '😮', '👏'];

  ShortFilm? get _current => _index < _films.length ? _films[_index] : null;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cacheSub = ShortFilmCache.instance.onCached.listen(_onCacheReady);
    Future.microtask(_load);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_saveCurrentProgress());
      unawaited(_setWakeLock(false));
    } else if (state == AppLifecycleState.resumed) {
      _syncWakeLock();
    }
  }

  Future<void> _setWakeLock(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  void _syncWakeLock() {
    // Keep screen on while this feed is open and the user hasn't paused playback.
    unawaited(_setWakeLock(_ready && !_userPaused && mounted));
  }

  Future<void> _load() async {
    final store = ref.read(shortFilmsProvider.notifier);
    final seriesId = widget.seriesId;
    if (seriesId != null && seriesId.isNotEmpty) {
      _seriesMode = true;
      final detail = await store.fetchSeriesDetail(seriesId);
      if (!mounted) return;
      _films = detail?.episodes ?? const [];
    } else {
      _seriesMode = false;
      await store.fetchAll(force: true);
      if (!mounted) return;
      _films = List<ShortFilm>.from(store.current.feed);
      await _ensureStartFilmPresent();
    }
    final start = widget.startId;
    if (start != null) {
      final i = _films.indexWhere((f) => f.id == start);
      if (i >= 0) _index = i;
    }
    _pages = PageController(initialPage: _index);
    setState(() => _ready = true);
    _syncWakeLock();
    _onIndexChanged();
  }

  /// Resolve start film; prefer full series episode list when applicable.
  Future<void> _ensureStartFilmPresent() async {
    final start = widget.startId;
    if (start == null || start.isEmpty) return;

    final store = ref.read(shortFilmsProvider.notifier);
    final localIdx = _films.indexWhere((f) => f.id == start);
    var film = localIdx >= 0 ? _films[localIdx] : null;
    film ??= await store.fetchById(start);
    if (!mounted || film == null) return;

    final sid = film.seriesId;
    if (sid != null && sid.isNotEmpty) {
      final detail = await store.fetchSeriesDetail(sid);
      if (!mounted) return;
      final eps = detail?.episodes ?? const <ShortFilm>[];
      if (eps.isNotEmpty) {
        _seriesMode = true;
        _films = eps;
        final i = _films.indexWhere((f) => f.id == start);
        _index = i >= 0 ? i : 0;
        return;
      }
    }

    if (localIdx < 0) {
      _films = [film, ..._films.where((f) => f.id != film!.id)];
      _index = 0;
    }
  }

  @override
  void didUpdateWidget(ShortFilmsFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final start = widget.startId;
    if (start == null || start == oldWidget.startId || !_ready) return;
    _jumpToFilm(start);
  }

  Future<void> _jumpToFilm(String id) async {
    var i = _films.indexWhere((f) => f.id == id);
    if (i < 0) {
      final store = ref.read(shortFilmsProvider.notifier);
      final seriesId = widget.seriesId;
      if (seriesId != null && seriesId.isNotEmpty) {
        final detail = await store.fetchSeriesDetail(seriesId);
        if (!mounted || widget.startId != id) return;
        setState(() => _films = detail?.episodes ?? const []);
      } else {
        final film = await store.fetchById(id);
        if (!mounted || widget.startId != id) return;
        if (film != null) {
          final sid = film.seriesId;
          if (sid != null && sid.isNotEmpty) {
            final detail = await store.fetchSeriesDetail(sid);
            if (!mounted || widget.startId != id) return;
            final eps = detail?.episodes ?? const <ShortFilm>[];
            if (eps.isNotEmpty) {
              setState(() {
                _seriesMode = true;
                _films = eps;
              });
            } else {
              setState(() => _films = [film, ..._films.where((f) => f.id != film.id)]);
            }
          } else {
            setState(() => _films = [film, ..._films.where((f) => f.id != film.id)]);
          }
        }
      }
      i = _films.indexWhere((f) => f.id == id);
    }
    final p = _pages;
    if (i < 0 || p == null || !p.hasClients) return;
    if (i == _index) {
      _onIndexChanged();
    } else {
      p.jumpToPage(i);
    }
  }

  Future<void> _saveProgressFor(String? filmId) async {
    if (filmId == null || filmId.isEmpty) return;
    final v = _players[filmId];
    if (v == null || !v.value.isInitialized) return;
    await ShortFilmProgress.save(filmId, v.value.position, duration: v.value.duration);
  }

  Future<void> _saveCurrentProgress() => _saveProgressFor(_current?.id);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cacheSub?.cancel());
    _hideChromeTimer?.cancel();
    _autoNextTimer?.cancel();
    _skipFlashTimer?.cancel();
    unawaited(_saveCurrentProgress());
    unawaited(_setWakeLock(false));
    _pages?.dispose();
    for (final e in _players.entries) {
      ShortFilmCache.instance.releaseInUse(e.key);
      e.value.dispose();
    }
    super.dispose();
  }

  void _onCacheReady(String id) {
    if (!mounted || _fileBacked.contains(id) || !_players.containsKey(id)) return;
    final film = _films.where((f) => f.id == id).firstOrNull;
    if (film == null) return;
    unawaited(_hotSwapToFile(film));
  }

  /// Swap a network-backed player to the local cache file without losing position.
  Future<void> _hotSwapToFile(ShortFilm f) async {
    if (!mounted || _fileBacked.contains(f.id)) return;
    final old = _players[f.id];
    if (old == null) return;
    final file = await ShortFilmCache.instance.cachedVideo(f.id);
    if (file == null || !mounted || _players[f.id] != old) return;
    final pos = old.value.position;
    final wasPlaying = old.value.isPlaying && _current?.id == f.id && !_userPaused && !_scrolling;
    final next = VideoPlayerController.file(file);
    try {
      await next.initialize();
      await next.setLooping(!_seriesMode);
      await next.setPlaybackSpeed(_speed);
      await next.setVolume(_muted ? 0 : 1);
      if (pos > Duration.zero) await next.seekTo(pos);
    } catch (_) {
      next.dispose();
      return;
    }
    if (!mounted || _players[f.id] != old) {
      next.dispose();
      return;
    }
    next.addListener(() {
      if (!mounted) return;
      final isPlaying = next.value.isPlaying;
      if (isPlaying != _playing.contains(f.id)) {
        setState(() => isPlaying ? _playing.add(f.id) : _playing.remove(f.id));
      }
    });
    _players[f.id] = next;
    _fileBacked.add(f.id);
    old.dispose();
    if (wasPlaying) unawaited(next.play());
    if (mounted) setState(() {});
  }

  void _bumpChrome() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _hideChromeTimer?.cancel();
    _hideChromeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _userPaused || _scrubbing || _autoNextVisible) return;
      setState(() => _chromeVisible = false);
    });
  }

  void _cancelAutoNext() {
    _autoNextTimer?.cancel();
    _autoNextTimer = null;
    if (_autoNextVisible && mounted) setState(() => _autoNextVisible = false);
  }

  void _startAutoNext() {
    if (!_seriesMode || _index >= _films.length - 1 || _autoNextVisible || _userPaused || _scrolling) return;
    _autoNextTimer?.cancel();
    setState(() {
      _autoNextVisible = true;
      _autoNextSec = 5;
      _chromeVisible = true;
    });
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_autoNextSec <= 1) {
        t.cancel();
        setState(() => _autoNextVisible = false);
        _go(1);
      } else {
        setState(() => _autoNextSec--);
      }
    });
  }

  Future<void> _seekBy(int seconds) async {
    final cur = _current;
    if (cur == null) return;
    final v = _players[cur.id];
    if (v == null || !v.value.isInitialized) return;
    final dur = v.value.duration;
    var next = v.value.position + Duration(seconds: seconds);
    if (next < Duration.zero) next = Duration.zero;
    if (dur > Duration.zero && next > dur) next = dur;
    await v.seekTo(next);
    unawaited(ShortFilmProgress.save(cur.id, next, duration: dur));
    setState(() => _skipFlash = seconds < 0 ? 'back' : 'fwd');
    _skipFlashTimer?.cancel();
    _skipFlashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _skipFlash = null);
    });
    _bumpChrome();
  }

  Future<void> _cycleSpeed() async {
    final i = _speeds.indexOf(_speed);
    final next = _speeds[(i < 0 ? 0 : i + 1) % _speeds.length];
    setState(() => _speed = next);
    final cur = _current;
    await (cur == null ? null : _players[cur.id])?.setPlaybackSpeed(next);
    _bumpChrome();
  }

  Future<void> _ensurePlayer(ShortFilm f) async {
    if (_players.containsKey(f.id) || _ensuring.contains(f.id)) return;
    _ensuring.add(f.id);
    try {
      final uri = await ShortFilmCache.instance.resolveVideoPlayback(f);
      if (uri == null || !mounted || _players.containsKey(f.id)) return;
      final fromFile = uri.isScheme('file');
      final c = fromFile ? VideoPlayerController.file(File.fromUri(uri)) : VideoPlayerController.networkUrl(uri);
      _players[f.id] = c;
      if (fromFile) _fileBacked.add(f.id);
      ShortFilmCache.instance.markInUse(f.id);
      c.addListener(() {
        if (!mounted) return;
        final isPlaying = c.value.isPlaying;
        if (isPlaying != _playing.contains(f.id)) {
          setState(() => isPlaying ? _playing.add(f.id) : _playing.remove(f.id));
        }
        if (_seriesMode &&
            _current?.id == f.id &&
            !_userPaused &&
            !_scrolling &&
            !_autoNextVisible &&
            c.value.isInitialized &&
            c.value.duration > Duration.zero &&
            !c.value.isPlaying &&
            c.value.position >= c.value.duration - const Duration(milliseconds: 500)) {
          _startAutoNext();
        }
      });
      try {
        await c.initialize();
        await c.setLooping(!_seriesMode);
        await c.setPlaybackSpeed(_speed);
        await c.setVolume(_muted ? 0 : 1);
        _failed.remove(f.id);
      } catch (_) {
        _failed.add(f.id);
      }
      if (!mounted) return;
      setState(() {});
      if (_current?.id == f.id) _playCurrent();
    } finally {
      _ensuring.remove(f.id);
    }
  }

  void _onIndexChanged() {
    _cancelAutoNext();
    final keep = <String>{};
    for (var o = -1; o <= 1; o++) {
      final i = _index + o;
      if (i >= 0 && i < _films.length) keep.add(_films[i].id);
    }
    for (final id in _players.keys.where((id) => !keep.contains(id)).toList()) {
      _players.remove(id)?.dispose();
      ShortFilmCache.instance.releaseInUse(id);
      _playing.remove(id);
      _endedHooked.remove(id);
      _fileBacked.remove(id);
    }
    ShortFilmCache.instance.prefetchAround(_films, _index);
    // Current first, then neighbors — avoids racing init of three streams.
    final order = [_index, _index + 1, _index - 1];
    unawaited(() async {
      for (final i in order) {
        if (!mounted || i < 0 || i >= _films.length) continue;
        await _ensurePlayer(_films[i]);
      }
    }());
    final cur = _current;
    if (cur != null) {
      ref.read(shortFilmsProvider.notifier).recordView(cur.id);
      unawaited(_players[cur.id]?.setLooping(!_seriesMode));
      unawaited(_players[cur.id]?.setPlaybackSpeed(_speed));
      unawaited(_loadEngagement(cur));
    }
    _playCurrent(restart: true);
    _bumpChrome();
    _maybeLoadMore();
  }

  Future<void> _loadEngagement(ShortFilm film) async {
    try {
      final eng = await ShortFilmEngagementApi.instance.get(film.id);
      final offline = await ShortFilmDownloads.instance.isDownloaded(film.id);
      if (!mounted || _current?.id != film.id) return;
      setState(() {
        _engagement[film.id] = eng;
        if (offline) {
          _downloaded.add(film.id);
        } else {
          _downloaded.remove(film.id);
        }
      });
    } catch (_) {}
  }

  Future<void> _toggleLike(ShortFilm film) async {
    final cur = _engagement[film.id] ?? const FilmEngagement();
    final next = !cur.liked;
    setState(() {
      _engagement[film.id] = cur.copyWith(
        liked: next,
        likeCount: (cur.likeCount + (next ? 1 : -1)).clamp(0, 1 << 30),
      );
    });
    try {
      await ShortFilmEngagementApi.instance.setLiked(film.id, next);
    } catch (_) {
      if (mounted) setState(() => _engagement[film.id] = cur);
    }
  }

  Future<void> _toggleWatchLater(ShortFilm film) async {
    final cur = _engagement[film.id] ?? const FilmEngagement();
    final next = !cur.watchLater;
    setState(() => _engagement[film.id] = cur.copyWith(watchLater: next));
    try {
      await ShortFilmEngagementApi.instance.setWatchLater(film.id, next);
    } catch (_) {
      if (mounted) setState(() => _engagement[film.id] = cur);
    }
  }

  Future<void> _pickReaction(ShortFilm film) async {
    final cur = _engagement[film.id] ?? const FilmEngagement();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: DramaWave.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: DramaWave.hairline, borderRadius: BorderRadius.circular(99)),
            ),
            Text(t('shortFilms.reactions'), style: DramaWave.title(size: 16)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              children: [
                for (final e in _reactions)
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, e),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cur.reaction == e ? DramaWave.goldSoft : DramaWave.elevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cur.reaction == e ? DramaWave.gold : DramaWave.hairline,
                        ),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, ''),
                  child: Text(t('shortFilms.cancelAutoNext'), style: DramaWave.body(color: DramaWave.soft)),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final emoji = chosen.isEmpty ? null : chosen;
    setState(() => _engagement[film.id] = cur.copyWith(reaction: () => emoji));
    try {
      await ShortFilmEngagementApi.instance.setReaction(film.id, emoji);
    } catch (_) {
      if (mounted) setState(() => _engagement[film.id] = cur);
    }
  }

  Future<void> _openComments(ShortFilm film) async {
    final eng = _engagement[film.id] ?? const FilmEngagement();
    final total = await openShortFilmCommentsSheet(
      context,
      filmId: film.id,
      initialCount: eng.commentCount,
    );
    if (!mounted || total == null) return;
    setState(() {
      _engagement[film.id] = (_engagement[film.id] ?? eng).copyWith(commentCount: total);
    });
  }

  bool _filmInSeries(ShortFilm? f) =>
      f != null && ((f.seriesId != null && f.seriesId!.isNotEmpty) || f.isEpisode || _seriesMode);

  Future<void> _openAllEpisodes() async {
    final cur = _current;
    if (cur == null || !_filmInSeries(cur)) return;

    var episodes = _seriesMode && _films.length > 1 ? List<ShortFilm>.from(_films) : const <ShortFilm>[];
    if (episodes.length <= 1) {
      final sid = cur.seriesId ?? widget.seriesId;
      if (sid == null || sid.isEmpty) return;
      final detail = await ref.read(shortFilmsProvider.notifier).fetchSeriesDetail(sid);
      if (!mounted) return;
      episodes = detail?.episodes ?? const [];
      if (episodes.isEmpty) return;
      setState(() {
        _seriesMode = true;
        _films = episodes;
        final i = _films.indexWhere((f) => f.id == cur.id);
        if (i >= 0) _index = i;
      });
    }

    final currentId = _current?.id ?? cur.id;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DramaWave.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => _EpisodesPickerSheet(
        episodes: episodes,
        currentId: currentId,
      ),
    );
    if (!mounted || chosen == null || chosen.isEmpty) return;
    await _jumpToFilm(chosen);
  }

  Future<void> _toggleDownload(ShortFilm film) async {
    final id = film.id;
    if (ShortFilmDownloads.instance.isBusy(id)) return;
    if (_downloaded.contains(id)) {
      await ShortFilmDownloads.instance.remove(id);
      if (mounted) setState(() => _downloaded.remove(id));
      return;
    }
    setState(() {});
    try {
      await ShortFilmDownloads.instance.download(film);
      if (mounted) setState(() => _downloaded.add(id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('shortFilms.downloadFailed'))));
    } finally {
      if (mounted) setState(() {});
    }
  }

  Widget _railAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    Color? color,
    bool accent = false,
  }) {
    final bg = accent
        ? const LinearGradient(colors: [DramaWave.gold, DramaWave.goldDeep])
        : null;
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: bg,
            color: bg == null
                ? (active ? DramaWave.goldSoft : const Color(0x99000000))
                : null,
            border: Border.all(
              color: accent
                  ? Colors.transparent
                  : (active ? DramaWave.gold.withValues(alpha: 0.55) : Colors.white24),
            ),
            boxShadow: accent
                ? [
                    BoxShadow(
                      color: DramaWave.gold.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [
                    BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
                  ],
          ),
          child: Icon(
            icon,
            size: 18,
            color: accent
                ? Colors.black
                : (color ?? (active ? DramaWave.gold : Colors.white)),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: active && !accent ? DramaWave.gold : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            shadows: _shadow,
          ),
        ),
      ]),
    );
  }

  Future<void> _maybeLoadMore() async {
    if (_seriesMode || _requestingMore || !_ready) return;
    final store = ref.read(shortFilmsProvider.notifier);
    if (!store.current.hasMore || store.current.loadingMore) return;
    if (_index < _films.length - 4) return;
    _requestingMore = true;
    try {
      final before = store.current.feed.length;
      await store.loadMore();
      if (!mounted) return;
      final feed = store.current.feed;
      if (feed.length <= before) return;
      final seen = {for (final f in _films) f.id};
      final added = [for (final f in feed) if (seen.add(f.id)) f];
      if (added.isEmpty) return;
      setState(() => _films = [..._films, ...added]);
    } finally {
      _requestingMore = false;
    }
  }

  Future<void> _playCurrent({bool force = false, bool restart = false}) async {
    final cur = _current;
    if (cur == null || _scrolling) return;
    if (_userPaused && !force) return;
    for (final e in _players.entries) {
      if (e.key != cur.id) e.value.pause();
    }
    final v = _players[cur.id];
    if (v == null || !v.value.isInitialized) return;
    if (restart) {
      final resume = ShortFilmProgress.resumeAt(cur.id, v.value.duration);
      await v.seekTo(resume ?? Duration.zero);
    }
    await v.setLooping(!_seriesMode);
    await v.setPlaybackSpeed(_speed);
    await v.setVolume(_muted ? 0 : 1);
    await v.play();
    _bumpChrome();
  }

  void _togglePlayPause() {
    final cur = _current;
    if (cur == null || _scrolling) return;
    final v = _players[cur.id];
    if (v == null) return;
    if (_userPaused || !v.value.isPlaying) {
      setState(() => _userPaused = false);
      _playCurrent(force: true);
    } else {
      setState(() => _userPaused = true);
      v.pause();
      unawaited(_saveProgressFor(cur.id));
    }
    _syncWakeLock();
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    final cur = _current;
    await (cur == null ? null : _players[cur.id])?.setVolume(_muted ? 0 : 1);
  }

  void _go(int delta) {
    final p = _pages;
    final target = _index + delta;
    if (p == null || target < 0 || target >= _films.length || _scrolling) return;
    p.animateToPage(target, duration: const Duration(milliseconds: 340), curve: const Cubic(0.22, 1, 0.36, 1));
  }

  void _close() {
    unawaited(_saveCurrentProgress());
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/short-films');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final films = ref.watch(shortFilmsProvider.select((s) => s.feed));
    if (_ready) {
      final byId = {for (final f in films) f.id: f};
      _films = [for (final f in _films) byId[f.id] ?? f];
    }
    Widget roundBtn(IconData icon, VoidCallback onTap, {double size = 22}) => Material(
          color: const Color(0x990A0809),
          shape: const CircleBorder(
            side: BorderSide(color: DramaWave.hairline),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 42, height: 42, child: Icon(icon, size: size, color: Colors.white)),
          ),
        );

    return Scaffold(
      backgroundColor: DramaWave.bg,
      body: Stack(children: [
        if (!_ready)
          const Center(child: CircularProgressIndicator(color: DramaWave.gold))
        else if (_films.isEmpty)
          Center(child: Text(t('shortFilms.empty'), style: DramaWave.body(color: DramaWave.soft)))
        else
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _scrolling = true;
                for (final p in _players.values) {
                  p.pause();
                }
                setState(() {});
              } else if (n is ScrollEndNotification) {
                _scrolling = false;
                setState(() {});
                _playCurrent();
              }
              return false;
            },
            child: PageView.builder(
              controller: _pages,
              scrollDirection: Axis.vertical,
              physics: _scrubbing ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              itemCount: _films.length,
              onPageChanged: (i) {
                unawaited(_saveProgressFor(_films[_index].id));
                setState(() {
                  _index = i;
                  _userPaused = false;
                  _descExpanded = false;
                  _scrubbing = false;
                });
                _onIndexChanged();
              },
              itemBuilder: (_, i) => _slide(_films[i], i == _index, pad),
            ),
          ),
        AnimatedOpacity(
          opacity: _chromeVisible || _userPaused || _autoNextVisible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: IgnorePointer(
            ignoring: !(_chromeVisible || _userPaused || _autoNextVisible),
            child: Stack(children: [
              PositionedDirectional(top: pad.top + 12, end: 12, child: roundBtn(LucideIcons.x, _close, size: 24)),
              PositionedDirectional(top: pad.top + 12, start: 12, child: roundBtn(_muted ? LucideIcons.volumeX : LucideIcons.volume2, () {
                _toggleMute();
                _bumpChrome();
              })),
              PositionedDirectional(
                top: pad.top + 12,
                start: 12 + 44 + 8,
                child: roundBtn(_userPaused ? LucideIcons.play : LucideIcons.pause, () {
                  _togglePlayPause();
                  _bumpChrome();
                }),
              ),
              PositionedDirectional(
                top: pad.top + 12,
                start: 12 + 44 + 8 + 44 + 8,
                child: roundBtn(LucideIcons.gauge, _cycleSpeed, size: 20),
              ),
              Positioned(
                top: pad.top + 18,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0A0809),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: DramaWave.gold.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      '${_speed}x',
                      style: const TextStyle(color: DramaWave.gold, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
        if (_skipFlash != null)
          IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xCC0A0809),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: DramaWave.hairline),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_skipFlash == 'back' ? LucideIcons.rotateCcw : LucideIcons.rotateCw, color: DramaWave.gold, size: 18),
                  const SizedBox(width: 8),
                  Text(_skipFlash == 'back' ? '-10' : '+10', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        if (_autoNextVisible)
          Positioned(
            left: 24,
            right: 24,
            bottom: pad.bottom + 28,
            child: Material(
              color: DramaWave.elevated,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: DramaWave.hairline),
                ),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      t('shortFilms.nextEpisodeIn', {'n': '$_autoNextSec'}),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _cancelAutoNext();
                      _go(1);
                    },
                    child: Text(
                      t('shortFilms.nextEpisode'),
                      style: const TextStyle(color: DramaWave.gold, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelAutoNext,
                    child: Text(t('shortFilms.cancelAutoNext'), style: const TextStyle(color: Colors.white70)),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _slide(ShortFilm film, bool isCurrent, EdgeInsets pad) {
    final v = _players[film.id];
    final active = isCurrent && !_scrolling && (_chromeVisible || _userPaused || _autoNextVisible);
    final w = MediaQuery.sizeOf(context).width;
    final narrow = w <= 380;
    final wide = w >= 481;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isCurrent
          ? () {
              _bumpChrome();
              _togglePlayPause();
            }
          : null,
      onDoubleTapDown: isCurrent
          ? (d) {
              final mid = MediaQuery.sizeOf(context).width / 2;
              unawaited(_seekBy(d.localPosition.dx < mid ? -10 : 10));
            }
          : null,
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: DramaWave.bg),
        // Poster under the player — perceived start feels instant; no black flash on swipe.
        if (film.thumbnailUrl != null && film.thumbnailUrl!.isNotEmpty)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: Api.absoluteUrl(film.thumbnailUrl)!,
              fit: BoxFit.cover,
              memCacheWidth: 1080,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        if (_failed.contains(film.id) && isCurrent)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(t('common.error'), style: const TextStyle(color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  _failed.remove(film.id);
                  _fileBacked.remove(film.id);
                  _players.remove(film.id)?.dispose();
                  unawaited(_ensurePlayer(film));
                },
                child: Text(t('noConnection.retry'), style: const TextStyle(color: DramaWave.gold)),
              ),
            ]),
          ),
        if (v != null && v.value.isInitialized)
          Positioned.fill(
            child: FittedBox(
              // contain: show the full video frame (no zoom/crop). Poster above uses cover.
              fit: BoxFit.contain,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: v.value.size.width,
                height: v.value.size.height,
                child: VideoPlayer(v),
              ),
            ),
          ),
        if (_userPaused && isCurrent)
          IgnorePointer(
            child: ColoredBox(
              color: const Color(0x33000000),
              child: Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.45),
                    border: Border.all(color: DramaWave.gold.withValues(alpha: 0.7)),
                  ),
                  child: const Icon(LucideIcons.play, size: 32, color: DramaWave.gold),
                ),
              ),
            ),
          ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xF00A0809),
                  Color(0x990A0809),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x660A0809),
                ],
                stops: [0, 0.26, 0.48, 0.8, 1],
              ),
            ),
          ),
        ),
        // action rail
        PositionedDirectional(
          bottom: (wide ? 80 : narrow ? 64 : 72) + pad.bottom,
          end: wide ? 20 : narrow ? 8 : 10,
          child: _FadeUp(
            visible: active,
            offset: 8,
            child: Builder(builder: (_) {
              final eng = _engagement[film.id] ?? const FilmEngagement();
              final gap = SizedBox(height: narrow ? 11 : 13);
              return Column(mainAxisSize: MainAxisSize.min, children: [
                _railAction(
                  icon: LucideIcons.heart,
                  label: eng.likeCount > 0 ? '${eng.likeCount}' : t('shortFilms.like'),
                  active: eng.liked,
                  color: eng.liked ? DramaWave.hot : Colors.white,
                  onTap: () => unawaited(_toggleLike(film)),
                ),
                gap,
                _railAction(
                  icon: LucideIcons.bookmark,
                  label: eng.watchLater ? t('shortFilms.savedWatchLater') : t('shortFilms.watchLater'),
                  active: eng.watchLater,
                  onTap: () => unawaited(_toggleWatchLater(film)),
                ),
                gap,
                _railAction(
                  icon: LucideIcons.messageCircle,
                  label: eng.commentCount > 0 ? '${eng.commentCount}' : t('shortFilms.comments'),
                  active: eng.commentCount > 0,
                  onTap: () => unawaited(_openComments(film)),
                ),
                gap,
                _railAction(
                  icon: LucideIcons.smilePlus,
                  label: eng.reaction ?? t('shortFilms.reactions'),
                  active: eng.reaction != null,
                  onTap: () => unawaited(_pickReaction(film)),
                ),
                gap,
                _railAction(
                  icon: _downloaded.contains(film.id) ? LucideIcons.check : LucideIcons.download,
                  label: ShortFilmDownloads.instance.isBusy(film.id)
                      ? t('shortFilms.downloading')
                      : (_downloaded.contains(film.id) ? t('shortFilms.downloaded') : t('shortFilms.download')),
                  active: _downloaded.contains(film.id),
                  onTap: () => unawaited(_toggleDownload(film)),
                ),
                gap,
                _railAction(
                  icon: LucideIcons.share2,
                  label: t('shortFilms.share'),
                  accent: true,
                  onTap: () {
                    final returnPath = film.seriesId != null && film.seriesId!.isNotEmpty
                        ? '/short-films/watch?start=${film.id}&series=${film.seriesId}'
                        : '/short-films/watch?start=${film.id}';
                    context.push('/share-message', extra: {
                      'shareMessage': {
                        'type': 'short_film',
                        'content': buildShortFilmShareContent(
                          film.id,
                          film.isEpisode ? film.displaySubtitle : film.title,
                          film.thumbnailUrl,
                        ),
                      },
                      'returnPath': returnPath,
                    });
                  },
                ),
                gap,
                const Icon(LucideIcons.eye, size: 16, color: DramaWave.soft, shadows: _shadow),
                const SizedBox(height: 4),
                Text(
                  '${film.viewCount}',
                  style: const TextStyle(
                    color: DramaWave.soft,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    shadows: _shadow,
                  ),
                ),
              ]);
            }),
          ),
        ),
        // meta
        PositionedDirectional(
          start: 0,
          end: 0,
          bottom: 0,
          child: _FadeUp(
            visible: active,
            offset: 10,
            child: Align(
              alignment: AlignmentDirectional.bottomStart,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? (w * 0.72).clamp(0, 420).toDouble() : double.infinity),
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(narrow ? 12 : 14, 12, wide ? 14 : (narrow ? 64 : 72), 14 + pad.bottom),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (isCurrent && v != null && v.value.isInitialized) ...[
                      _FilmSeekBar(
                        controller: v,
                        onScrubbingChanged: (scrubbing) {
                          if (_scrubbing == scrubbing) return;
                          setState(() => _scrubbing = scrubbing);
                        },
                        onSeekCommitted: (pos) {
                          unawaited(ShortFilmProgress.save(film.id, pos, duration: v.value.duration));
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_filmInSeries(film)) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [DramaWave.gold, DramaWave.goldDeep]),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              t('shortFilms.episodeN').replaceAll('{n}', '${film.episodeNumber ?? (_index + 1)}'),
                              style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (_seriesMode && _films.length > 1) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${_index + 1}/${_films.length}',
                              style: const TextStyle(
                                color: DramaWave.soft,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                shadows: _shadow,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: isCurrent ? _openAllEpisodes : null,
                          borderRadius: BorderRadius.circular(12),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xCC0A0809),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: DramaWave.gold.withValues(alpha: 0.45)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.listVideo, size: 16, color: DramaWave.gold),
                                const SizedBox(width: 8),
                                Text(
                                  t('shortFilms.allEpisodes'),
                                  style: const TextStyle(
                                    color: DramaWave.gold,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Directionality.of(context) == TextDirection.rtl
                                      ? LucideIcons.chevronLeft
                                      : LucideIcons.chevronRight,
                                  size: 16,
                                  color: DramaWave.gold,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      film.isEpisode ? film.displaySubtitle : film.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: narrow ? 15 : 16,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        shadows: _shadowStrong,
                      ),
                    ),
                    if (film.isEpisode && film.title != film.displaySubtitle) ...[
                      const SizedBox(height: 2),
                      Text(
                        film.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: narrow ? 12 : 13,
                          shadows: _shadow,
                        ),
                      ),
                    ],
                    if (film.description?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: isCurrent ? () => setState(() => _descExpanded = !_descExpanded) : null,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            film.description!,
                            maxLines: _descExpanded && isCurrent ? null : 2,
                            overflow: _descExpanded && isCurrent ? null : TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: narrow ? 12 : 13,
                              height: 1.45,
                              shadows: _shadow,
                            ),
                          ),
                          if (!_descExpanded || !isCurrent)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                t('shortFilms.showMore'),
                                style: const TextStyle(
                                  color: DramaWave.gold,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
        if (isCurrent)
          PositionedDirectional(
            start: 10,
            top: 0,
            bottom: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: const Duration(milliseconds: 320),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_index > 0) _NavBtn(icon: LucideIcons.chevronUp, onTap: () => _go(-1)),
                  if (_index > 0 && _index < _films.length - 1) const SizedBox(height: 6),
                  if (_index < _films.length - 1) _NavBtn(icon: LucideIcons.chevronDown, onTap: () => _go(1)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 1))];
const _shadowStrong = [Shadow(color: Color(0xA6000000), blurRadius: 6, offset: Offset(0, 1))];

String _fmtVideoClock(Duration d) {
  final total = d.inSeconds.clamp(0, 359999);
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Horizontal scrubber for the current short-film / series episode.
/// Owns its own [VideoPlayerController] listener so the feed page does not rebuild every tick.
class _FilmSeekBar extends StatefulWidget {
  const _FilmSeekBar({
    required this.controller,
    required this.onScrubbingChanged,
    required this.onSeekCommitted,
  });
  final VideoPlayerController controller;
  final ValueChanged<bool> onScrubbingChanged;
  final ValueChanged<Duration> onSeekCommitted;

  @override
  State<_FilmSeekBar> createState() => _FilmSeekBarState();
}

class _FilmSeekBarState extends State<_FilmSeekBar> {
  bool _dragging = false;
  double _dragValue = 0;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant _FilmSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTick);
      widget.controller.addListener(_onTick);
      _dragging = false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (!mounted || _dragging) return;
    final now = DateTime.now();
    if (now.difference(_lastTick) < const Duration(milliseconds: 200)) return;
    _lastTick = now;
    setState(() {});
  }

  Future<void> _seekFraction(double fraction) async {
    final dur = widget.controller.value.duration;
    if (dur <= Duration.zero) return;
    final ms = (dur.inMilliseconds * fraction.clamp(0.0, 1.0)).round();
    await widget.controller.seekTo(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.controller.value;
    final dur = v.duration;
    final ready = dur > Duration.zero;
    final live = ready ? (v.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final value = _dragging ? _dragValue : live;
    final pos = !ready
        ? Duration.zero
        : (_dragging ? Duration(milliseconds: (dur.inMilliseconds * value).round()) : v.position);

    // Absorb taps so the slide play/pause GestureDetector does not fire.
    // Horizontal Slider drag naturally does not compete with the vertical PageView.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: _dragging ? 7 : 5.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: DramaWave.gold,
              inactiveTrackColor: Colors.white24,
              thumbColor: DramaWave.gold,
              overlayColor: DramaWave.goldSoft,
              trackShape: const RoundedRectSliderTrackShape(),
            ),
              child: Slider(
              value: value,
              onChangeStart: ready
                  ? (x) {
                      setState(() {
                        _dragging = true;
                        _dragValue = x;
                      });
                      widget.onScrubbingChanged(true);
                    }
                  : null,
              onChanged: ready ? (x) => setState(() => _dragValue = x) : null,
              onChangeEnd: ready
                  ? (x) async {
                      await _seekFraction(x);
                      final dur = widget.controller.value.duration;
                      final pos = Duration(milliseconds: (dur.inMilliseconds * x.clamp(0.0, 1.0)).round());
                      widget.onSeekCommitted(pos);
                      if (!mounted) return;
                      setState(() => _dragging = false);
                      widget.onScrubbingChanged(false);
                    }
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(
                  _fmtVideoClock(pos),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, shadows: _shadow),
                ),
                const Spacer(),
                Text(
                  _fmtVideoClock(dur),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w600, shadows: _shadow),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FadeUp extends StatelessWidget {
  const _FadeUp({required this.visible, required this.offset, required this.child});
  final bool visible;
  final double offset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const curve = Cubic(0.22, 1, 0.36, 1);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 320),
        curve: curve,
        child: AnimatedSlide(
          offset: Offset(0, visible ? 0 : offset / 100),
          duration: const Duration(milliseconds: 320),
          curve: curve,
          child: child,
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0x990A0809),
        shape: const CircleBorder(side: BorderSide(color: DramaWave.hairline)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: DramaWave.gold.withValues(alpha: 0.85)),
          ),
        ),
      );
}

/// DramaWave-style episode number picker for the player.
class _EpisodesPickerSheet extends StatelessWidget {
  const _EpisodesPickerSheet({required this.episodes, this.currentId});
  final List<ShortFilm> episodes;
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.62;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + pad.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DramaWave.hairline,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 16,
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    decoration: BoxDecoration(
                      color: DramaWave.gold,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Expanded(
                    child: Text(t('shortFilms.selectEpisode'), style: DramaWave.title(size: 16)),
                  ),
                  Text(
                    t('shortFilms.episodesCount').replaceAll('{n}', '${episodes.length}'),
                    style: DramaWave.body(size: 12, color: DramaWave.soft),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: LayoutBuilder(builder: (context, box) {
                    const gap = 10.0;
                    final cols = box.maxWidth >= 520
                        ? 7
                        : box.maxWidth >= 400
                            ? 6
                            : 5;
                    final cell = (box.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (var i = 0; i < episodes.length; i++)
                          SizedBox(
                            width: cell,
                            height: cell,
                            child: _EpisodePickCell(
                              number: episodes[i].episodeNumber ?? (i + 1),
                              selected: episodes[i].id == currentId,
                              onTap: () => Navigator.pop(context, episodes[i].id),
                            ),
                          ),
                      ],
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodePickCell extends StatelessWidget {
  const _EpisodePickCell({required this.number, required this.selected, required this.onTap});
  final int number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? DramaWave.goldSoft : DramaWave.elevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? DramaWave.gold : DramaWave.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              '$number',
              style: TextStyle(
                color: selected ? DramaWave.gold : DramaWave.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
