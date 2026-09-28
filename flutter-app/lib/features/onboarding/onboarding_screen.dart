import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/feature_flags.dart';
import '../../core/i18n/i18n.dart';
import '../../core/storage/prefs.dart';

const _kBlue = Color(0xFF0084FF);
const _kPurple = Color(0xFF8E54E9);
const _kTitle = Color(0xFF0A1931);
const _kBody = Color(0xFF7E8A97);

class _Slide {
  const _Slide(this.asset, this.titleKey, this.descKey);
  final String asset;
  final String titleKey;
  final String descKey;
}

/// Onboarding matching product mockups: hero image + soft wave + pill CTA.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final PageController _page;
  int _index = 0;
  bool _ready = false;

  static const _slides = [
    _Slide('assets/images/1.png', 'onboarding.slide1Title', 'onboarding.slide1Desc'),
    _Slide('assets/images/2.png', 'onboarding.slide2Title', 'onboarding.slide2Desc'),
    _Slide('assets/images/3.png', 'onboarding.slide3Title', 'onboarding.slide3Desc'),
  ];

  @override
  void initState() {
    super.initState();
    _page = PageController();
    _bootstrap();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Admin kill-switch only — never override local images/copy (breaks the designed UI).
    final content = await fetchSiteContent('onboarding');
    if (content != null && '$content'.isNotEmpty) {
      try {
        final parsed = jsonDecode('$content');
        if (parsed is Map && parsed['enabled'] == false) {
          if (mounted) {
            setState(() => _ready = true);
            _finish();
          }
          return;
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _ready = true);
  }

  void _finish() {
    Prefs.instance.setString(Keys.onboardingSeen, '1');
    if (!mounted) return;
    navigateDefaultForSession(GoRouter.of(context), ref);
  }

  bool get _isLast => _index >= _slides.length - 1;

  void _goTo(int i) {
    if (i < 0 || i >= _slides.length) return;
    _page.animateToPage(i, duration: const Duration(milliseconds: 340), curve: Curves.easeOutCubic);
  }

  void _next() => _isLast ? _finish() : _goTo(_index + 1);

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    return PopScope(
      canPop: false,
      child: !_ready
          ? const Scaffold(backgroundColor: Colors.white, body: SizedBox.expand())
          : _OnboardingBody(
              page: _page,
              index: _index,
              slides: _slides,
              isLast: _isLast,
              onPageChanged: (i) => setState(() => _index = i),
              onDotTap: _goTo,
              onNext: _next,
            ),
    );
  }
}

class _OnboardingBody extends StatelessWidget {
  const _OnboardingBody({
    required this.page,
    required this.index,
    required this.slides,
    required this.isLast,
    required this.onPageChanged,
    required this.onDotTap,
    required this.onNext,
  });

  final PageController page;
  final int index;
  final List<_Slide> slides;
  final bool isLast;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onDotTap;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final h = MediaQuery.sizeOf(context).height;
    final cardH = (h * 0.38).clamp(290.0, 360.0);
    final slide = slides[index];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: page,
                itemCount: slides.length,
                onPageChanged: onPageChanged,
                itemBuilder: (_, i) => Image.asset(
                  slides[i].asset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: cardH,
              child: CustomPaint(
                painter: const _WaveCardPainter(),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(28, 52, 28, pad.bottom + 8),
                  child: Column(
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          child: Column(
                            key: ValueKey(index),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                t(slide.titleKey),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: _kTitle,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                t(slide.descKey),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: _kBody,
                                  height: 1.65,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < slides.length; i++)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onDotTap(i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: i == index ? 9 : 7,
                                  height: i == index ? 9 : 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i == index ? _kBlue : const Color(0xFFD0D7E2),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _PillCta(
                        label: isLast ? t('onboarding.start') : t('onboarding.next'),
                        onTap: onNext,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillCta extends StatelessWidget {
  const _PillCta({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kBlue, _kPurple],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(27),
          boxShadow: const [
            BoxShadow(color: Color(0x332E86FB), blurRadius: 18, offset: Offset(0, 8)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(27),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
    );
  }
}

/// White bottom card with soft asymmetrical wave (matches mockups).
class _WaveCardPainter extends CustomPainter {
  const _WaveCardPainter();

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

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
