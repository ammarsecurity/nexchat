import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/layout.dart';
import '../../shared/widgets.dart';
import '../settings/birth_date_sheet.dart';
import '../settings/profile_photos_sheet.dart';
import 'discover_controller.dart';
import 'discover_filters_sheet.dart';
import 'discover_match_dialog.dart';
import 'discover_matches_sheet.dart';
import 'discover_theme.dart';

/// Tinder-style Discover: card stack, like/pass, mutual match dialog.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  Offset _drag = Offset.zero;
  double _angle = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoverProvider.notifier).refresh();
    });
  }

  Future<void> _act({required bool like}) async {
    if (_busy) return;
    final ctrl = ref.read(discoverProvider.notifier);
    if (ref.read(discoverProvider).top == null) return;
    setState(() {
      _busy = true;
      _drag = Offset(like ? 420 : -420, 40);
      _angle = like ? 0.28 : -0.28;
    });
    await Future<void>.delayed(const Duration(milliseconds: 180));
    try {
      final res = await ctrl.swipe(like: like);
      if (!mounted) return;
      if (res != null && res.b('matched')) {
        await showDiscoverMatchDialog(context, res);
      }
    } catch (_) {
      if (mounted) showToast(context, t('common.error'), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _drag = Offset.zero;
          _angle = 0;
        });
      }
    }
  }

  Future<void> _onPanEnd(DragEndDetails d) async {
    final dx = _drag.dx;
    if (dx.abs() > 110) {
      await _act(like: dx > 0);
      return;
    }
    setState(() {
      _drag = Offset.zero;
      _angle = 0;
    });
  }

  Future<void> _setBirthDate() async {
    if (!mounted) return;
    final saved = await showBirthDateSheet(context, accent: DiscoverTheme.red);
    if (saved == null || !mounted) return;
    // Hide birth-date CTA immediately, then sync with server.
    ref.read(discoverProvider.notifier).markBirthDateComplete();
    await ref.read(discoverProvider.notifier).refresh();
  }

  Future<void> _reportCard(Json card) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return AlertDialog(
          backgroundColor: c.bgCard,
          title: Text(t('randomChat.report')),
          content: TextField(
            controller: reason,
            maxLines: 3,
            decoration: InputDecoration(hintText: t('randomChat.reportPlaceholder')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('randomChat.report'))),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await Api.post('/discover/report', {'targetUserId': card.str('id'), 'reason': reason.text.trim()});
      if (mounted) showToast(context, t('discover.reported'), success: true);
      try {
        await ref.read(discoverProvider.notifier).swipe(like: false);
      } catch (_) {
        ref.read(discoverProvider.notifier).removeTopLocally();
      }
    } catch (_) {
      if (mounted) showToast(context, t('common.error'), error: true);
    } finally {
      reason.dispose();
    }
  }

  Future<void> _blockCard(Json card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('randomChat.blockConfirmTitle')),
        content: Text(t('discover.blockConfirmDesc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.colors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('randomChat.blockConfirm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // Pass first so the pair is recorded; then block (feed also excludes blocks).
      try {
        await ref.read(discoverProvider.notifier).swipe(like: false);
      } catch (_) {
        ref.read(discoverProvider.notifier).removeTopLocally();
      }
      await Api.post('/blocks/${card.str('id')}');
      if (mounted) showToast(context, t('discover.blocked'), success: true);
    } catch (_) {
      if (mounted) showToast(context, t('randomChat.blockError'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final state = ref.watch(discoverProvider);
    final bottomPad = MediaQuery.paddingOf(context).bottom + kTabBarContentHeight + 12;
    final gating = state.eligibilityLoaded && !state.eligibility.canSwipe;

    if (gating) {
      return Scaffold(
        backgroundColor: DiscoverTheme.redDeep,
        body: _GateHero(
          eligibility: state.eligibility,
          bottomPad: bottomPad,
          onAddPhotos: () async {
            final saved = await showProfilePhotosSheet(context, accent: DiscoverTheme.red);
            if (saved) await ref.read(discoverProvider.notifier).refresh();
          },
          onAddBirthDate: _setBirthDate,
        ),
      );
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: DiscoverTheme.pageGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _DiscoverHeader(),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(10, 0, 10, bottomPad),
                  child: _body(context, state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DiscoverState state) {
    if (state.loading && !state.eligibilityLoaded) {
      return const Center(child: CircularProgressIndicator(color: DiscoverTheme.red));
    }
    if (state.error.isNotEmpty && state.deck.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t('common.error'), style: TextStyle(color: DiscoverTheme.redDeep.withValues(alpha: 0.7))),
            const SizedBox(height: 16),
            _DiscoverRetryButton(onPressed: () => ref.read(discoverProvider.notifier).refresh()),
          ]),
        ),
      );
    }
    if (state.deck.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: DiscoverTheme.ctaGradient,
                boxShadow: DiscoverTheme.likeShadow,
              ),
              child: const Icon(LucideIcons.heartHandshake, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(t('discover.empty'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: DiscoverTheme.ink, height: 1.3)),
            const SizedBox(height: 8),
            Text(t('discover.emptyHint'), textAlign: TextAlign.center, style: TextStyle(color: DiscoverTheme.redDeep.withValues(alpha: 0.55), fontSize: 14, height: 1.4)),
            const SizedBox(height: 22),
            _DiscoverRetryButton(onPressed: () => ref.read(discoverProvider.notifier).refresh()),
          ]),
        ),
      );
    }

    final top = state.deck.first;
    final behind = state.deck.length > 1 ? state.deck[1] : null;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            // Fill available height; cap width so the card stays portrait and edge-to-edge.
            const aspect = 0.72; // width / height
            var h = box.maxHeight;
            var w = h * aspect;
            if (w > box.maxWidth) {
              w = box.maxWidth;
              h = w / aspect;
            }
            return Center(
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (behind != null)
                      Positioned.fill(
                        child: Transform.scale(
                          scale: 0.96,
                          child: Opacity(
                            opacity: 0.7,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: _CardFace(card: behind),
                            ),
                          ),
                        ),
                      ),
                    GestureDetector(
                      onPanUpdate: _busy
                          ? null
                          : (d) => setState(() {
                                _drag += d.delta;
                                _angle = (_drag.dx / 320).clamp(-0.35, 0.35);
                              }),
                      onPanEnd: _busy ? null : _onPanEnd,
                      child: AnimatedContainer(
                        duration: _busy ? const Duration(milliseconds: 180) : Duration.zero,
                        transform: Matrix4.translationValues(_drag.dx, _drag.dy, 0)..rotateZ(_angle),
                        transformAlignment: Alignment.center,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _CardFace(
                              card: top,
                              onReport: () => _reportCard(top),
                              onBlock: () => _blockCard(top),
                            ),
                            Positioned(
                              top: 36,
                              left: 28,
                              child: Opacity(
                                opacity: (-_drag.dx / 120).clamp(0.0, 1.0),
                                child: _Stamp(label: t('discover.pass'), color: DiscoverTheme.slate),
                              ),
                            ),
                            Positioned(
                              top: 36,
                              right: 28,
                              child: Opacity(
                                opacity: (_drag.dx / 120).clamp(0.0, 1.0),
                                child: _Stamp(label: t('discover.like'), color: DiscoverTheme.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        _DiscoverActionBar(
          busy: _busy,
          canUndo: state.canUndo,
          onPass: () => _act(like: false),
          onLike: () => _act(like: true),
          onUndo: () async {
            setState(() => _busy = true);
            try {
              await ref.read(discoverProvider.notifier).undo();
            } catch (_) {
              if (mounted) showToast(context, t('common.error'), error: true);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        ),
        const SizedBox(height: 4),
      ],
    );
  }

}

class _DiscoverRetryButton extends StatelessWidget {
  const _DiscoverRetryButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: DiscoverTheme.ctaGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: DiscoverTheme.likeShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              HapticFeedback.selectionClick();
              onPressed();
            },
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.refreshCw, size: 18, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    t('common.retry'),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
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

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap, this.filled = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DiscoverTheme.redSoft,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 20, color: DiscoverTheme.red, fill: filled ? 1 : 0),
        ),
      ),
    );
  }
}

class _DiscoverHeader extends StatelessWidget {
  const _DiscoverHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t('discover.title'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: DiscoverTheme.ink,
                    height: 1.15,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              _HeaderIconButton(
                icon: LucideIcons.slidersHorizontal,
                onTap: () => showDiscoverFiltersSheet(context),
              ),
              const SizedBox(width: 8),
              _HeaderIconButton(
                icon: LucideIcons.heart,
                filled: true,
                onTap: () => showDiscoverMatchesSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t('discover.policyShort'),
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: DiscoverTheme.redDeep.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed Discover onboarding gate — photo background + glass CTAs.
class _GateHero extends StatelessWidget {
  const _GateHero({
    required this.eligibility,
    required this.bottomPad,
    required this.onAddPhotos,
    required this.onAddBirthDate,
  });

  final DiscoverEligibility eligibility;
  final double bottomPad;
  final Future<void> Function() onAddPhotos;
  final Future<void> Function() onAddBirthDate;

  /// Same visual language as onboarding heroes (lifestyle + soft glow), not the same slide.
  static const _bgAsset = 'assets/images/1.png';

  @override
  Widget build(BuildContext context) {
    final needPhoto = !eligibility.hasAvatar;
    final needBirth = !eligibility.hasBirthDate || !eligibility.ageOk;
    final top = MediaQuery.paddingOf(context).top;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _bgAsset,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.15),
          errorBuilder: (_, _, _) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFBE123C), Color(0xFF9F1239), Color(0xFF4C0519)],
              ),
            ),
          ),
        ),
        const DecoratedBox(decoration: BoxDecoration(gradient: DiscoverTheme.heroGradient)),
        Positioned(
          top: top + 12,
          left: 20,
          right: 20,
          child: Text(
            t('discover.title'),
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: bottomPad + 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t('discover.gateTitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.3),
              ),
              const SizedBox(height: 10),
              Text(
                needBirth && !needPhoto
                    ? t('discover.gateBirthOnly')
                    : needPhoto && !needBirth
                        ? t('discover.gatePhotoOnly')
                        : t('discover.gateBody'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14.5, height: 1.45),
              ),
              const SizedBox(height: 8),
              Text(
                t('discover.policy'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.58), fontSize: 11.5, height: 1.35),
              ),
              const SizedBox(height: 22),
              if (needPhoto) ...[
                _GatePrimaryButton(
                  label: t('discover.addPhoto'),
                  icon: LucideIcons.camera,
                  onPressed: onAddPhotos,
                ),
                if (needBirth) const SizedBox(height: 12),
              ],
              if (needBirth)
                _GateSecondaryButton(
                  label: t('discover.addBirthDate'),
                  icon: LucideIcons.calendar,
                  onPressed: onAddBirthDate,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GatePrimaryButton extends StatelessWidget {
  const _GatePrimaryButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: DiscoverTheme.ctaGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x66E11D48), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onPressed(),
          child: SizedBox(
            height: 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: 10),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GateSecondaryButton extends StatelessWidget {
  const _GateSecondaryButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onPressed(),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: DiscoverTheme.redHot.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: label == t('discover.like') ? -0.22 : 0.22,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          border: Border.all(color: color, width: 3.5),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 1.4),
        ),
      ),
    );
  }
}

/// Clean action dock — equal rhythm, no Material ink boxes.
class _DiscoverActionBar extends StatelessWidget {
  const _DiscoverActionBar({
    required this.busy,
    required this.canUndo,
    required this.onPass,
    required this.onLike,
    required this.onUndo,
  });

  final bool busy;
  final bool canUndo;
  final VoidCallback onPass;
  final VoidCallback onLike;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
          boxShadow: const [
            BoxShadow(color: Color(0x14E11D48), blurRadius: 20, offset: Offset(0, 8)),
            BoxShadow(color: Color(0x0A0F172A), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DockButton(
              kind: _DockKind.pass,
              enabled: !busy,
              onTap: onPass,
            ),
            const SizedBox(width: 14),
            _DockButton(
              kind: _DockKind.undo,
              enabled: !busy && canUndo,
              onTap: onUndo,
            ),
            const SizedBox(width: 14),
            _DockButton(
              kind: _DockKind.like,
              enabled: !busy,
              onTap: onLike,
            ),
          ],
        ),
      ),
    );
  }
}

enum _DockKind { pass, undo, like }

class _DockButton extends StatefulWidget {
  const _DockButton({required this.kind, required this.enabled, required this.onTap});
  final _DockKind kind;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final enabled = widget.enabled;
    final isLike = kind == _DockKind.like;
    final isUndo = kind == _DockKind.undo;
    final size = isUndo ? 48.0 : 60.0;
    final iconSize = isLike ? 28.0 : (isUndo ? 20.0 : 26.0);

    final icon = switch (kind) {
      _DockKind.pass => LucideIcons.x,
      _DockKind.undo => LucideIcons.rotateCcw,
      _DockKind.like => LucideIcons.heart,
    };

    final Color iconColor;
    final Decoration decoration;
    if (isLike) {
      iconColor = Colors.white;
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: DiscoverTheme.ctaGradient,
        boxShadow: enabled
            ? const [BoxShadow(color: Color(0x55E11D48), blurRadius: 16, offset: Offset(0, 6))]
            : null,
      );
    } else if (isUndo) {
      const amber = Color(0xFFF59E0B);
      iconColor = enabled ? amber : const Color(0xFFCBD5E1);
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        color: enabled ? const Color(0xFFFFFBEB) : const Color(0xFFF1F5F9),
        border: Border.all(color: enabled ? amber.withValues(alpha: 0.55) : const Color(0xFFE2E8F0), width: 1.5),
      );
    } else {
      iconColor = enabled ? DiscoverTheme.slate : const Color(0xFFCBD5E1);
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: enabled
            ? const [BoxShadow(color: Color(0x140F172A), blurRadius: 10, offset: Offset(0, 4))]
            : null,
      );
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.42,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                HapticFeedback.selectionClick();
                widget.onTap();
              }
            : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        child: AnimatedScale(
          scale: _down && enabled ? 0.9 : 1,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: decoration,
            child: Icon(icon, size: iconSize, color: iconColor, fill: isLike ? 1 : 0),
          ),
        ),
      ),
    );
  }
}

class _CardFace extends StatefulWidget {
  const _CardFace({required this.card, this.onReport, this.onBlock});
  final Json card;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  @override
  State<_CardFace> createState() => _CardFaceState();
}

class _CardFaceState extends State<_CardFace> {
  final _page = PageController();
  int _photoIndex = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  List<String> _photoUrls(Json card) {
    final out = <String>[];
    final raw = card['photos'] ?? card['Photos'];
    if (raw is List) {
      for (final e in raw) {
        final s = '$e'.trim();
        if (s.startsWith('http') || s.startsWith('/')) {
          final abs = Api.absoluteUrl(s);
          if (abs != null) out.add(abs);
        }
      }
    }
    if (out.isEmpty) {
      for (final key in ['coverImageUrl', 'avatar']) {
        final s = card.s(key);
        if (s != null && (s.startsWith('http') || s.startsWith('/'))) {
          final abs = Api.absoluteUrl(s);
          if (abs != null && !out.contains(abs)) out.add(abs);
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = widget.card;
    final name = card.str('name');
    final age = card.i('age');
    final gender = card.str('gender');
    final country = card.s('country');
    final bio = (card.s('bio') ?? '').trim();
    final photos = _photoUrls(card);

    final genderLabel = switch (gender) {
      'male' => t('profile.genderMale'),
      'female' => t('profile.genderFemale'),
      _ => '',
    };

    final meta = [
      if (genderLabel.isNotEmpty) genderLabel,
      if (country != null && country.isNotEmpty) country,
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DiscoverTheme.cardRadius),
        boxShadow: DiscoverTheme.cardShadow,
      ),
      child: Material(
        color: c.bgElevated,
        borderRadius: BorderRadius.circular(DiscoverTheme.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photos.isEmpty)
              _fallback(name)
            else
              PageView.builder(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _photoIndex = i),
                itemBuilder: (_, i) => CachedNetworkImage(
                  imageUrl: photos[i],
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _fallback(name),
                ),
              ),
            // Tap left/right halves to flip photos (Tinder-style).
            if (photos.length > 1) ...[
                Positioned.fill(
                  child: Row(children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          if (_photoIndex > 0) {
                            _page.previousPage(duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          if (_photoIndex < photos.length - 1) {
                            _page.nextPage(duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
                          }
                        },
                      ),
                    ),
                  ]),
                ),
                Positioned(
                  top: 14,
                  left: 14,
                  right: 58,
                  child: Row(
                    children: [
                      for (var i = 0; i < photos.length; i++) ...[
                        if (i > 0) const SizedBox(width: 5),
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 3.5,
                            decoration: BoxDecoration(
                              color: i == _photoIndex ? Colors.white : Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: i == _photoIndex
                                  ? const [BoxShadow(color: Color(0x66000000), blurRadius: 4)]
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const DecoratedBox(decoration: BoxDecoration(gradient: DiscoverTheme.cardScrim)),
              if (widget.onReport != null || widget.onBlock != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.38),
                    shape: const CircleBorder(),
                    child: PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      icon: const Icon(LucideIcons.ellipsisVertical, color: Colors.white, size: 20),
                      onSelected: (v) {
                        if (v == 'report') widget.onReport?.call();
                        if (v == 'block') widget.onBlock?.call();
                      },
                      itemBuilder: (_) => [
                        if (widget.onReport != null) PopupMenuItem(value: 'report', child: Text(t('randomChat.report'))),
                        if (widget.onBlock != null) PopupMenuItem(value: 'block', child: Text(t('randomChat.block'))),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 22,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      age > 0 ? '$name, $age' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final m in meta)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                              ),
                              child: Text(
                                m,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        bio,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  Widget _fallback(String name) => Container(
        color: UserAvatar.colorFor(name),
        alignment: Alignment.center,
        child: Text(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w800, color: Colors.white70),
        ),
      );
}
