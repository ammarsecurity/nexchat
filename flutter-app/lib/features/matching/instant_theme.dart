import 'package:flutter/material.dart';

/// Instant chat brand — electric violet, separate from Discover red and app blue.
abstract final class InstantTheme {
  static const violet = Color(0xFF7C3AED);
  static const violetDeep = Color(0xFF5B21B6);
  static const violetHot = Color(0xFFA78BFA);
  static const violetSoft = Color(0x337C3AED);
  static const ink = Color(0xFF1E1033);
  static const mist = Color(0xFFF5F3FF);

  static const pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF5F3FF),
      Color(0xFFEDE9FE),
      Color(0xFFFAF5FF),
    ],
    stops: [0, 0.5, 1],
  );

  static const ctaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFA78BFA), Color(0xFF7C3AED), Color(0xFF6D28D9)],
  );

  static List<BoxShadow> get ctaShadow => const [
        BoxShadow(color: Color(0x557C3AED), blurRadius: 24, offset: Offset(0, 10)),
      ];
}
