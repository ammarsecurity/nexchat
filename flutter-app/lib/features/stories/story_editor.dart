import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import 'stories_controller.dart';

const _textColors = [Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFFFF6584), Color(0xFF6C63FF), Color(0xFF22C55E), Color(0xFFFBBF24)];
const storyBgPresets = [
  'linear-gradient(135deg,#2563eb 0%,#60a5fa 100%)',
  'linear-gradient(135deg,#0ea5e9 0%,#3b82f6 100%)',
  'linear-gradient(135deg,#f97316 0%,#ec4899 100%)',
  'linear-gradient(135deg,#22c55e 0%,#14b8a6 100%)',
  '#1a1a2e',
  '#ffffff',
];
const _stickers = ['😀', '😂', '❤️', '🔥', '👍', '🎉', '✨', '💯', '😍', '🤩', '👋', '💬'];
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
const _exportWidth = 1080.0;

double _clampScale(double s) => s.clamp(_minScale, _maxScale).toDouble();

class _TextLayer {
  _TextLayer(this.id, this.text);
  final String id;
  String text;
  double x = 50, y = 45;
  Color color = Colors.white;
  double fontSize = 22;
  double scale = 1;

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
    required this.onBackgroundChanged,
  });

  /// Local file path or remote url.
  final String? imageSrc;
  final String? videoSrc;
  final bool textOnly;
  final String backgroundColor;
  final String initialFilterId;
  final ValueChanged<String> onBackgroundChanged;

  @override
  State<StoryEditor> createState() => StoryEditorState();
}

class StoryEditorState extends State<StoryEditor> {
  final _boundary = GlobalKey();
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
  bool _exporting = false;
  final _textInput = TextEditingController();
  VideoPlayerController? _video;
  int _idSeq = 0;

  // per-gesture state
  Offset _gestureStartPct = Offset.zero;
  Offset _gestureStartFocal = Offset.zero;
  double _gestureStartScale = 1;
  Size _stageSize = Size.zero;

  String get filterId => _filterId;

  bool get hasEditorChanges => _filterId != 'none' || _texts.isNotEmpty || _stickerLayers.isNotEmpty || _strokes.isNotEmpty;

  String get overlayJson => jsonEncode({
        'textLayers': [for (final l in _texts) l.toJson()],
        'stickers': [for (final s in _stickerLayers) s.toJson()],
        'strokes': [for (final s in _strokes) s.toJson()],
      });

  _TextLayer? get _selText => _texts.where((l) => l.id == _selectedText).firstOrNull;
  _Sticker? get _selSticker => _stickerLayers.where((s) => s.id == _selectedSticker).firstOrNull;

  bool _isRemote(String s) => s.startsWith('http') || s.startsWith('/uploads') || s.startsWith('/media');

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  void _addText() {
    final layer = _TextLayer(_newId(), t('stories.defaultText'));
    setState(() {
      _texts.add(layer);
      _selectedText = layer.id;
      _selectedSticker = null;
      _tool = 'text';
      _textInput.text = layer.text;
    });
  }

  void _selectText(_TextLayer l) {
    setState(() {
      _selectedText = l.id;
      _selectedSticker = null;
      _tool = 'text';
      _textInput.text = l.text;
    });
  }

  void _addSticker(String emoji) {
    final r = math.Random();
    final s = _Sticker(_newId(), emoji, 30 + r.nextDouble() * 40, 30 + r.nextDouble() * 40);
    setState(() {
      _stickerLayers.add(s);
      _selectedSticker = s.id;
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

  /// Returns a PNG of the stage at 1080px width (like storyExport.js composing the frame).
  Future<File?> exportImage() async {
    setState(() {
      _exporting = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    try {
      final ctx = _boundary.currentContext;
      final ro = ctx?.findRenderObject();
      if (ro is! RenderRepaintBoundary) return null;
      final ratio = _exportWidth / ro.size.width;
      final img = await ro.toImage(pixelRatio: ratio);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (bytes == null) return null;
      final file = File('${Directory.systemTemp.path}/story-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      return file;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = MediaQuery.sizeOf(context).height;
    final stageMaxH = math.max(200.0, math.min(h * 0.42, 320.0));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 320, maxHeight: stageMaxH),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 32, offset: Offset(0, 8))],
                ),
                clipBehavior: Clip.antiAlias,
                child: ClipRRect(borderRadius: BorderRadius.circular(24), child: _stage()),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: c.bgCard,
          border: Border(top: BorderSide(color: c.border)),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 20, offset: Offset(0, -4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _toolTabs(c),
          ..._options(c),
          if (widget.textOnly) _bgCard(c),
        ]),
      ),
    ]);
  }

  Widget _stage() {
    return LayoutBuilder(builder: (context, box) {
      _stageSize = box.biggest;
      final w = box.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() {
          _selectedSticker = null;
          _selectedText = null;
        }),
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
        child: RepaintBoundary(
          key: _boundary,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: widget.textOnly ? storyBackgroundDecoration(widget.backgroundColor) : const BoxDecoration(color: Color(0xFF111111)),
              ),
            ),
            if (!widget.textOnly) Positioned.fill(child: _media()),
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _StrokesPainter([..._strokes, ?_currentStroke]))),
            ),
            for (final l in _texts) _textLayer(l, w),
            for (final s in _stickerLayers) _stickerLayer(s),
          ]),
        ),
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
    if (!selected || _exporting) return child;
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
                _selectText(l);
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
            constraints: BoxConstraints(maxWidth: stageW * 0.9, minWidth: 80),
            child: Text(
              l.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: l.color,
                fontSize: l.fontSize * l.scale,
                fontWeight: FontWeight.w700,
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
        onTap: () => setState(() => _selectedSticker = s.id),
        onScaleStart: _tool == 'draw'
            ? null
            : (d) {
                setState(() => _selectedSticker = s.id);
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
        tab('text', t('stories.toolText'), _addText),
        const SizedBox(width: 6),
        tab('draw', t('stories.toolDraw'), () => setState(() => _tool = 'draw')),
        const SizedBox(width: 6),
        tab('sticker', t('stories.toolSticker'), () => setState(() => _tool = 'sticker')),
        const SizedBox(width: 6),
        tab('filter', t('stories.toolFilter'), () => setState(() => _tool = 'filter')),
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
            onChanged: (v) => setState(() => sel.text = v),
            style: TextStyle(fontSize: 14, color: c.textPrimary),
            decoration: InputDecoration(
              hintText: t('stories.defaultText'),
              isDense: true,
              filled: true,
              fillColor: c.bgCard,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.primary)),
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
