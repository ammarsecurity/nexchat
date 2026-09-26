import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import 'short_film_cache.dart';
import 'short_films_controller.dart';

/// views/ShortFilmsFeedView.vue — vertical snap feed; only the current ±1 players are alive.
class ShortFilmsFeedScreen extends ConsumerStatefulWidget {
  const ShortFilmsFeedScreen({super.key, this.startId, this.seriesId});
  final String? startId;
  final String? seriesId;

  @override
  ConsumerState<ShortFilmsFeedScreen> createState() => _ShortFilmsFeedScreenState();
}

class _ShortFilmsFeedScreenState extends ConsumerState<ShortFilmsFeedScreen> {
  PageController? _pages;
  List<ShortFilm> _films = const [];
  int _index = 0;
  bool _ready = false;
  bool _muted = true;
  bool _userPaused = false;
  bool _descExpanded = false;
  bool _scrolling = false;
  bool _seriesMode = false;
  bool _requestingMore = false;
  final Map<String, VideoPlayerController> _players = {};
  final Set<String> _playing = {};
  final Set<String> _failed = {};

  ShortFilm? get _current => _index < _films.length ? _films[_index] : null;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
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

  @override
  void dispose() {
    _pages?.dispose();
    for (final e in _players.entries) {
      ShortFilmCache.instance.releaseInUse(e.key);
      e.value.dispose();
    }
    super.dispose();
  }

  Future<void> _ensurePlayer(ShortFilm f) async {
    if (_players.containsKey(f.id)) return;
    final uri = await ShortFilmCache.instance.resolveVideoPlayback(f);
    if (uri == null || !mounted || _players.containsKey(f.id)) return;
    final c = uri.isScheme('file')
        ? VideoPlayerController.file(File.fromUri(uri))
        : VideoPlayerController.networkUrl(uri);
    _players[f.id] = c;
    ShortFilmCache.instance.markInUse(f.id);
    c.addListener(() {
      final isPlaying = c.value.isPlaying;
      if (isPlaying != _playing.contains(f.id) && mounted) {
        setState(() => isPlaying ? _playing.add(f.id) : _playing.remove(f.id));
      }
    });
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(_muted ? 0 : 1);
      _failed.remove(f.id);
    } catch (_) {
      _failed.add(f.id);
    }
    if (!mounted) return;
    setState(() {});
    if (_current?.id == f.id) _playCurrent();
  }

  void _onIndexChanged() {
    final keep = <String>{};
    for (var o = -1; o <= 1; o++) {
      final i = _index + o;
      if (i >= 0 && i < _films.length) keep.add(_films[i].id);
    }
    for (final id in _players.keys.where((id) => !keep.contains(id)).toList()) {
      _players.remove(id)?.dispose();
      ShortFilmCache.instance.releaseInUse(id);
      _playing.remove(id);
    }
    ShortFilmCache.instance.prefetchAround(_films, _index);
    for (final i in [_index, _index + 1, _index - 1]) {
      if (i >= 0 && i < _films.length) _ensurePlayer(_films[i]);
    }
    final cur = _current;
    if (cur != null) ref.read(shortFilmsProvider.notifier).recordView(cur.id);
    _playCurrent(restart: true);
    _maybeLoadMore();
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
    if (restart) await v.seekTo(Duration.zero);
    await v.setVolume(_muted ? 0 : 1);
    await v.play();
  }

  void _togglePlayPause() {
    final cur = _current;
    final v = cur == null ? null : _players[cur.id];
    if (v == null || _scrolling) return;
    if (_userPaused || !v.value.isPlaying) {
      setState(() => _userPaused = false);
      _playCurrent(force: true);
    } else {
      setState(() => _userPaused = true);
      v.pause();
    }
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
          color: const Color(0x73000000),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, size: size, color: Colors.white)),
          ),
        );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (!_ready)
          const Center(child: CircularProgressIndicator(color: Colors.white54))
        else if (_films.isEmpty)
          Center(child: Text(t('shortFilms.empty'), style: TextStyle(color: Colors.white.withValues(alpha: 0.7))))
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
              itemCount: _films.length,
              onPageChanged: (i) {
                setState(() {
                  _index = i;
                  _userPaused = false;
                  _descExpanded = false;
                });
                _onIndexChanged();
              },
              itemBuilder: (_, i) => _slide(_films[i], i == _index, pad),
            ),
          ),
        PositionedDirectional(top: pad.top + 12, end: 12, child: roundBtn(LucideIcons.x, _close, size: 24)),
        PositionedDirectional(top: pad.top + 12, start: 12, child: roundBtn(_muted ? LucideIcons.volumeX : LucideIcons.volume2, _toggleMute)),
        PositionedDirectional(
          top: pad.top + 12,
          start: 12 + 44 + 8,
          child: roundBtn(_userPaused ? LucideIcons.play : LucideIcons.pause, _togglePlayPause),
        ),
      ]),
    );
  }

  Widget _slide(ShortFilm film, bool isCurrent, EdgeInsets pad) {
    final v = _players[film.id];
    final active = isCurrent && !_scrolling;
    final w = MediaQuery.sizeOf(context).width;
    final narrow = w <= 380;
    final wide = w >= 481;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isCurrent ? _togglePlayPause : null,
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Color(0xFF111111)),
        if (_failed.contains(film.id) && isCurrent)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(t('common.error'), style: const TextStyle(color: Colors.white70, fontSize: 15)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  _failed.remove(film.id);
                  _players.remove(film.id)?.dispose();
                  unawaited(_ensurePlayer(film));
                },
                child: Text(t('noConnection.retry'), style: const TextStyle(color: Colors.white)),
              ),
            ]),
          ),
        if (v != null && v.value.isInitialized)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: isCurrent && (_playing.contains(film.id) || _userPaused) ? 1 : 0,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)),
            ),
          ),
        if (_userPaused && isCurrent)
          const IgnorePointer(
            child: ColoredBox(
              color: Color(0x2E000000),
              child: Center(child: Icon(LucideIcons.play, size: 56, color: Color(0xEBFFFFFF))),
            ),
          ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xE0000000), Color(0x59000000), Color(0x00000000), Color(0x00000000), Color(0x59000000)],
                stops: [0, 0.28, 0.48, 0.82, 1],
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
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
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: narrow ? 36 : 40,
                    height: narrow ? 36 : 40,
                    decoration: const BoxDecoration(
                      color: Color(0xEB6C63FF),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 4))],
                    ),
                    child: const Icon(LucideIcons.share2, size: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(t('shortFilms.share'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, shadows: _shadow)),
                ]),
              ),
              SizedBox(height: narrow ? 14 : 18),
              const Icon(LucideIcons.eye, size: 18, color: Colors.white, shadows: _shadow),
              const SizedBox(height: 4),
              Text('${film.viewCount}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, height: 1, shadows: _shadow)),
            ]),
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
                    Text(film.isEpisode ? film.displaySubtitle : film.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: narrow ? 15 : 16, fontWeight: FontWeight.w700, height: 1.3, shadows: _shadowStrong)),
                    if (film.isEpisode && film.title != film.displaySubtitle) ...[
                      const SizedBox(height: 2),
                      Text(film.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: narrow ? 12 : 13, shadows: _shadow)),
                    ],
                    if (film.description?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: isCurrent ? () => setState(() => _descExpanded = !_descExpanded) : null,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(film.description!,
                              maxLines: _descExpanded && isCurrent ? null : 2,
                              overflow: _descExpanded && isCurrent ? null : TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: narrow ? 12 : 13, height: 1.45, shadows: _shadow)),
                          if (!_descExpanded || !isCurrent)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(t('shortFilms.showMore'),
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w700)),
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
        color: const Color(0x59000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.55))),
        ),
      );
}
