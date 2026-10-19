import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Dark cinematic action sheet for short-films menus.
Future<T?> showDramaWaveSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: DramaWave.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: DramaWave.hairline,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Flexible(child: builder(ctx)),
          ],
        ),
      ),
    ),
  );
}

class DramaWaveSheetAction extends StatelessWidget {
  const DramaWaveSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? DramaWave.hot : DramaWave.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: danger ? DramaWave.hot.withValues(alpha: 0.12) : DramaWave.elevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: danger ? DramaWave.hot.withValues(alpha: 0.35) : DramaWave.hairline,
                  ),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? LucideIcons.chevronLeft
                    : LucideIcons.chevronRight,
                size: 16,
                color: DramaWave.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty / zero-state for short-films surfaces (gold accent, not app primary blue).
class DramaWaveEmpty extends StatelessWidget {
  const DramaWaveEmpty({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final parts = text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final title = parts.isNotEmpty ? parts.first : text;
    final subtitle = parts.length > 1 ? parts.sublist(1).join('\n') : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DramaWave.goldSoft,
                border: Border.all(color: DramaWave.gold.withValues(alpha: 0.35)),
                boxShadow: [
                  BoxShadow(
                    color: DramaWave.gold.withValues(alpha: 0.12),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(icon, size: 34, color: DramaWave.gold),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: DramaWave.title(size: 17),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: DramaWave.body(size: 13, color: DramaWave.muted),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onAction,
                  borderRadius: BorderRadius.circular(24),
                  child: Ink(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [DramaWave.gold, DramaWave.goldDeep]),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// DramaWave-inspired palette for short-films surfaces (always dark / cinematic).
abstract final class DramaWave {
  static const bg = Color(0xFF0A0809);
  static const surface = Color(0xFF161214);
  static const elevated = Color(0xFF1E191B);
  static const hairline = Color(0x22FFFFFF);
  static const ink = Color(0xFFF8F5F2);
  static const muted = Color(0xFF9A8E86);
  static const soft = Color(0xFFC9B8A8);
  static const gold = Color(0xFFE8B923);
  static const goldSoft = Color(0x33E8B923);
  static const goldDeep = Color(0xFFC9921A);
  static const hot = Color(0xFFFF4D6A);
  static const rank1 = Color(0xFFE8B923);
  static const rank2 = Color(0xFFC0C7D1);
  static const rank3 = Color(0xFFC97A45);
  static const scrub = Color(0xFFE8B923);

  static const heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x66000000),
      Color(0x00000000),
      Color(0xCC0A0809),
      Color(0xFF0A0809),
    ],
    stops: [0, 0.28, 0.72, 1],
  );

  static const cardFade = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xE6000000), Color(0x00000000)],
    stops: [0, 0.55],
  );

  static Color rankColor(int rank) {
    if (rank == 1) return rank1;
    if (rank == 2) return rank2;
    if (rank == 3) return rank3;
    return muted;
  }

  static TextStyle title({double size = 16, FontWeight weight = FontWeight.w800}) =>
      TextStyle(color: ink, fontSize: size, fontWeight: weight, height: 1.25);

  static TextStyle body({double size = 13, Color? color}) =>
      TextStyle(color: color ?? muted, fontSize: size, fontWeight: FontWeight.w500, height: 1.45);
}
