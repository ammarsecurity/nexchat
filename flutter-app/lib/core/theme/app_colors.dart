import 'package:flutter/material.dart';

/// Design tokens mirrored from mobile-app/src/assets/chatloop-theme.css.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgCard,
    required this.bgCardHover,
    required this.bgElevated,
    required this.primary,
    required this.primaryHover,
    required this.primarySoft,
    required this.primaryMuted,
    required this.danger,
    required this.success,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.msgTheirsBg,
    required this.msgTheirsColor,
    required this.systemMsgBg,
    required this.shadow,
  });

  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgCard;
  final Color bgCardHover;
  final Color bgElevated;
  final Color primary;
  final Color primaryHover;
  final Color primarySoft;
  final Color primaryMuted;
  final Color danger;
  final Color success;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color msgTheirsBg;
  final Color msgTheirsColor;
  final Color systemMsgBg;
  final Color shadow;

  static const msgMineGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF60A5FA), Color(0xFF3B82F6)],
  );

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C75FF), Color(0xFF60A5FA), Color(0xFF5B54E8)],
  );

  static const dark = AppColors(
    bgPrimary: Color(0xFF0F172A),
    bgSecondary: Color(0xFF1E293B),
    bgCard: Color(0xFF1E293B),
    bgCardHover: Color(0xFF334155),
    bgElevated: Color(0xFF334155),
    primary: Color(0xFF60A5FA),
    primaryHover: Color(0xFF3B82F6),
    primarySoft: Color(0x2660A5FA),
    primaryMuted: Color(0x3860A5FA),
    danger: Color(0xFFF87171),
    success: Color(0xFF34D399),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF64748B),
    border: Color(0x14FFFFFF),
    msgTheirsBg: Color(0x14FFFFFF),
    msgTheirsColor: Color(0xFFF8FAFC),
    systemMsgBg: Color(0x0DFFFFFF),
    shadow: Color(0x33000000),
  );

  static const light = AppColors(
    bgPrimary: Color(0xFFF4F7FE),
    bgSecondary: Color(0xFFEBF2FF),
    bgCard: Color(0xFFFFFFFF),
    bgCardHover: Color(0xFFF0F5FF),
    bgElevated: Color(0xFFF8FAFF),
    primary: Color(0xFF3B82F6),
    primaryHover: Color(0xFF2563EB),
    primarySoft: Color(0x1F3B82F6),
    primaryMuted: Color(0x2E3B82F6),
    danger: Color(0xFFEF4444),
    success: Color(0xFF22C55E),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF94A3B8),
    border: Color(0x0F0F172A),
    msgTheirsBg: Color(0xFFFFFFFF),
    msgTheirsColor: Color(0xFF0F172A),
    systemMsgBg: Color(0x0F3B82F6),
    shadow: Color(0x143B82F6),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bgPrimary: l(bgPrimary, other.bgPrimary),
      bgSecondary: l(bgSecondary, other.bgSecondary),
      bgCard: l(bgCard, other.bgCard),
      bgCardHover: l(bgCardHover, other.bgCardHover),
      bgElevated: l(bgElevated, other.bgElevated),
      primary: l(primary, other.primary),
      primaryHover: l(primaryHover, other.primaryHover),
      primarySoft: l(primarySoft, other.primarySoft),
      primaryMuted: l(primaryMuted, other.primaryMuted),
      danger: l(danger, other.danger),
      success: l(success, other.success),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      border: l(border, other.border),
      msgTheirsBg: l(msgTheirsBg, other.msgTheirsBg),
      msgTheirsColor: l(msgTheirsColor, other.msgTheirsColor),
      systemMsgBg: l(systemMsgBg, other.systemMsgBg),
      shadow: l(shadow, other.shadow),
    );
  }
}

class AppRadius {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
