import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;
import 'package:video_player/video_player.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import 'stories_controller.dart';

const _textColors = [Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFFFF6584), Color(0xFF6C63FF), Color(0xFF22C55E), Color(0xFFFBBF24), Color(0xFF38BDF8), Color(0xFFF472B6)];
const storyBgPresets = [
  'linear-gradient(135deg,#2563eb 0%,#60a5fa 100%)',
  'linear-gradient(135deg,#0ea5e9 0%,#3b82f6 100%)',
  'linear-gradient(135deg,#f97316 0%,#ec4899 100%)',
  'linear-gradient(135deg,#22c55e 0%,#14b8a6 100%)',
  '#1a1a2e',
  '#ffffff',
];
const _stickers = ['😀', '😂', '😍', '🤩', '😘', '😭', '😡', '😱', '❤️', '🔥', '👍', '👎', '🎉', '✨', '💯', '👋', '💬', '🙏', '💪', '⭐', '🌹', '🎵', '📍', '🌙'];
const _filters = [
  ('none', 'stories.filterNone'),
  ('grayscale', 'stories.filterGray'),
  ('sepia', 'stories.filterSepia'),
  ('vintage', 'stories.filterVintage'),
  ('warm', 'stories.filterWarm'),
  ('vivid', 'stories.filterVivid'),
];
const _minScale = 0.35;
const _maxScale = 4.0;
const _exportMaxDim = 1080;
const _exportQuality = 85;
const _textStorySize = Size(720, 1280);

double _clampScale(double s) => s.clamp(_minScale, _maxScale).toDouble();

class _TextLayer {
  _TextLayer(this.id, this.text, {this.x = 50, this.y = 42, this.color = Colors.white, this.fontSize = 28, this.scale = 1});
  final String id;
  String text;
  double x;
  double y;
  Color color;
  double fontSize;
  double scale;

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'x': x, 'y': y, 'color': _hex(color), 'fontSize': fontSize, 'scale': scale};
}

class _Sticker {
  _Sticker(this.id, this.emoji, this.x, this.y);
  final String id;
  final String emoji;
  double x, y;
  double scale = 1;

  Map<String, dynamic> toJson() => {'id': id, 'emoji': emoji, 'x': x, 'y': y, 'scale': scale};
}

class _Stroke {
  _Stroke(this.color, this.size, this.points);
  final Color color;
  final double size;
  final List<Offset> points;

  Map<String, dynamic> toJson() => {
        'color': _hex(color),
        'size': size,
        'points': [for (final p in points) {'x': p.dx, 'y': p.dy}],
      };
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// components/stories/StoryEditorCanvas.vue
class StoryEditor extends StatefulWidget {
  const StoryEditor({
    super.key,
    this.imageSrc,
    this.videoSrc,
    this.textOnly = false,
    required this.backgroundColor,
    this.initialFilterId = 'none',
    this.initialOverlayJson,
    required this.onBackgroundChanged,
    this.onInteractingChanged,
    this.footer,
  });

  /// Local file path or remote url.
  final String? imageSrc;
  final String? videoSrc;
  final bool textOnly;
  final String backgroundColor;
  final String initialFilterId;
  final String? initialOverlayJson;
  final ValueChanged<String> onBackgroundChanged;

  /// True while the draw tool is selected or a pointer is down on the stage (parent should stop scrolling).
  final ValueChanged<bool>? onInteractingChanged;

  /// شريط سفلي ثابت (مثل الكابشن) يُعرض تحت لوحة الأدوات ويرتفع مع الكيبورد.
  final Widget? footer;

  @override
  State<StoryEditor> createState() => StoryEditorState();
}

class StoryEditorState extends State<StoryEditor> {
  late String _filterId = widget.initialFilterId.isEmpty ? 'none' : widget.initialFilterId;
  final List<_TextLayer> _texts = [];
  final List<_Sticker> _stickerLayers = [];
  final List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;
  String _tool = 'none';
  Color _brushColor = Colors.white;
  double _brushSize = 4;
  String? _selectedText;
  String? _selectedSticker;
  int _stagePointers = 0;
  bool _interacting = false;
  final _textInput = TextEditingController();
  final _textFocus = FocusNode();
  VideoPlayerController? _video;
  int _idSeq = 0;

  // per-gesture state
  Offset _gestureStartPct = Offset.zero;
  Offset _gestureStartFocal = Offset.zero;
  double _gestureStartScale = 1;
  Size _stageSize = Size.zero;

  String get filterId => _filterId;

  int? get videoDurationSeconds {
    final d = _video?.value.duration;
    if (d == null || d.inMilliseconds <= 0) return null;
    return (d.inMilliseconds / 1000).round().clamp(1, 60);
  }

  bool get hasEditorChanges => _filterId != 'none' || _texts.isNotEmpty || _stickerLayers.isNotEmpty || _strokes.isNotEmpty;

  String get overlayJson => jsonEncode({
        'textLayers': [for (final l in _texts) l.toJson()],
        'stickers': [for (final s in _stickerLayers) s.toJson()],
        'strokes': [for (final s in _strokes) s.toJson()],
      });

  _TextLayer? get _selText => _texts.where((l) => l.id == _selectedText).firstOrNull;
  _Sticker? get _selSticker => _stickerLayers.where((s) => s.id == _selectedSticker).firstOrNull;

  bool _isRemote(String s) => s.startsWith('http') || s.startsWith('/uploads') || s.startsWith('/media');

  Color _parseHex(String? raw, [Color fallback = Colors.white]) {
    var h = (raw ?? '').trim().replaceFirst('#', '');
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length == 6) h = 'FF$h';
    final n = int.tryParse(h, radix: 16);
    return n == null ? fallback : Color(n);
  }

  void _loadOverlay(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      for (final item in (data['textLayers'] as List? ?? const [])) {
        if (item is! Map) continue;
        _texts.add(_TextLayer(
          '${item['id'] ?? _newId()}',
          '${item['text'] ?? ''}',
          x: (item['x'] as num?)?.toDouble() ?? 50,
          y: (item['y'] as num?)?.toDouble() ?? 42,
          color: _parseHex(item['color']?.toString()),
          fontSize: (item['fontSize'] as num?)?.toDouble() ?? 28,
          scale: (item['scale'] as num?)?.toDouble() ?? 1,
        ));
      }
      for (final item in (data['stickers'] as List? ?? const [])) {
        if (item is! Map) continue;
        _stickerLayers.add(_Sticker(
          '${item['id'] ?? _newId()}',
          '${item['emoji'] ?? '😀'}',
          (item['x'] as num?)?.toDouble() ?? 50,
          (item['y'] as num?)?.toDouble() ?? 50,
        )..scale = (item['scale'] as num?)?.toDouble() ?? 1);
      }
      for (final item in (data['strokes'] as List? ?? const [])) {
        if (item is! Map) continue;
        final pts = <Offset>[];
        for (final p in (item['points'] as List? ?? const [])) {
          if (p is Map) pts.add(Offset((p['x'] as num?)?.toDouble() ?? 0, (p['y'] as num?)?.toDouble() ?? 0));
        }
        if (pts.isNotEmpty) {
          _strokes.add(_Stroke(_parseHex(item['color']?.toString(), Colors.white), (item['size'] as num?)?.toDouble() ?? 4, pts));
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadOverlay(widget.initialOverlayJson);
    if (widget.textOnly && _texts.isEmpty) {
      final layer = _TextLayer(_newId(), '');
      _texts.add(layer);
      _selectedText = layer.id;
      _tool = 'text';
    }
    final selected = _selText;
    if (selected != null) _textInput.text = selected.text;
    if (_selectedText != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocus.requestFocus();
      });
    }
    _initVideo();
  }

  @override
  void didUpdateWidget(StoryEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoSrc != widget.videoSrc) {
      _video?.dispose();
      _video = null;
      _initVideo();
    }
    if (oldWidget.initialFilterId != widget.initialFilterId) {
      _filterId = widget.initialFilterId.isEmpty ? 'none' : widget.initialFilterId;
    }
  }

  Future<void> _initVideo() async {
    final src = widget.videoSrc;
    if (src == null || src.isEmpty || widget.textOnly) return;
    final c = _isRemote(src)
        ? VideoPlayerController.networkUrl(Uri.parse(Api.absoluteUrl(src)!))
        : VideoPlayerController.file(File(src));
    _video = c;
    try {
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(true);
      await c.play();
      if (mounted && _video == c) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _video?.dispose();
    _textInput.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  void _addText({Offset? at}) {
    final layer = _TextLayer(_newId(), '', x: at?.dx ?? 50, y: at?.dy ?? 42);
    setState(() {
      _texts.add(layer);
      _selectedText = layer.id;
      _selectedSticker = null;
      _tool = 'text';
      _textInput.text = layer.text;
    });
    _textFocus.requestFocus();
  }

  void _onTextTool() {
    final current = _selText;
    if (_tool == 'text' && current != null && current.text.trim().isNotEmpty) {
      _addText();
      return;
    }
    final empty = _texts.where((l) => l.text.trim().isEmpty).lastOrNull;
    if (empty != null) {
      _selectText(empty);
      return;
    }
    if (current != null) {
      _selectText(current);
      return;
    }
    final last = _texts.lastOrNull;
    if (last != null) {
      _selectText(last);
      return;
    }
    _addText();
  }

  void _selectText(_TextLayer l) {
    setState(() {
      _selectedText = l.id;
      _selectedSticker = null;
      _tool = 'text';
      _textInput.text = l.text;
    });
    _textFocus.requestFocus();
  }

  void _clearSelection() {
    _textFocus.unfocus();
    setState(() {
      _selectedText = null;
      _selectedSticker = null;
    });
  }

  void _setTool(String tool) {
    _textFocus.unfocus();
    setState(() {
      _tool = tool;
      if (tool != 'text') _selectedText = null;
      if (tool != 'sticker') _selectedSticker = null;
    });
  }

  void _addSticker(String emoji) {
    final r = math.Random();
    final s = _Sticker(_newId(), emoji, 30 + r.nextDouble() * 40, 30 + r.nextDouble() * 40);
    _textFocus.unfocus();
    setState(() {
      _stickerLayers.add(s);
      _selectedSticker = s.id;
      _selectedText = null;
      _tool = 'sticker';
    });
  }

  Offset _pct(Offset local) {
    if (_stageSize.isEmpty) return const Offset(50, 50);
    return Offset(
      (local.dx / _stageSize.width * 100).clamp(0, 100).toDouble(),
      (local.dy / _stageSize.height * 100).clamp(0, 100).toDouble(),
    );
  }

  void _setStagePointers(int n) {
    _stagePointers = math.max(0, n);
    _notifyInteracting();
  }

  void _notifyInteracting() {
    final v = _tool == 'draw' || _stagePointers > 0;
    if (v == _interacting) return;
    _interacting = v;
    widget.onInteractingChanged?.call(v);
  }

  Future<ui.Image> _resolveImage(ImageProvider provider) {
    final done = Completer<ui.Image>();
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (done.isCompleted) {
          info.dispose();
        } else {
          done.complete(info.image);
        }
      },
      onError: (e, st) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.completeError(e, st ?? StackTrace.current);
      },
    );
    stream.addListener(listener);
    return done.future.timeout(const Duration(seconds: 20));
  }

  /// Bakes background + photo + drawings + text + stickers into a JPEG (Vue storyExport.js).
  Future<File?> exportImage() async {
    final imgSrc = widget.textOnly ? null : widget.imageSrc;
    final dir = Directionality.of(context);
    final stageW = _stageSize.isEmpty ? 270.0 : _stageSize.width;
    ui.Image? source;
    try {
      if (imgSrc != null && imgSrc.isNotEmpty) {
        final ImageProvider base = _isRemote(imgSrc) ? CachedNetworkImageProvider(Api.absoluteUrl(imgSrc)!) : FileImage(File(imgSrc));
        source = await _resolveImage(ResizeImage(base, width: _exportMaxDim, height: _exportMaxDim, policy: ResizeImagePolicy.fit));
      }
      final size = source != null ? Size(source.width.toDouble(), source.height.toDouble()) : _textStorySize;
      final rect = Offset.zero & size;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, rect);

      if (widget.textOnly) {
        paintStoryBackground(canvas, size, widget.backgroundColor);
      } else {
        canvas.drawRect(rect, Paint()..color = const Color(0xFF111111));
        if (source != null) {
          final m = storyFilterMatrix(_filterId);
          paintImage(
            canvas: canvas,
            rect: rect,
            image: source,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            colorFilter: m == null ? null : ColorFilter.matrix(m),
          );
        }
      }

      _StrokesPainter(_strokes).paint(canvas, size);
      final k = size.width / stageW;
      Offset at(double x, double y) => Offset(x / 100 * size.width, y / 100 * size.height);
      void drawCentered(TextPainter tp, Offset center) {
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
        tp.dispose();
      }

      for (final l in _texts) {
        if (l.text.trim().isEmpty) continue;
        final tp = TextPainter(
          text: TextSpan(
            text: l.text,
            style: TextStyle(
              color: l.color,
              fontSize: l.fontSize * l.scale * k,
              fontWeight: FontWeight.w800,
              height: 1.25,
              shadows: [Shadow(color: const Color(0x99000000), blurRadius: 8 * k, offset: Offset(0, 2 * k))],
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: dir,
        )..layout(maxWidth: size.width * 0.88);
        drawCentered(tp, at(l.x, l.y));
      }
      for (final s in _stickerLayers) {
        final tp = TextPainter(
          text: TextSpan(text: s.emoji, style: TextStyle(fontSize: 48 * s.scale * k, height: 1)),
          textDirection: dir,
        )..layout();
        drawCentered(tp, at(s.x, s.y));
      }

      final picture = recorder.endRecording();
      final frame = await picture.toImage(size.width.round(), size.height.round());
      picture.dispose();
      final png = await frame.toByteData(format: ui.ImageByteFormat.png);
      frame.dispose();
      if (png == null) return null;
      final pngBytes = Uint8List.fromList(png.buffer.asUint8List());
      List<int>? jpg;
      try {
        jpg = await Isolate.run(() {
          final decoded = imglib.decodePng(pngBytes);
          if (decoded == null) return null;
          return imglib.encodeJpg(decoded, quality: _exportQuality);
        });
      } catch (_) {
        final decoded = imglib.decodePng(pngBytes);
        if (decoded != null) jpg = imglib.encodeJpg(decoded, quality: _exportQuality);
      }
      if (jpg == null) return null;
      final file = File('${Directory.systemTemp.path}/story-${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(jpg);
      return file;
    } catch (_) {
      return null;
    } finally {
      source?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if ((_tool == 'draw' || _stagePointers > 0) != _interacting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _notifyInteracting();
      });
    }
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // عند فتح الكيبورد نضيّق لوحة الأدوات؛ الستيج يبقى بحجمه عبر Stack
    final toolsMax = kb > 0
        ? math.min(240.0, MediaQuery.sizeOf(context).height * 0.32)
        : math.min(300.0, MediaQuery.sizeOf(context).height * 0.36);

    final toolsPanel = Material(
      color: c.bgCard,
      elevation: 8,
      shadowColor: const Color(0x14000000),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: toolsMax),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _toolTabs(c),
                ..._options(c),
                if (widget.textOnly) _bgCard(c),
              ]),
            ),
          ),
          if (widget.footer != null) widget.footer!,
        ],
      ),
    );

    return LayoutBuilder(builder: (context, constraints) {
      final footerReserve = widget.footer != null ? 64.0 : 0.0;
      final reserve = kb > 0
          ? math.min(toolsMax + footerReserve + 8, constraints.maxHeight * 0.48)
          : math.min(toolsMax + footerReserve + 8, constraints.maxHeight * 0.42);
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: kb > 0 ? kb + reserve : reserve,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 28, offset: Offset(0, 10))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Listener(
                      onPointerDown: (_) => _setStagePointers(_stagePointers + 1),
                      onPointerUp: (_) => _setStagePointers(_stagePointers - 1),
                      onPointerCancel: (_) => _setStagePointers(_stagePointers - 1),
                      child: ClipRRect(borderRadius: BorderRadius.circular(22), child: _stage()),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: kb,
            child: Padding(
              padding: EdgeInsets.only(bottom: kb > 0 ? 0 : safeBottom),
              child: toolsPanel,
            ),
          ),
        ],
      );
    });
  }

  void _onEmptyTap(TapUpDetails d) {
    if (_tool == 'draw') return;
    if (widget.textOnly && (_tool == 'text' || _tool == 'none')) {
      final empty = _texts.where((l) => l.text.trim().isEmpty).lastOrNull;
      if (empty != null) {
        _selectText(empty);
        return;
      }
      if (_texts.isEmpty) {
        _addText(at: _pct(d.localPosition));
        return;
      }
    }
    _clearSelection();
  }

  Widget _stage() {
    return LayoutBuilder(builder: (context, box) {
      _stageSize = box.biggest;
      final w = box.maxWidth;
      return RepaintBoundary(
        child: Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
          DecoratedBox(
            decoration: widget.textOnly ? storyBackgroundDecoration(widget.backgroundColor) : const BoxDecoration(color: Color(0xFF111111)),
          ),
          if (!widget.textOnly) _media(),
          IgnorePointer(child: CustomPaint(painter: _StrokesPainter([..._strokes, ?_currentStroke]))),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _tool == 'draw' ? null : _onEmptyTap,
            onPanStart: _tool != 'draw'
                ? null
                : (d) => setState(() => _currentStroke = _Stroke(_brushColor, _brushSize, [_pct(d.localPosition)])),
            onPanUpdate: _tool != 'draw' ? null : (d) => setState(() => _currentStroke?.points.add(_pct(d.localPosition))),
            onPanEnd: _tool != 'draw'
                ? null
                : (_) => setState(() {
                      if (_currentStroke != null) _strokes.add(_currentStroke!);
                      _currentStroke = null;
                    }),
          ),
          IgnorePointer(
            ignoring: _tool == 'draw',
            child: Stack(clipBehavior: Clip.none, children: [
              for (final l in _texts) _textLayer(l, w),
              for (final s in _stickerLayers) _stickerLayer(s),
            ]),
          ),
        ]),
      );
    });
  }

  Widget _media() {
    Widget? child;
    final img = widget.imageSrc;
    if (img != null && img.isNotEmpty) {
      child = _isRemote(img)
          ? CachedNetworkImage(imageUrl: Api.absoluteUrl(img)!, fit: BoxFit.contain)
          : Image.file(File(img), fit: BoxFit.contain);
    } else if (_video != null && _video!.value.isInitialized) {
      final v = _video!;
      child = FittedBox(fit: BoxFit.contain, child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)));
    }
    if (child == null) return const SizedBox.shrink();
    return applyStoryFilter(_filterId, Center(child: child));
  }

  Widget _layerChrome({required bool selected, required Widget child, required VoidCallback onDelete, required GestureDragUpdateCallback onScaleHandle, required VoidCallback onScaleHandleStart}) {
    if (!selected) return child;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        left: -10,
        top: -10,
        right: -10,
        bottom: -10,
        child: IgnorePointer(child: CustomPaint(painter: _DashedRect())),
      ),
      child,
      PositionedDirectional(
        top: -14,
        start: -14,
        child: GestureDetector(
          onTap: onDelete,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xA6000000), shape: BoxShape.circle),
            child: const Text('×', style: TextStyle(color: Colors.white, fontSize: 18, height: 1)),
          ),
        ),
      ),
      PositionedDirectional(
        bottom: -12,
        end: -12,
        child: GestureDetector(
          onPanStart: (_) => onScaleHandleStart(),
          onPanUpdate: onScaleHandle,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.primary, width: 2),
              boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _positioned({required double x, required double y, required Widget child}) {
    return Positioned(
      left: x / 100 * _stageSize.width,
      top: y / 100 * _stageSize.height,
      child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: child),
    );
  }

  Widget _textLayer(_TextLayer l, double stageW) {
    final selected = _selectedText == l.id;
    double handleStart = 1;
    double handleDy = 0;
    return _positioned(
      x: l.x,
      y: l.y,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectText(l),
        onScaleStart: _tool == 'draw'
            ? null
            : (d) {
                // تحديد الطبقة بدون فتح الكيبورد أثناء السحب
                _textFocus.unfocus();
                setState(() {
                  _selectedText = l.id;
                  _selectedSticker = null;
                  _tool = 'text';
                  _textInput.text = l.text;
                });
                _gestureStartPct = Offset(l.x, l.y);
                _gestureStartFocal = d.focalPoint;
                _gestureStartScale = l.scale;
              },
        onScaleUpdate: _tool == 'draw'
            ? null
            : (d) => setState(() {
                  if (d.pointerCount >= 2) {
                    l.scale = _clampScale(_gestureStartScale * d.scale);
                  } else {
                    final delta = d.focalPoint - _gestureStartFocal;
                    l.x = (_gestureStartPct.dx + delta.dx / _stageSize.width * 100).clamp(0, 100).toDouble();
                    l.y = (_gestureStartPct.dy + delta.dy / _stageSize.height * 100).clamp(0, 100).toDouble();
                  }
                }),
        child: _layerChrome(
          selected: selected,
          onDelete: () => setState(() {
            _texts.remove(l);
            _selectedText = null;
          }),
          onScaleHandleStart: () {
            handleStart = l.scale;
            handleDy = 0;
          },
          onScaleHandle: (d) => setState(() {
            handleDy += d.delta.dy;
            l.scale = _clampScale(handleStart + handleDy * -0.008);
          }),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: stageW * 0.88, minWidth: 96),
            // النص دائماً Text — الكتابة من لوحة الأدوات حتى لا يتخبّط التخطيط مع الكيبورد/السحب
            child: Text(
              l.text.isEmpty ? t('stories.defaultText') : l.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: l.text.isEmpty ? l.color.withValues(alpha: 0.45) : l.color,
                fontSize: l.fontSize * l.scale,
                fontWeight: FontWeight.w800,
                height: 1.25,
                shadows: const [Shadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 2))],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stickerLayer(_Sticker s) {
    final selected = _selectedSticker == s.id;
    double handleStart = 1;
    double handleDy = 0;
    return _positioned(
      x: s.x,
      y: s.y,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _selectedSticker = s.id;
          _selectedText = null;
          _tool = 'sticker';
          _textFocus.unfocus();
        }),
        onScaleStart: _tool == 'draw'
            ? null
            : (d) {
                setState(() {
                  _selectedSticker = s.id;
                  _selectedText = null;
                  _tool = 'sticker';
                });
                _gestureStartPct = Offset(s.x, s.y);
                _gestureStartFocal = d.focalPoint;
                _gestureStartScale = s.scale;
              },
        onScaleUpdate: _tool == 'draw'
            ? null
            : (d) => setState(() {
                  if (d.pointerCount >= 2) {
                    s.scale = _clampScale(_gestureStartScale * d.scale);
                  } else {
                    final delta = d.focalPoint - _gestureStartFocal;
                    s.x = (_gestureStartPct.dx + delta.dx / _stageSize.width * 100).clamp(0, 100).toDouble();
                    s.y = (_gestureStartPct.dy + delta.dy / _stageSize.height * 100).clamp(0, 100).toDouble();
                  }
                }),
        child: _layerChrome(
          selected: selected,
          onDelete: () => setState(() {
            _stickerLayers.remove(s);
            _selectedSticker = null;
          }),
          onScaleHandleStart: () {
            handleStart = s.scale;
            handleDy = 0;
          },
          onScaleHandle: (d) => setState(() {
            handleDy += d.delta.dy;
            s.scale = _clampScale(handleStart + handleDy * -0.008);
          }),
          child: Text(s.emoji, style: TextStyle(fontSize: 48 * s.scale, height: 1)),
        ),
      ),
    );
  }

  Widget _toolTabs(AppColors c) {
    Widget tab(String id, String label, VoidCallback onTap) {
      final active = _tool == id;
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: active ? c.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: active ? const [BoxShadow(color: Color(0x402563EB), blurRadius: 8, offset: Offset(0, 2))] : null,
            ),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : c.textMuted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.bgElevated, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(999)),
      child: Row(children: [
        tab('text', t('stories.toolText'), _onTextTool),
        const SizedBox(width: 6),
        tab('draw', t('stories.toolDraw'), () => _setTool('draw')),
        const SizedBox(width: 6),
        tab('sticker', t('stories.toolSticker'), () => _setTool('sticker')),
        if (!widget.textOnly) ...[
          const SizedBox(width: 6),
          tab('filter', t('stories.toolFilter'), () => _setTool('filter')),
        ],
      ]),
    );
  }

  Widget _card(AppColors c, List<Widget> children, {double top = 12}) => Container(
        margin: EdgeInsets.only(top: top),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.bgElevated, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: c.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _label(AppColors c, String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textPrimary)));

  Widget _sublabel(AppColors c, String text) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textMuted)));

  Widget _swatches(AppColors c, Color selected, ValueChanged<Color> onPick) => SizedBox(
        height: 38,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final col in _textColors)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: GestureDetector(
                onTap: () => onPick(col),
                child: AnimatedScale(
                  scale: selected == col ? 1.06 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(color: selected == col ? c.primary : c.border, width: selected == col ? 2 : 1),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );

  Widget _range(AppColors c, String label, double value, double min, double max, ValueChanged<double> onChanged, {String? valueLabel, int? divisions}) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52),
            child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textSecondary)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 4, overlayShape: SliderComponentShape.noOverlay),
              child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, divisions: divisions, activeColor: c.primary, onChanged: onChanged),
            ),
          ),
          if (valueLabel != null)
            SizedBox(
              width: 22,
              child: Text(valueLabel, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.primary)),
            ),
        ]),
      );

  List<Widget> _options(AppColors c) {
    final sel = _selText;
    if (_tool == 'text' && sel != null) {
      return [
        _card(c, [
          _label(c, t('stories.textEdit')),
          TextField(
            controller: _textInput,
            focusNode: _textFocus,
            maxLines: 3,
            minLines: 1,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onChanged: (v) => setState(() => sel.text = v),
            onSubmitted: (_) => _textFocus.unfocus(),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary, height: 1.35),
            decoration: InputDecoration(
              hintText: t('stories.defaultText'),
              hintStyle: TextStyle(color: c.textMuted, fontWeight: FontWeight.w600),
              filled: true,
              fillColor: c.bgCard,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),
          _sublabel(c, t('stories.textColor')),
          _swatches(c, sel.color, (col) => setState(() => sel.color = col)),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(t('stories.textMoveHint'), style: TextStyle(fontSize: 10, color: c.textMuted, height: 1.45)),
          ),
          _range(c, t('stories.textSize'), sel.scale, _minScale, _maxScale, (v) => setState(() => sel.scale = v)),
        ]),
      ];
    }
    if (_tool == 'draw') {
      return [
        _card(c, [
          _sublabel(c, t('stories.brushColor')),
          _swatches(c, _brushColor, (col) => setState(() => _brushColor = col)),
          _range(c, t('stories.brushSize'), _brushSize, 2, 12, (v) => setState(() => _brushSize = v.roundToDouble()),
              valueLabel: '${_brushSize.round()}', divisions: 10),
        ]),
      ];
    }
    if (_tool == 'sticker') {
      final ss = _selSticker;
      return [
        _card(c, [
          _label(c, t('stories.pickSticker')),
          GridView.count(
            crossAxisCount: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (final em in _stickers)
                Material(
                  color: c.bgCard,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.border)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _addSticker(em),
                    child: Center(child: Text(em, style: const TextStyle(fontSize: 24, height: 1))),
                  ),
                ),
            ],
          ),
          if (ss != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: c.border),
            const SizedBox(height: 12),
            Text(t('stories.stickerMoveHint'), style: TextStyle(fontSize: 10, color: c.textMuted, height: 1.45)),
            _range(c, t('stories.stickerSize'), ss.scale, _minScale, _maxScale, (v) => setState(() => ss.scale = v)),
          ],
        ]),
      ];
    }
    if (_tool == 'filter') {
      return [
        _card(c, [
          _label(c, t('stories.filtersLabel')),
          SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final (id, key) in _filters)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filterId = id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _filterId == id ? c.primary.withValues(alpha: 0.14) : c.bgCard,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _filterId == id ? c.primary : c.border),
                      ),
                      child: Text(t(key),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _filterId == id ? c.primary : c.textSecondary)),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ];
    }
    return const [];
  }

  Widget _bgCard(AppColors c) => _card(c, top: 8, [
        _label(c, t('stories.bgLabel')),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final bg in storyBgPresets)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: GestureDetector(
                  onTap: () => widget.onBackgroundChanged(bg),
                  child: AnimatedScale(
                    scale: widget.backgroundColor == bg ? 1.05 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 40,
                      height: 40,
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: widget.backgroundColor == bg ? c.primary : c.border, width: 2),
                      ),
                      decoration: storyBackgroundDecoration(bg, radius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]);
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.size * 0.15 * size.width / 100;
      final path = Path()..moveTo(s.points.first.dx / 100 * size.width, s.points.first.dy / 100 * size.height);
      for (final p in s.points.skip(1)) {
        path.lineTo(p.dx / 100 * size.width, p.dy / 100 * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _DashedRect extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
