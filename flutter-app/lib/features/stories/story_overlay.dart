import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Paints story overlayJson (text / stickers / strokes, percent coords) for the viewer fallback
/// when a slide was not baked to an image (old text stories, video overlays).
class StoryOverlayLayer extends StatelessWidget {
  const StoryOverlayLayer({super.key, this.overlayJson});
  final String? overlayJson;

  @override
  Widget build(BuildContext context) {
    final data = parseStoryOverlay(overlayJson);
    if (data == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(painter: _OverlayPainter(data, Directionality.of(context))),
    );
  }
}

class StoryOverlayData {
  const StoryOverlayData({required this.texts, required this.stickers, required this.strokes});
  final List<StoryOverlayText> texts;
  final List<StoryOverlaySticker> stickers;
  final List<StoryOverlayStroke> strokes;

  bool get isEmpty => texts.isEmpty && stickers.isEmpty && strokes.isEmpty;
}

class StoryOverlayText {
  const StoryOverlayText({required this.text, required this.x, required this.y, required this.color, required this.fontSize, required this.scale});
  final String text;
  final double x, y, fontSize, scale;
  final Color color;
}

class StoryOverlaySticker {
  const StoryOverlaySticker({required this.emoji, required this.x, required this.y, required this.scale});
  final String emoji;
  final double x, y, scale;
}

class StoryOverlayStroke {
  const StoryOverlayStroke({required this.color, required this.size, required this.points});
  final Color color;
  final double size;
  final List<Offset> points;
}

String? storyOverlayAsString(Object? raw) {
  if (raw == null) return null;
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty || s == 'null') return null;
    return s;
  }
  if (raw is Map || raw is List) {
    try {
      return jsonEncode(raw);
    } catch (_) {
      return null;
    }
  }
  return null;
}

Color parseStoryHex(String? raw, [Color fallback = Colors.white]) {
  var h = (raw ?? '').trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) h = 'FF$h';
  if (h.length == 8) {
    final n = int.tryParse(h, radix: 16);
    if (n != null) return Color(n);
  }
  return fallback;
}

StoryOverlayData? parseStoryOverlay(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final data = jsonDecode(raw);
    if (data is! Map) return null;
    final texts = <StoryOverlayText>[];
    for (final item in (data['textLayers'] as List? ?? const [])) {
      if (item is! Map) continue;
      final text = '${item['text'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      texts.add(StoryOverlayText(
        text: text,
        x: (item['x'] as num?)?.toDouble() ?? 50,
        y: (item['y'] as num?)?.toDouble() ?? 42,
        color: parseStoryHex(item['color']?.toString()),
        fontSize: (item['fontSize'] as num?)?.toDouble() ?? 28,
        scale: (item['scale'] as num?)?.toDouble() ?? 1,
      ));
    }
    final stickers = <StoryOverlaySticker>[];
    for (final item in (data['stickers'] as List? ?? const [])) {
      if (item is! Map) continue;
      final emoji = '${item['emoji'] ?? ''}'.trim();
      if (emoji.isEmpty) continue;
      stickers.add(StoryOverlaySticker(
        emoji: emoji,
        x: (item['x'] as num?)?.toDouble() ?? 50,
        y: (item['y'] as num?)?.toDouble() ?? 50,
        scale: (item['scale'] as num?)?.toDouble() ?? 1,
      ));
    }
    final strokes = <StoryOverlayStroke>[];
    for (final item in (data['strokes'] as List? ?? const [])) {
      if (item is! Map) continue;
      final pts = <Offset>[];
      for (final p in (item['points'] as List? ?? const [])) {
        if (p is Map) pts.add(Offset((p['x'] as num?)?.toDouble() ?? 0, (p['y'] as num?)?.toDouble() ?? 0));
      }
      if (pts.isNotEmpty) {
        strokes.add(StoryOverlayStroke(
          color: parseStoryHex(item['color']?.toString()),
          size: (item['size'] as num?)?.toDouble() ?? 4,
          points: pts,
        ));
      }
    }
    final parsed = StoryOverlayData(texts: texts, stickers: stickers, strokes: strokes);
    return parsed.isEmpty ? null : parsed;
  } catch (_) {
    return null;
  }
}

String? firstOverlayText(String? raw) => parseStoryOverlay(raw)?.texts.firstOrNull?.text;

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.data, this.dir);
  final StoryOverlayData data;
  final ui.TextDirection dir;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    for (final s in data.strokes) {
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

    final k = size.width / 270;
    Offset at(double x, double y) => Offset(x / 100 * size.width, y / 100 * size.height);
    void drawCentered(TextPainter tp, Offset center) {
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }

    for (final l in data.texts) {
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
    for (final s in data.stickers) {
      final tp = TextPainter(
        text: TextSpan(text: s.emoji, style: TextStyle(fontSize: 48 * s.scale * k, height: 1)),
        textDirection: dir,
      )..layout();
      drawCentered(tp, at(s.x, s.y));
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => oldDelegate.data != data || oldDelegate.dir != dir;
}
