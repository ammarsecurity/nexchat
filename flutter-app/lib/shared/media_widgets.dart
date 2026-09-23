import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/i18n/i18n.dart';
import '../core/network/api_client.dart';
import '../core/theme/app_colors.dart';
import '../services/media.dart';
import 'widgets.dart';

/// Decode width for images shown inside message bubbles (full-screen viewer uses the original).
const bubbleImageCacheWidth = 800;

ImageProvider mediaImage(String url, {int? cacheWidth}) {
  final ImageProvider provider;
  if (url.startsWith('/data') || url.startsWith('file:') || (Platform.isIOS && url.startsWith('/var'))) {
    provider = FileImage(File(url.replaceFirst('file://', '')));
  } else {
    provider = CachedNetworkImageProvider(Api.absoluteUrl(url)!);
  }
  return ResizeImage.resizeIfNeeded(cacheWidth, null, provider);
}

/// linkifyText() — URLs become tappable spans.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(this.text, {super.key, required this.style, required this.linkColor});
  final String text;
  final TextStyle style;
  final Color linkColor;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _recognizers = <TapGestureRecognizer>[];
  static final _re = RegExp(r'(https?://[^\s<>]+)|(www\.[^\s<>]+)', caseSensitive: false);

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _re.allMatches(widget.text)) {
      if (m.start > last) spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      final match = m.group(0)!;
      final href = match.startsWith('http') ? match : 'https://$match';
      final rec = TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      _recognizers.add(rec);
      spans.add(TextSpan(
        text: match,
        recognizer: rec,
        style: TextStyle(color: widget.linkColor, decoration: TextDecoration.underline),
      ));
      last = m.end;
    }
    if (last < widget.text.length) spans.add(TextSpan(text: widget.text.substring(last)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

String formatAudioDuration(Duration? d) {
  if (d == null || d.inMilliseconds <= 0) return '0:00';
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// One global audio player so starting a clip pauses the previous one (like the Vue page).
class _AudioHub {
  static AudioPlayer? current;
}

class AudioBubble extends StatefulWidget {
  const AudioBubble({super.key, required this.url, required this.mine});
  final String url;
  final bool mine;

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final _player = AudioPlayer();
  Duration _pos = Duration.zero;
  Duration? _dur;
  bool _playing = false;
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPositionChanged.listen((p) => setState(() => _pos = p)));
    _subs.add(_player.onDurationChanged.listen((d) => setState(() => _dur = d)));
    _subs.add(_player.onPlayerStateChanged.listen((s) => setState(() => _playing = s == PlayerState.playing)));
    _subs.add(_player.onPlayerComplete.listen((_) => setState(() => _pos = Duration.zero)));
    _setSource();
  }

  Future<void> _setSource() async {
    try {
      final u = widget.url;
      if (u.startsWith('/') && !u.startsWith('/uploads') && File(u).existsSync()) {
        await _player.setSourceDeviceFile(u);
      } else {
        await _player.setSourceUrl(Api.absoluteUrl(u)!);
      }
      final d = await _player.getDuration();
      if (mounted && d != null) setState(() => _dur = d);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(AudioBubble old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _setSource();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    if (_AudioHub.current == _player) _AudioHub.current = null;
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_AudioHub.current != null && _AudioHub.current != _player) await _AudioHub.current!.pause();
    _AudioHub.current = _player;
    await _player.resume();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = widget.mine ? Colors.white : c.primary;
    final pct = (_dur == null || _dur!.inMilliseconds == 0) ? 0.0 : (_pos.inMilliseconds / _dur!.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: 220,
      child: Row(children: [
        Material(
          color: widget.mine ? Colors.white.withValues(alpha: 0.22) : c.primarySoft,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggle,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(_playing ? LucideIcons.pause : LucideIcons.play, size: 18, color: fg),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: widget.mine ? Colors.white.withValues(alpha: 0.3) : c.border,
                valueColor: AlwaysStoppedAnimation(fg),
              ),
            ),
            const SizedBox(height: 6),
            Text('${formatAudioDuration(_pos)} / ${formatAudioDuration(_dur)}',
                style: TextStyle(fontSize: 11, color: widget.mine ? Colors.white70 : c.textMuted)),
          ]),
        ),
      ]),
    );
  }
}

/// AlbumMessageBubble.vue
class AlbumGrid extends StatelessWidget {
  const AlbumGrid({super.key, required this.urls, required this.onOpen});
  final List<String> urls;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = urls.take(4).toList();
    final extra = urls.length - 4;
    Widget tile(int i) => GestureDetector(
          onTap: () => onOpen(i),
          child: Stack(fit: StackFit.expand, children: [
            Container(color: c.bgElevated, child: Image(image: mediaImage(shown[i], cacheWidth: bubbleImageCacheWidth), fit: BoxFit.cover)),
            if (i == 3 && extra > 0)
              Container(
                color: const Color(0x8C000000),
                alignment: Alignment.center,
                child: Text('+$extra', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
              ),
          ]),
        );
    const gap = 3.0;
    final w = (MediaQuery.sizeOf(context).width * 0.72).clamp(0.0, 280.0);
    final half = (w - gap) / 2;
    Widget grid;
    switch (shown.length) {
      case 1:
        grid = SizedBox(width: w, height: w, child: tile(0));
      case 2:
        grid = Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: half, height: half, child: tile(0)),
          const SizedBox(width: gap),
          SizedBox(width: half, height: half, child: tile(1)),
        ]);
      case 3:
        grid = Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: half, height: w, child: tile(0)),
          const SizedBox(width: gap),
          Column(children: [
            SizedBox(width: half, height: half, child: tile(1)),
            const SizedBox(height: gap),
            SizedBox(width: half, height: half, child: tile(2)),
          ]),
        ]);
      default:
        grid = Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: half, height: half, child: tile(0)),
            const SizedBox(width: gap),
            SizedBox(width: half, height: half, child: tile(1)),
          ]),
          const SizedBox(height: gap),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: half, height: half, child: tile(2)),
            const SizedBox(width: gap),
            SizedBox(width: half, height: half, child: tile(3)),
          ]),
        ]);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: grid);
  }
}

/// ShortFilmMessageBubble.vue
class ShortFilmCard extends StatelessWidget {
  const ShortFilmCard({super.key, required this.title, this.thumbnailUrl, required this.onOpen, this.mine = false});
  final String title;
  final String? thumbnailUrl;
  final VoidCallback onOpen;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        width: 260,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.bgElevated,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              if (thumbnailUrl != null)
                Image(image: mediaImage(thumbnailUrl!, cacheWidth: bubbleImageCacheWidth), fit: BoxFit.cover)
              else
                Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0x336C63FF), Color(0x1FFF6584)])),
                  child: Icon(LucideIcons.film, size: 28, color: c.primary),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.center, colors: [Color(0x8C000000), Color(0x00000000)]),
                ),
              ),
              Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xE66C63FF),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 4))],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, size: 26, color: Colors.white),
                ),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
            color: mine ? Colors.white.withValues(alpha: 0.08) : c.bgCard,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('shortFilms.title').toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: mine ? const Color(0xFFC8C4FF) : c.primary)),
              const SizedBox(height: 4),
              Text(title.isEmpty ? t('shortFilms.title') : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.35, color: mine ? Colors.white : c.textPrimary)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Inline chat video with tap-to-play and an expand button.
class ChatVideo extends StatefulWidget {
  const ChatVideo({super.key, required this.url, required this.onExpand});
  final String url;
  final VoidCallback onExpand;

  @override
  State<ChatVideo> createState() => _ChatVideoState();
}

class _ChatVideoState extends State<ChatVideo> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final u = widget.url;
    _ctrl = (u.startsWith('/') && !u.startsWith('/uploads'))
        ? VideoPlayerController.file(File(u))
        : VideoPlayerController.networkUrl(Uri.parse(Api.absoluteUrl(u)!));
    _ctrl!.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((_) {});
    _ctrl!.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl!;
    final playing = ctrl.value.isPlaying;
    final ratio = _ready && ctrl.value.aspectRatio > 0 ? ctrl.value.aspectRatio : 16 / 9;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 340),
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: Colors.black, child: _ready ? VideoPlayer(ctrl) : null),
            GestureDetector(
              onTap: () {
                if (playing) {
                  ctrl.pause();
                } else {
                  ctrl.play();
                }
              },
              child: playing
                  ? const SizedBox.expand()
                  : Container(
                      color: const Color(0x33000000),
                      alignment: Alignment.center,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, size: 36, color: Colors.white),
                      ),
                    ),
            ),
            PositionedDirectional(
              top: 8,
              end: 8,
              child: GestureDetector(
                onTap: () {
                  ctrl.pause();
                  widget.onExpand();
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: const Color(0x80000000), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(LucideIcons.maximize2, size: 16, color: Colors.white),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Full-screen image viewer with album paging and download (image-modal in ConversationChatView.vue).
Future<void> showImageViewer(BuildContext context, List<String> urls, {int start = 0}) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, _, _) => _ImageViewer(urls: urls, start: start),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.urls, required this.start});
  final List<String> urls;
  final int start;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final _page = PageController(initialPage: widget.start);
  late int _index = widget.start;
  bool _downloading = false;

  Future<void> _run(Future<void> Function() task) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await task();
      if (mounted) showToast(context, t('conversationChat.downloadSuccess'));
    } catch (_) {
      if (mounted) showToast(context, t('conversationChat.downloadFailed'), error: true);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _download() {
    if (widget.urls.length == 1) {
      _run(() => downloadMediaUrl(widget.urls.first));
      return;
    }
    showAppSheet<void>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(t('conversationChat.downloadChoose'), style: TextStyle(fontWeight: FontWeight.w700, color: ctx.colors.textPrimary)),
        SheetAction(
          icon: LucideIcons.download,
          label: '${t('conversationChat.downloadCurrentPhoto')}  ·  ${_index + 1}/${widget.urls.length}',
          onTap: () {
            Navigator.pop(ctx);
            _run(() => downloadMediaUrl(widget.urls[_index], filename: 'album-${_index + 1}.jpg'));
          },
        ),
        SheetAction(
          icon: LucideIcons.images,
          label: '${t('conversationChat.downloadAllPhotos')}  ·  ${widget.urls.length}',
          onTap: () {
            Navigator.pop(ctx);
            _run(() => downloadAlbumImages(widget.urls));
          },
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('common.cancel'))),
        const SizedBox(height: 8),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.urls.length > 1;
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _page,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(child: Image(image: mediaImage(widget.urls[i]), fit: BoxFit.contain)),
          ),
        ),
        Positioned(
          top: pad.top + 8,
          left: 12,
          right: 12,
          child: Row(children: [
            if (multi)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(999)),
                child: Text(t('conversationChat.albumViewerCounter', {'current': _index + 1, 'total': widget.urls.length}),
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            const Spacer(),
            IconButton(
              onPressed: _downloading ? null : _download,
              icon: const Icon(LucideIcons.download, color: Colors.white, size: 20),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x, color: Colors.white, size: 22)),
          ]),
        ),
        if (multi && widget.urls.length <= 12)
          Positioned(
            bottom: pad.bottom + 20,
            left: 0,
            right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < widget.urls.length; i++)
                GestureDetector(
                  onTap: () => _page.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _index ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// Full-screen video modal.
Future<void> showVideoViewer(BuildContext context, String url) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _VideoViewer(url: url),
  ));
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.url});
  final String url;

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController _ctrl = VideoPlayerController.networkUrl(Uri.parse(Api.absoluteUrl(widget.url)!));
  bool _ready = false;
  bool _failed = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _ctrl.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _ctrl.play();
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await downloadMediaUrl(widget.url, kind: 'video');
      if (mounted) showToast(context, t('conversationChat.downloadSuccess'));
    } catch (_) {
      if (mounted) showToast(context, t('conversationChat.downloadFailed'), error: true);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _ctrl.value;
    final pad = MediaQuery.paddingOf(context);
    final pct = v.duration.inMilliseconds == 0 ? 0.0 : v.position.inMilliseconds / v.duration.inMilliseconds;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: _ready
              ? GestureDetector(
                  onTap: () => v.isPlaying ? _ctrl.pause() : _ctrl.play(),
                  child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_ctrl)),
                )
              : _failed || v.hasError
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(LucideIcons.circleAlert, color: Colors.white70, size: 40),
                      const SizedBox(height: 10),
                      Text(t('common.error'), style: const TextStyle(color: Colors.white70)),
                    ])
                  : const CircularProgressIndicator(color: Colors.white),
        ),
        Positioned(
          top: pad.top + 8,
          right: 8,
          left: 8,
          child: Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x, color: Colors.white)),
            const Spacer(),
            IconButton(
              onPressed: _downloading ? null : _download,
              icon: _downloading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(LucideIcons.download, color: Colors.white, size: 20),
            ),
          ]),
        ),
        Positioned(
          bottom: pad.bottom + 16,
          left: 16,
          right: 16,
          child: Row(children: [
            IconButton(
              onPressed: () => v.isPlaying ? _ctrl.pause() : _ctrl.play(),
              icon: Icon(v.isPlaying ? LucideIcons.pause : LucideIcons.play, color: Colors.white),
            ),
            Expanded(
              child: GestureDetector(
                onTapDown: (d) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null || v.duration == Duration.zero) return;
                  final w = box.size.width - 32 - 96;
                  final x = (d.localPosition.dx / w).clamp(0.0, 1.0);
                  _ctrl.seekTo(v.duration * x);
                },
                child: LinearProgressIndicator(
                  value: pct.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
            IconButton(
              onPressed: () => _ctrl.setVolume(v.volume > 0 ? 0 : 1),
              icon: Icon(v.volume > 0 ? LucideIcons.volume2 : LucideIcons.volumeX, color: Colors.white),
            ),
          ]),
        ),
      ]),
    );
  }
}
