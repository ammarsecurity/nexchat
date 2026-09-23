import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/feature_flags.dart';
import '../../core/i18n/i18n.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

class _Slide {
  const _Slide(this.title, this.description, [this.imageUrl = '']);
  final String title;
  final String description;
  final String imageUrl;
}

List<_Slide> _localizedDefaults() => [
      _Slide(t('onboarding.slide1Title'), t('onboarding.slide1Desc')),
      _Slide(t('onboarding.slide2Title'), t('onboarding.slide2Desc')),
      _Slide(t('onboarding.slide3Title'), t('onboarding.slide3Desc')),
    ];

/// views/OnboardingView.vue
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  List<_Slide> _slides = const [];
  int _index = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var slides = _localizedDefaults();
    final content = await fetchSiteContent('onboarding');
    if (content != null && '$content'.isNotEmpty) {
      try {
        final parsed = jsonDecode('$content');
        if (parsed is Map && parsed['enabled'] == false) {
          if (mounted) setState(() => _loading = false);
          _finish();
          return;
        }
        final list = parsed is Map ? parsed['slides'] : null;
        if (list is List && list.isNotEmpty) {
          final sorted = list.whereType<Map>().toList()
            ..sort((a, b) => (num.tryParse('${a['order']}') ?? 0).compareTo(num.tryParse('${b['order']}') ?? 0));
          final parsedSlides = sorted
              .map((m) => _Slide('${m['title'] ?? ''}', '${m['description'] ?? ''}', '${m['imageUrl'] ?? ''}'))
              .toList();
          if (parsedSlides.isNotEmpty) slides = parsedSlides;
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _slides = slides;
        _loading = false;
      });
    }
  }

  void _finish() {
    Prefs.instance.setString(Keys.onboardingSeen, '1');
    if (!mounted) return;
    navigateDefaultForSession(GoRouter.of(context), ref);
  }

  bool get _isLast => _index >= _slides.length - 1;

  @override
  Widget build(BuildContext context) => PopScope(canPop: false, child: _page(context));

  Widget _page(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final pad = MediaQuery.paddingOf(context);
    if (_loading) {
      return Scaffold(
        backgroundColor: c.bgPrimary,
        body: PageLoader(text: t('common.loading')),
      );
    }
    final slide = _slides[_index];
    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: Padding(
        padding: EdgeInsets.fromLTRB(16, pad.top + 16, 16, pad.bottom + 24),
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _finish,
                child: Text(t('onboarding.skip'), style: TextStyle(color: c.textMuted, fontSize: 15)),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v > 200 && !_isLast) setState(() => _index++);
                  if (v < -200 && _index > 0) setState(() => _index--);
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: ConstrainedBox(
                    key: ValueKey(_index),
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (slide.imageUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 200,
                              height: 200,
                              color: c.bgCard,
                              child: CachedNetworkImage(imageUrl: slide.imageUrl, fit: BoxFit.cover),
                            ),
                          )
                        else
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(color: c.bgCard, borderRadius: BorderRadius.circular(24)),
                            alignment: Alignment.center,
                            child: Image.asset(light ? 'assets/images/logo-light.png' : 'assets/images/logo.png', height: 80),
                          ),
                        const SizedBox(height: 24),
                        Text(slide.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.textPrimary)),
                        const SizedBox(height: 12),
                        Text(slide.description,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: c.textSecondary, height: 1.6)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _index = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: i == _index ? c.primary : c.border),
                      ),
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Row(
                children: [
                  Opacity(
                    opacity: _index == 0 ? 0.4 : 1,
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Material(
                        color: c.bgCard,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _index == 0 ? null : () => setState(() => _index--),
                          child: Icon(LucideIcons.chevronRight, color: c.textSecondary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: Material(
                        color: c.primary,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _isLast ? _finish() : setState(() => _index++),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_isLast ? t('onboarding.start') : t('onboarding.next'),
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              const Icon(LucideIcons.chevronLeft, size: 20, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
