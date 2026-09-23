import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/feature_flags.dart';
import '../../core/i18n/i18n.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

/// views/SplashScreen.vue
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  late final _float = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2700))..forward();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final reduced = MediaQuery.of(context).disableAnimations;
      await Future<void>.delayed(Duration(milliseconds: reduced ? 400 : 1000));
      if (!mounted) return;
      setState(() => _loading = true);
      await _goNext();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _float.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    final router = GoRouter.of(context);
    if (Prefs.instance.getString(Keys.onboardingSeen) != null) {
      await navigateDefaultForSession(router, ref);
      return;
    }
    final content = await fetchSiteContent('onboarding');
    if (content != null && '$content'.isNotEmpty) {
      try {
        final parsed = jsonDecode('$content');
        if (parsed is Map && parsed['enabled'] == false) {
          await navigateDefaultForSession(router, ref);
          return;
        }
      } catch (_) {}
    }
    router.go('/onboarding');
  }

  Animation<double> _interval(double startMs, double durMs) => CurvedAnimation(
        parent: _intro,
        curve: Interval(startMs / 2700, ((startMs + durMs) / 2700).clamp(0, 1), curve: Curves.ease),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final size = MediaQuery.sizeOf(context);
    final page = Scaffold(
      backgroundColor: c.bgPrimary,
      body: AnimatedBuilder(
        animation: Listenable.merge([_float, _intro]),
        builder: (context, _) {
          double wave(double delaySec) {
            final phase = ((_float.value * 6 - delaySec) % 6) / 6;
            return (1 - cosTurn(phase)) / 2;
          }

          final w1 = wave(0), w2 = wave(2), w3 = wave(1);
          return Stack(
            children: [
              _orb(right: -80, top: -80 - 20 * w1, size: 300, scale: 1 + 0.05 * w1, color: const Color(0x4D6C63FF)),
              _orb(left: -60, bottom: -60 + 20 * w2, size: 250, scale: 1 + 0.05 * w2, color: const Color(0x40FF6584)),
              _orb(
                left: size.width / 2 - 90,
                top: size.height / 2 - 90 - 18 * w3,
                size: 180,
                scale: 1 + 0.1 * w3,
                color: const Color(0x2600D4FF),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _interval(200, 800),
                      child: Image.asset(light ? 'assets/images/logo-light.png' : 'assets/images/logo.png', height: 120),
                    ),
                    const SizedBox(height: 16),
                    FadeTransition(
                      opacity: _interval(500, 800),
                      child: Text(t('splash.tagline'), style: TextStyle(color: c.textSecondary, fontSize: 15)),
                    ),
                    const SizedBox(height: 48),
                    FadeTransition(
                      opacity: _interval(800, 500),
                      child: Container(
                        width: 120,
                        height: 3,
                        decoration: BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(4)),
                        alignment: AlignmentDirectional.centerStart,
                        child: FractionallySizedBox(
                          widthFactor: _interval(900, 1800).value,
                          child: Container(
                            decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    return PopScope(
      canPop: false,
      child: Stack(children: [page, LoaderOverlay(show: _loading, text: t('splash.loading'))]),
    );
  }

  Widget _orb({double? left, double? right, double? top, double? bottom, required double size, required double scale, required Color color}) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Transform.scale(
        scale: scale,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.decal),
          child: Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ),
      ),
    );
  }
}

double cosTurn(double turns) => math.cos(turns * 2 * math.pi);
