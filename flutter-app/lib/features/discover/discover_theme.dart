import 'package:flutter/material.dart';

/// Discover (تعارف) brand — warm red, independent from app blue primary.
abstract final class DiscoverTheme {
  static const red = Color(0xFFE11D48);
  static const redDeep = Color(0xFF9F1239);
  static const redHot = Color(0xFFFF4D6D);
  static const redSoft = Color(0x33E11D48);
  static const ink = Color(0xFF1A0A0F);

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
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFF1F2),
      Color(0xFFFFE4E6),
      Color(0xFFFFF7F8),
    ],
  );

  static const ctaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B8A), Color(0xFFE11D48), Color(0xFFBE123C)],
  );
}
