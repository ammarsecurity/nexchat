import 'package:flutter/material.dart';

/// Discover (تعارف) brand — warm red, independent from app blue primary.
abstract final class DiscoverTheme {
  static const red = Color(0xFFE11D48);
  static const redDeep = Color(0xFF9F1239);
  static const redHot = Color(0xFFFF4D6D);
  static const redSoft = Color(0x33E11D48);
  static const ink = Color(0xFF1A0A0F);
  static const slate = Color(0xFF64748B);
  static const cardRadius = 20.0;

  static const heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x55E11D48),
      Color(0x22000000),
      Color(0xCC7F1D1D),
      Color(0xF54C0519),
    ],
    stops: [0, 0.28, 0.65, 1],
  );

  static const pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFF7F8),
      Color(0xFFFFE4E6),
      Color(0xFFFFF1F2),
    ],
    stops: [0, 0.45, 1],
  );

  static const ctaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B8A), Color(0xFFE11D48), Color(0xFFBE123C)],
  );

  static const cardScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x66000000),
      Color(0x00000000),
      Color(0x00000000),
      Color(0xE6110510),
    ],
    stops: [0, 0.18, 0.48, 1],
  );

  static List<BoxShadow> get cardShadow => const [
        BoxShadow(color: Color(0x28E11D48), blurRadius: 28, offset: Offset(0, 14)),
        BoxShadow(color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4)),
      ];

  static List<BoxShadow> get likeShadow => const [
        BoxShadow(color: Color(0x55E11D48), blurRadius: 22, offset: Offset(0, 10)),
      ];
}
