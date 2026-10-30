import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/hubs.dart';
import '../../core/network/network_status.dart';
import '../../shared/banner_strip.dart';
import '../../shared/widgets.dart';
import 'instant_theme.dart';
import 'matching_controller.dart';

/// Searching state for Instant Chat — InstantTheme (violet), no NX-code tips.
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
    HapticFeedback.selectionClick();
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

    Widget wave(double delay) => AnimatedBuilder(
          animation: _radar,
          builder: (_, _) {
            final v = reduced ? 1.0 : (_radar.value - delay) % 1.0;
            final eased = Curves.easeOut.transform(v);
            return Transform.scale(
              scale: reduced ? 1 : 0.55 + 0.45 * eased,
              child: Opacity(
                opacity: reduced ? 0.28 : 0.8 * (1 - eased),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: InstantTheme.violet.withValues(alpha: 0.35), width: 2),
                  ),
                ),
              ),
            );
          },
        );

    Widget chip({required IconData icon, required Color iconColor, required Color bg, required String label}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: InstantTheme.violetSoft),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 17, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: InstantTheme.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    final tips = [
      (t('matching.tip1'), LucideIcons.zap),
      (t('matching.tip2'), LucideIcons.usersRound),
      (t('matching.tip3'), LucideIcons.lightbulb),
    ];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: InstantTheme.mist,
        body: Stack(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(gradient: InstantTheme.pageGradient),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t('matching.title'),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: InstantTheme.ink,
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: _cancelling ? 0.45 : 1,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.85),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: InstantTheme.violetSoft),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: _cancelling ? null : _cancel,
                              child: const SizedBox(
                                width: 42,
                                height: 42,
                                child: Icon(LucideIcons.x, size: 20, color: InstantTheme.violetDeep),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(color: InstantTheme.violetSoft),
                              boxShadow: const [
                                BoxShadow(color: Color(0x227C3AED), blurRadius: 28, offset: Offset(0, 12)),
                              ],
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  width: 148,
                                  height: 148,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Positioned.fill(child: wave(0)),
                                      Positioned.fill(child: wave(1 / 3)),
                                      Positioned.fill(child: wave(2 / 3)),
                                      Container(
                                        width: 84,
                                        height: 84,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: InstantTheme.ctaGradient,
                                          boxShadow: InstantTheme.ctaShadow,
                                        ),
                                        alignment: Alignment.center,
                                        child: reduced
                                            ? const Icon(LucideIcons.zap, size: 32, color: Colors.white)
                                            : Lottie.asset('assets/lottie/chat.json', width: 52, height: 52, frameRate: FrameRate.max),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FadeTransition(
                                      opacity: reduced
                                          ? const AlwaysStoppedAnimation(1)
                                          : TweenSequence([
                                              TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.4), weight: 1),
                                              TweenSequenceItem(tween: Tween(begin: 0.4, end: 1.0), weight: 1),
                                            ]).animate(CurvedAnimation(parent: _live, curve: Curves.easeInOut)),
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: InstantTheme.violet,
                                          boxShadow: [BoxShadow(color: Color(0x557C3AED), spreadRadius: 4)],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${t('matching.searching')}$_dots',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                        color: InstantTheme.violet,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  t('matching.searchingFor'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    height: 1.35,
                                    color: InstantTheme.ink,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    chip(
                                      icon: LucideIcons.shieldCheck,
                                      iconColor: InstantTheme.violet,
                                      bg: InstantTheme.violetSoft,
                                      label: t('matching.secureSearch'),
                                    ),
                                    const SizedBox(width: 10),
                                    chip(
                                      icon: filterIcon,
                                      iconColor: InstantTheme.violetDeep,
                                      bg: InstantTheme.violetSoft,
                                      label: filterLabel,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: InstantTheme.violetSoft),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t('matching.tipsTitle'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: InstantTheme.ink,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                for (final (i, tip) in tips.indexed)
                                  Padding(
                                    padding: EdgeInsets.only(top: i > 0 ? 10 : 0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: InstantTheme.violetSoft,
                                            borderRadius: BorderRadius.circular(11),
                                          ),
                                          child: Icon(tip.$2, size: 16, color: InstantTheme.violet),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(top: 7),
                                            child: Text(
                                              tip.$1,
                                              style: TextStyle(
                                                fontSize: 13,
                                                height: 1.4,
                                                fontWeight: FontWeight.w500,
                                                color: InstantTheme.ink.withValues(alpha: 0.72),
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
                          const SizedBox(height: 12),
                          const BannerStrip(placement: 'matching', padding: EdgeInsets.zero),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + pad.bottom),
                    decoration: BoxDecoration(
                      color: InstantTheme.mist.withValues(alpha: 0.96),
                      border: Border(top: BorderSide(color: InstantTheme.violet.withValues(alpha: 0.12))),
                    ),
                    child: Opacity(
                      opacity: _cancelling ? 0.55 : 1,
                      child: Material(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: InstantTheme.violet.withValues(alpha: 0.18)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _cancelling ? null : _cancel,
                          child: SizedBox(
                            height: 52,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.x, size: 18, color: InstantTheme.violetDeep.withValues(alpha: 0.75)),
                                const SizedBox(width: 8),
                                Text(
                                  t('matching.cancelSearch'),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: InstantTheme.violetDeep.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            LoaderOverlay(show: _cancelling, text: t('matching.cancelling')),
          ],
        ),
      ),
    );
  }
}
