import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/share_links.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import 'stories_controller.dart';

const _slideMs = 5000;
const _swipeRatio = 0.18;
const _swipeDownMin = 72.0;

/// views/StoryViewerView.vue
class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({super.key, required this.userId, this.slideId, this.from});
  final String userId;
  final String? slideId;
  final String? from;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen> with SingleTickerProviderStateMixin {
  late String _userId = widget.userId;
  List<StorySlide> _slides = const [];
  int _index = 0;
  bool _loading = true;
  bool _userSwitching = false;
  bool _mediaReady = false;
  bool _paused = false;
  bool _holding = false;
  bool _transitioning = false;
  bool _muted = true;
  bool _sending = false;
  String _dir = 'fade';
  double _dragX = 0;
  bool _dragging = false;
  Offset _dragStart = Offset.zero;
  DateTime _dragStartAt = DateTime.now();

  VideoPlayerController? _video;
  bool _videoPlaying = false;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  final Set<String> _mediaCache = {};

  late final AnimationController _progress = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _navigate('next');
    });

  StorySlide? get _current => _index < _slides.length ? _slides[_index] : null;
  bool get _isOwner => _userId == ref.read(authProvider).user?.id;

  String get _publisherName =>
      ref.read(storiesProvider).feed.where((r) => r.userId == _userId).firstOrNull?.name ?? '—';

  List<StoryRing> get _feedRings {
    final withSlides = ref.read(storiesProvider).feed.where((r) => r.slideCount > 0);
    return [...withSlides.where((r) => r.isMine), ...withSlides.where((r) => !r.isMine)];
  }

  @override
  void initState() {
    super.initState();
    _replyFocus.addListener(_syncPause);
    Future.microtask(() async {
      final stories = ref.read(storiesProvider.notifier);
      if (!stories.current.loaded) await stories.fetchFeed();
      await _loadSlidesForUser(_userId, startSlideId: widget.slideId, initial: true);
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _video?.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _syncPause() {
    if (_holding || _paused || _replyFocus.hasFocus) {
      _progress.stop();
      _video?.pause();
    } else if (_mediaReady && _current != null) {
      _progress.forward();
      _video?.play();
    }
  }

  Future<void> _preload(StorySlide s) async {
    if (s.mediaUrl == null || s.isText) return;
    final url = Api.absoluteUrl(s.mediaUrl)!;
    if (s.isVideo) return;
    try {
      await precacheImage(CachedNetworkImageProvider(url), context).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  void _prefetchAdjacent() {
    for (final i in [_index - 1, _index + 1]) {
      if (i < 0 || i >= _slides.length) continue;
      final s = _slides[i];
      _preload(s).then((_) => _mediaCache.add(s.id));
    }
  }

  Future<void> _onSlideChange() async {
    _progress.stop();
    _progress.value = 0;
    final old = _video;
    _video = null;
    _videoPlaying = false;
    old?.dispose();
    final slide = _current;
    if (slide == null) return;

    if (slide.isVideo && slide.mediaUrl != null) {
      setState(() => _mediaReady = false);
      final c = VideoPlayerController.networkUrl(Uri.parse(Api.absoluteUrl(slide.mediaUrl)!));
      _video = c;
      try {
        await c.initialize().timeout(const Duration(seconds: 15));
        await c.setVolume(_muted ? 0 : 1);
        c.addListener(() {
          final playing = c.value.isPlaying;
          if (playing != _videoPlaying && mounted && _video == c) setState(() => _videoPlaying = playing);
        });
      } catch (_) {}
      if (!mounted || _video != c) return;
    } else if (!_mediaCache.contains(slide.id)) {
      setState(() => _mediaReady = false);
      await _preload(slide);
      _mediaCache.add(slide.id);
      if (!mounted || _current?.id != slide.id) return;
    }

    final ms = slide.isVideo ? ((slide.videoDurationSeconds ?? 15) * 1000).clamp(0, 60000).toInt() : _slideMs;
    _progress.duration = Duration(milliseconds: ms <= 0 ? 15000 : ms);
    setState(() => _mediaReady = true);
    if (_video != null) {
      await _video!.seekTo(Duration.zero);
      if (!_paused && !_holding) await _video!.play();
    }
    if (!_paused && !_holding && !_replyFocus.hasFocus) _progress.forward(from: 0);
    _recordView();
    _prefetchAdjacent();
  }

  Future<bool> _loadSlidesForUser(String uid, {String? startSlideId, int? startIndex, String? direction, bool initial = false}) async {
    setState(() {
      if (initial) {
        _loading = true;
      } else {
        _userSwitching = true;
      }
      if (_mediaCache.isEmpty) _mediaReady = false;
    });
    try {
      final data = await Api.get('/stories/user/$uid');
      final list = asJsonList(data).map(StorySlide.fromJson).toList();
      if (list.isEmpty) {
        if (direction == 'prev') return false;
        if (mounted) context.go('/conversations');
        return false;
      }
      if (!mounted) return false;
      setState(() {
        _userId = uid;
        _slides = list;
        if (startIndex != null) {
          _index = startIndex.clamp(0, list.length - 1);
        } else if (startSlideId != null) {
          final i = list.indexWhere((s) => s.id == startSlideId);
          _index = i >= 0 ? i : 0;
        } else {
          _index = direction == 'prev' ? list.length - 1 : 0;
        }
        _loading = false;
      });
      await _onSlideChange();
      return true;
    } catch (_) {
      if (mounted) context.go('/conversations');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _userSwitching = false;
        });
      }
    }
  }

  Future<void> _recordView() async {
    final slide = _current;
    if (slide == null || _isOwner) return;
    try {
      await Api.post('/stories/${slide.id}/view');
      ref.read(storiesProvider.notifier).markRingSeen(_userId);
    } catch (_) {}
  }

  Future<void> _goToAdjacentUser(int delta) async {
    final rings = _feedRings;
    final i = rings.indexWhere((r) => r.userId == _userId);
    if (i < 0) {
      _goBack();
      return;
    }
    final j = i + delta;
    if (j < 0 || j >= rings.length) {
      if (delta > 0) _goBack();
      return;
    }
    _mediaCache.clear();
    _paused = false;
    await _loadSlidesForUser(rings[j].userId, direction: delta > 0 ? 'next' : 'prev', startIndex: delta > 0 ? 0 : null);
  }

  Future<void> _navigate(String direction) async {
    if (_transitioning || _loading || _userSwitching) return;
    _transitioning = true;
    setState(() => _dir = direction);
    _progress.stop();
    try {
      if (direction == 'next') {
        if (_index < _slides.length - 1) {
          setState(() => _index++);
          await _onSlideChange();
        } else {
          await _goToAdjacentUser(1);
        }
      } else if (_index > 0) {
        setState(() => _index--);
        await _onSlideChange();
      } else {
        await _goToAdjacentUser(-1);
      }
    } finally {
      _transitioning = false;
    }
  }

  void _goBack() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(widget.from == 'create' ? '/stories/create' : '/conversations');
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    _syncPause();
  }

  void _onTapZone(double x) {
    final w = MediaQuery.sizeOf(context).width;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final inStart = x < w * 0.34;
    final inEnd = x > w * 0.66;
    if (rtl) {
      if (inStart) {
        _navigate('next');
      } else if (inEnd) {
        _navigate('prev');
      } else {
        _togglePause();
      }
    } else {
      if (inStart) {
        _navigate('prev');
      } else if (inEnd) {
        _navigate('next');
      } else {
        _togglePause();
      }
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_transitioning || _userSwitching) return;
    if (_replyFocus.hasFocus) {
      _replyFocus.unfocus();
      return;
    }
    _holding = true;
    _dragging = true;
    _dragStart = e.position;
    _dragStartAt = DateTime.now();
    _dragX = 0;
    _syncPause();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_dragging) return;
    final dx = e.position.dx - _dragStart.dx;
    final dy = e.position.dy - _dragStart.dy;
    if (dy.abs() > dx.abs() * 1.2 && dy.abs() > 24) return;
    setState(() => _dragX = dx);
  }

  void _onPointerUp(PointerEvent e) {
    if (!_dragging) return;
    _dragging = false;
    _holding = false;
    final dx = _dragX;
    final dy = e.position.dy - _dragStart.dy;
    final dt = DateTime.now().difference(_dragStartAt).inMilliseconds;
    setState(() => _dragX = 0);

    final threshold = MediaQuery.sizeOf(context).width * _swipeRatio;
    final swipeLeft = dx < -threshold || (dx < -40 && dt < 280);
    final swipeRight = dx > threshold || (dx > 40 && dt < 280);

    if (dy.abs() > dx.abs() && dy > _swipeDownMin && dy > threshold) {
      _goBack();
      return;
    }
    if (dx.abs() > dy.abs() && swipeLeft) {
      _navigate('next');
      return;
    }
    if (dx.abs() > dy.abs() && swipeRight) {
      _navigate('prev');
      return;
    }
    if (dx.abs() < 12 && dy.abs() < 12 && dt < 320) {
      _onTapZone(e.position.dx);
      return;
    }
    _syncPause();
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _video?.setVolume(_muted ? 0 : 1);
  }

  Future<void> _sendReply() async {
    final slide = _current;
    final text = _reply.text.trim();
    if (slide == null || text.isEmpty || _sending || _isOwner) return;
    setState(() => _sending = true);
    try {
      final data = await Api.post('/stories/${slide.id}/reply', {'text': text});
      _reply.clear();
      final convId = data is Map ? data.s('conversationId') : null;
      if (convId != null && mounted) context.push('/conversation/$convId');
    } catch (e) {
      if (mounted) _showAlert(Api.errorMessage(e, t('common.error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showAlert(String message) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('stories.dialogNotice')),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('common.ok')))],
      ),
    );
  }

  Future<void> _openViewers() async {
    final slide = _current;
    if (slide == null || !_isOwner) return;
    setState(() => _holding = true);
    _syncPause();
    final future = Api.get('/stories/${slide.id}/viewers').then(asJsonList).catchError((_) => <Json>[]);
    await showAppSheet<void>(
      context,
      builder: (ctx) => _ViewersSheet(viewers: future),
    );
    if (!mounted) return;
    _holding = false;
    _syncPause();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final slide = _current;
    ref.watch(storiesProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: _loading
          ? Center(child: Text(t('common.loading'), style: const TextStyle(color: Colors.white)))
          : slide == null
              ? const SizedBox.shrink()
              : Stack(children: [
                  Positioned.fill(
                    child: Listener(
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerUp,
                      child: AnimatedContainer(
                        duration: _dragging ? Duration.zero : const Duration(milliseconds: 250),
                        curve: const Cubic(0.25, 0.8, 0.25, 1),
                        transform: Matrix4.translationValues(_dragX * 0.55, 0, 0),
                        decoration: slide.isText ? storyBackgroundDecoration(slide.backgroundColor) : const BoxDecoration(color: Colors.black),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: const Cubic(0.25, 0.8, 0.25, 1),
                          transitionBuilder: _transition,
                          child: KeyedSubtree(key: ValueKey('$_userId-${slide.id}'), child: _media(slide)),
                        ),
                      ),
                    ),
                  ),
                  if (_userSwitching || (!_mediaReady && !_dragging && !slide.isText))
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: const Color(0x59000000),
                          child: Center(child: Text(t('common.loading'), style: const TextStyle(color: Colors.white))),
                        ),
                      ),
                    ),
                  if (_paused && _mediaReady && (!slide.isVideo || _videoPlaying || _video != null))
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Color(0x26000000),
                          child: Center(child: Icon(LucideIcons.pause, size: 44, color: Color(0xEBFFFFFF))),
                        ),
                      ),
                    ),
                  // header gradient + buttons
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(12, pad.top + 16, 12, 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x80000000), Color(0x00000000)]),
                      ),
                      child: Row(children: [
                        _IconBtn(icon: LucideIcons.x, size: 22, onTap: _goBack),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_publisherName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                        if (slide.isVideo) ...[
                          _IconBtn(icon: _muted ? LucideIcons.volumeX : LucideIcons.volume2, onTap: _toggleMute),
                          const SizedBox(width: 10),
                        ],
                        _IconBtn(
                          icon: LucideIcons.share2,
                          onTap: () async {
                            final msg = await shareStoryPublic(_userId, publisherName: _publisherName);
                            if (msg != null && context.mounted) showToast(context, msg);
                          },
                        ),
                        if (_isOwner) ...[
                          const SizedBox(width: 10),
                          _IconBtn(icon: LucideIcons.eye, onTap: _openViewers),
                        ] else if (!slide.isVideo)
                          const SizedBox(width: 46),
                      ]),
                    ),
                  ),
                  // progress segments
                  Positioned(
                    top: pad.top + 8,
                    left: 10,
                    right: 10,
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (_, _) => Row(children: [
                        for (var i = 0; i < _slides.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                minHeight: 3,
                                value: i < _index ? 1 : (i == _index ? _progress.value : 0),
                                backgroundColor: Colors.white.withValues(alpha: 0.35),
                                valueColor: const AlwaysStoppedAnimation(Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                  if (!_isOwner)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + pad.bottom),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0x99000000), Color(0x00000000)]),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _reply,
                              focusNode: _replyFocus,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _sendReply(),
                              textInputAction: TextInputAction.send,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: t('stories.replyPlaceholder'),
                                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                filled: true,
                                fillColor: const Color(0x59000000),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0x4DFFFFFF))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0x4DFFFFFF))),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Color(0x80FFFFFF))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Opacity(
                            opacity: _sending || _reply.text.trim().isEmpty ? 0.5 : 1,
                            child: Material(
                              color: context.colors.primary,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _sending || _reply.text.trim().isEmpty ? null : _sendReply,
                                child: const SizedBox(width: 44, height: 44, child: Icon(LucideIcons.send, size: 18, color: Colors.white)),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                ]),
    );
  }

  Widget _transition(Widget child, Animation<double> anim) {
    if (_dir == 'fade') return FadeTransition(opacity: anim, child: child);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sign = (_dir == 'next' ? 1.0 : -1.0) * (rtl ? -1 : 1);
    final incoming = child.key == ValueKey('$_userId-${_current?.id}');
    final offset = incoming
        ? Tween(begin: Offset(sign, 0), end: Offset.zero).animate(anim)
        : Tween(begin: Offset(-sign * 0.28, 0), end: Offset.zero).animate(anim);
    return SlideTransition(position: offset, child: FadeTransition(opacity: Tween(begin: incoming ? 0.35 : 0.0, end: 1.0).animate(anim), child: child));
  }

  Widget _media(StorySlide slide) {
    final children = <Widget>[];
    if (slide.isVideo && slide.mediaUrl != null) {
      final c = _video;
      children.add(Center(
        child: AnimatedOpacity(
          opacity: _videoPlaying || (_paused && c != null) ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: c != null && c.value.isInitialized
              ? SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: c.value.size.width,
                      height: c.value.size.height,
                      child: applyStoryFilter(slide.filterId, VideoPlayer(c)),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ));
    } else if (slide.mediaUrl != null) {
      children.add(Center(
        child: Opacity(
          opacity: _mediaReady ? 1 : 0,
          child: applyStoryFilter(
            slide.filterId,
            CachedNetworkImage(imageUrl: Api.absoluteUrl(slide.mediaUrl)!, fit: BoxFit.contain, fadeInDuration: Duration.zero),
          ),
        ),
      ));
    } else if (slide.caption?.isNotEmpty ?? false) {
      children.add(Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(slide.caption!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, height: 1.4)),
        ),
      ));
    }
    if ((slide.caption?.isNotEmpty ?? false) && !slide.isText && slide.mediaUrl != null) {
      children.add(Positioned(
        left: 16,
        right: 16,
        bottom: 80 + MediaQuery.paddingOf(context).bottom,
        child: Text(slide.caption!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14, shadows: [Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 1))])),
      ));
    }
    return Stack(fit: StackFit.expand, children: children);
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.size = 20});
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0x66000000),
        shape: const CircleBorder(side: BorderSide(color: Color(0x1FFFFFFF))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 38, height: 38, child: Icon(icon, size: size, color: Colors.white)),
        ),
      );
}

class _ViewersSheet extends StatelessWidget {
  const _ViewersSheet({required this.viewers});
  final Future<List<Json>> viewers;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('stories.viewersTitle'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const SizedBox(height: 12),
          Flexible(
            child: FutureBuilder<List<Json>>(
              future: viewers,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Padding(padding: const EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: c.primary)));
                }
                final list = snap.data ?? const [];
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(t('stories.noViewers'), textAlign: TextAlign.center, style: TextStyle(color: c.textMuted)),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      UserAvatar(url: list[i].s('avatar'), name: list[i].str('name'), size: 36),
                      const SizedBox(width: 10),
                      Expanded(child: Text(list[i].str('name'), style: TextStyle(color: c.textPrimary))),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: TextButton(
              style: TextButton.styleFrom(backgroundColor: c.bgElevated, shape: const StadiumBorder()),
              onPressed: () => Navigator.pop(context),
              child: Text(t('common.cancel'), style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}
