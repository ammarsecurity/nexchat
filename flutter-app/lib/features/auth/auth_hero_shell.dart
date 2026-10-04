import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Visual language shared with [OnboardingScreen]: hero photo + soft wave card.
const kAuthBlue = Color(0xFF0084FF);
const kAuthPurple = Color(0xFF8E54E9);
const kAuthTitle = Color(0xFF0A1931);
const kAuthBody = Color(0xFF7E8A97);

class AuthHeroShell extends StatelessWidget {
  const AuthHeroShell({
    super.key,
    required this.heroAsset,
    required this.child,
    this.heroFraction = 0.34,
    this.onBack,
  });

  final String heroAsset;
  final Widget child;
  /// Portion of screen height reserved for the photo before the wave.
  final double heroFraction;
  /// Optional translucent back control over the hero (e.g. register → login).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final heroH = (size.height * heroFraction).clamp(160.0, 320.0);
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroH + 48,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    heroAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x33000000),
                          Color(0x00000000),
                          Color(0x14000000),
                        ],
                        stops: [0, 0.45, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: heroH - 8,
              left: 0,
              right: 0,
              bottom: 0,
              child: CustomPaint(
                painter: const AuthWaveCardPainter(),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 44, 24, pad.bottom + 12),
                  child: child,
                ),
              ),
            ),
            if (onBack != null)
              Positioned(
                top: pad.top + 8,
                left: rtl ? null : 16,
                right: rtl ? 16 : null,
                child: _AuthBackButton(onTap: onBack!, rtl: rtl),
              ),
          ],
        ),
      ),
    );
  }
}

class _AuthBackButton extends StatelessWidget {
  const _AuthBackButton({required this.onTap, required this.rtl});
  final VoidCallback onTap;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          child: Icon(
            rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
            size: 22,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class AuthWaveCardPainter extends CustomPainter {
  const AuthWaveCardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path()
      ..moveTo(0, 42)
      ..cubicTo(size.width * 0.18, 8, size.width * 0.38, 8, size.width * 0.52, 26)
      ..cubicTo(size.width * 0.72, 48, size.width * 0.88, 40, size.width, 18)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawShadow(path, const Color(0x220A1931), 12, false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Gradient pill CTA matching onboarding.
class AuthPillCta extends StatelessWidget {
  const AuthPillCta({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.showChevron = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return Opacity(
      opacity: enabled || loading ? 1 : 0.45,
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kAuthBlue, kAuthPurple],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(27),
            boxShadow: enabled
                ? const [BoxShadow(color: Color(0x332E86FB), blurRadius: 18, offset: Offset(0, 8))]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(27),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  else
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (showChevron && !loading)
                    Positioned(
                      right: 10,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(LucideIcons.chevronRight, color: Colors.white, size: 20),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthHeroTitle extends StatelessWidget {
  const AuthHeroTitle({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: kAuthTitle,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: kAuthBody,
            height: 1.65,
          ),
        ),
      ],
    );
  }
}
