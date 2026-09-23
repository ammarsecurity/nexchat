import 'dart:math' as math;

/// CSS filter functions (grayscale, sepia, saturate, contrast, hue-rotate) as 5x4 colour matrices.
class CssFilter {
  const CssFilter(this.matrix);
  final List<double> matrix;

  factory CssFilter.grayscale(double a) {
    final s = 1 - a;
    return CssFilter([
      0.2126 + 0.7874 * s, 0.7152 - 0.7152 * s, 0.0722 - 0.0722 * s, 0, 0,
      0.2126 - 0.2126 * s, 0.7152 + 0.2848 * s, 0.0722 - 0.0722 * s, 0, 0,
      0.2126 - 0.2126 * s, 0.7152 - 0.7152 * s, 0.0722 + 0.9278 * s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  factory CssFilter.sepia(double a) {
    final s = 1 - a;
    return CssFilter([
      0.393 + 0.607 * s, 0.769 - 0.769 * s, 0.189 - 0.189 * s, 0, 0,
      0.349 - 0.349 * s, 0.686 + 0.314 * s, 0.168 - 0.168 * s, 0, 0,
      0.272 - 0.272 * s, 0.534 - 0.534 * s, 0.131 + 0.869 * s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  factory CssFilter.saturate(double s) => CssFilter([
        0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
        0, 0, 0, 1, 0,
      ]);

  factory CssFilter.contrast(double c) {
    final o = 255 * (0.5 - 0.5 * c);
    return CssFilter([c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0]);
  }

  factory CssFilter.hueRotate(double deg) {
    final r = deg * math.pi / 180;
    final cs = math.cos(r), sn = math.sin(r);
    return CssFilter([
      0.213 + cs * 0.787 - sn * 0.213, 0.715 - cs * 0.715 - sn * 0.715, 0.072 - cs * 0.072 + sn * 0.928, 0, 0,
      0.213 - cs * 0.213 + sn * 0.143, 0.715 + cs * 0.285 + sn * 0.140, 0.072 - cs * 0.072 - sn * 0.283, 0, 0,
      0.213 - cs * 0.213 - sn * 0.787, 0.715 - cs * 0.715 + sn * 0.715, 0.072 + cs * 0.928 + sn * 0.072, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  /// `a.then(b)` applies a first, then b — same order as a CSS filter list.
  CssFilter then(CssFilter next) {
    final a = matrix, b = next.matrix;
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var sum = c == 4 ? b[r * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          sum += b[r * 5 + k] * a[k * 5 + c];
        }
        out[r * 5 + c] = sum;
      }
    }
    return CssFilter(out);
  }
}
