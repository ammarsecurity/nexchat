import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/hubs.dart';
import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/banner_strip.dart';
import '../../shared/widgets.dart';
import 'matching_controller.dart';

/// views/MatchingView.vue
class MatchingScreen extends ConsumerStatefulWidget {
  const MatchingScreen({super.key});

  @override
  ConsumerState<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends ConsumerState<MatchingScreen> with TickerProviderStateMixin {
  late final MatchingController _matching = ref.read(matchingProvider.notifier);
  late final AnimationController _radar = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  late final AnimationController _live = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
  Timer? _dotsTimer;
  String _dots = '.';
  bool _cancelling = false;
  bool _cancelledProgrammatically = false;

  @override
  void initState() {
    super.initState();
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _dots = _dots.length >= 3 ? '.' : '$_dots.');
    });
    if (_matching.consumeResumeSearchAfterNav() && NetworkStatus.online.value) {
      Hubs.matching.ensureConnected().then((_) => Hubs.matching.invoke('StartSearching', [_matching.current.genderFilter])).catchError((_) {
        _matching.setIdle();
        if (mounted) {
          showToast(context, t('home.connectionError'), error: true);
          context.go('/home');
        }
        return null;
      });
    }
  }

  @override
  void dispose() {
    _dotsTimer?.cancel();
    _radar.dispose();
    _live.dispose();
    if (!_matching.consumeSkipNextMatchingUnmountCancel() && !_cancelledProgrammatically) {
      Hubs.matching.ensureConnected().then((_) => Hubs.matching.invoke('CancelSearching')).catchError((_) => null);
    }
    super.dispose();
  }

  Future<void> _cancel() async {
    _cancelledProgrammatically = true;
    setState(() => _cancelling = true);
    try {
      if (NetworkStatus.online.value) {
        await Hubs.matching.ensureConnected();
        await Hubs.matching.invoke('CancelSearching');
      }
      _matching.setIdle();
      if (mounted) context.go('/home');
    } catch (_) {
      _matching.setIdle();
      if (mounted) context.go('/home');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(networkProvider, (prev, next) {
      if (prev == true && next == false && !_cancelledProgrammatically) {
        _cancelledProgrammatically = true;
        _matching.setIdle();
        if (mounted) context.go('/home');
      }
    });
    final c = context.colors;
    final pad = MediaQuery.paddingOf(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final gender = ref.watch(matchingProvider.select((s) => s.genderFilter));
    final filterLabel = switch (gender) {
      'male' => t('matching.filterMale'),
      'female' => t('matching.filterFemale'),
      _ => t('matching.filterAll'),
    };
    final filterIcon = switch (gender) {
      'male' => LucideIcons.circleUser,
      'female' => LucideIcons.usersRound,
      _ => LucideIcons.globe,
    };
    final (Color accent, Color accentBg) = gender == 'female' ? (const Color(0xFFDB2777), const Color(0x1ADB2777)) : (c.primary, c.primarySoft);

    Widget wave(double delay) => AnimatedBuilder(
          animation: _radar,
          builder: (_, _) {
            final v = reduced ? 1.0 : (_radar.value - delay) % 1.0;
            final eased = Curves.easeOut.transform(v);
            return Transform.scale(
              scale: reduced ? 1 : 0.55 + 0.45 * eased,
              child: Opacity(
                opacity: reduced ? 0.35 : 0.85 * (1 - eased),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x472563EB), width: 2)),
                ),
              ),
            );
          },
        );

    Widget meta(Widget icon, Color bg, String text) => Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(color: c.bgElevated, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.border)),
            child: Column(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: icon,
              ),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.35, color: c.textSecondary)),
            ]),
          ),
        );

    final cardShadow = [BoxShadow(color: c.shadow, blurRadius: 6, offset: const Offset(0, 1))];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: c.bgPrimary,
        body: Stack(children: [
          Column(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, pad.top + 10, 16, 12),
              child: Row(children: [
                Expanded(child: Text(t('matching.title'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c.textPrimary))),
                Opacity(
                  opacity: _cancelling ? 0.5 : 1,
                  child: GlassIconButton(icon: LucideIcons.x, color: c.textSecondary, onTap: _cancelling ? null : _cancel),
                ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.fromLTRB(18, 28, 18, 18),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: c.border),
                      boxShadow: cardShadow,
                    ),
                    child: Column(children: [
                      SizedBox(
                        width: 132,
                        height: 132,
                        child: Stack(alignment: Alignment.center, children: [
                          Positioned.fill(child: wave(0)),
                          Positioned.fill(child: wave(1 / 3)),
                          Positioned.fill(child: wave(2 / 3)),
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2563EB), Color(0xFF60A5FA)]),
                              boxShadow: [BoxShadow(color: Color(0x522563EB), blurRadius: 28, offset: Offset(0, 10))],
                            ),
                            alignment: Alignment.center,
                            child: reduced
                                ? const Icon(LucideIcons.search, size: 28, color: Colors.white)
                                : Lottie.asset('assets/lottie/chat.json', width: 44, height: 44),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 22),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        FadeTransition(
                          opacity: reduced
                              ? const AlwaysStoppedAnimation(1)
                              : TweenSequence([
                                  TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.45), weight: 1),
                                  TweenSequenceItem(tween: Tween(begin: 0.45, end: 1.0), weight: 1),
                                ]).animate(CurvedAnimation(parent: _live, curve: Curves.easeInOut)),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF22C55E),
                              boxShadow: [BoxShadow(color: Color(0x3822C55E), spreadRadius: 4)],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${t('matching.searching')}$_dots',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: c.primary)),
                      ]),
                      const SizedBox(height: 8),
                      Text(t('matching.searchingFor'),
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.4, color: c.textPrimary)),
                      const SizedBox(height: 20),
                      IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          meta(const Icon(LucideIcons.shieldCheck, size: 18, color: Color(0xFF16A34A)), const Color(0x1F22C55E), t('matching.secureSearch')),
                          const SizedBox(width: 10),
                          meta(Icon(filterIcon, size: 18, color: accent), accentBg, filterLabel),
                        ]),
                      ),
                    ]),
                  ),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: c.border),
                      boxShadow: cardShadow,
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('matching.tipsTitle'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c.textPrimary)),
                      const SizedBox(height: 10),
                      for (final (i, tip) in const [('tip1', LucideIcons.sparkles), ('tip2', LucideIcons.usersRound), ('tip3', LucideIcons.lightbulb)].indexed)
                        Padding(
                          padding: EdgeInsets.only(top: i > 0 ? 8 : 0),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(10)),
                              child: Icon(tip.$2, size: 16, color: c.primary),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(t('matching.${tip.$1}'), style: TextStyle(fontSize: 13, height: 1.45, color: c.textSecondary)),
                              ),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                  const BannerStrip(placement: 'matching', padding: EdgeInsets.zero),
                ]),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + pad.bottom),
              decoration: BoxDecoration(
                color: c.bgPrimary,
                border: Border(top: BorderSide(color: c.border)),
                boxShadow: const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 20, offset: Offset(0, -4))],
              ),
              child: Opacity(
                opacity: _cancelling ? 0.55 : 1,
                child: Material(
                  color: c.bgCard,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    highlightColor: const Color(0x0FEF4444),
                    onTap: _cancelling ? null : _cancel,
                    child: SizedBox(
                      height: 52,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(LucideIcons.x, size: 18, color: c.textSecondary),
                        const SizedBox(width: 8),
                        Text(t('matching.cancelSearch'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textSecondary)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
          LoaderOverlay(show: _cancelling, text: t('matching.cancelling')),
        ]),
      ),
    );
  }
}
