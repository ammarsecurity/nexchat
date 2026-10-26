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
import 'discover_match_dialog.dart';
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
    final saved = await showBirthDateSheet(context);
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
            final saved = await showProfilePhotosSheet(context);
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  t('discover.title'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: DiscoverTheme.ink, height: 1.2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(t('discover.policy'), style: TextStyle(fontSize: 12, height: 1.35, color: DiscoverTheme.redDeep.withValues(alpha: 0.65))),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('common.error'), style: TextStyle(color: DiscoverTheme.redDeep.withValues(alpha: 0.7))),
          const SizedBox(height: 12),
          SoftButton(label: t('common.retry'), color: DiscoverTheme.red, onPressed: () => ref.read(discoverProvider.notifier).refresh()),
        ]),
      );
    }
    if (state.deck.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.heartHandshake, size: 48, color: DiscoverTheme.red.withValues(alpha: 0.85)),
          const SizedBox(height: 12),
          Text(t('discover.empty'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: DiscoverTheme.ink)),
          const SizedBox(height: 8),
          Text(t('discover.emptyHint'), textAlign: TextAlign.center, style: TextStyle(color: DiscoverTheme.redDeep.withValues(alpha: 0.55))),
          const SizedBox(height: 16),
          SoftButton(label: t('common.retry'), color: DiscoverTheme.red, onPressed: () => ref.read(discoverProvider.notifier).refresh()),
        ]),
      );
    }

    final top = state.deck.first;
    final behind = state.deck.length > 1 ? state.deck[1] : null;

    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (behind != null)
                Transform.scale(
                  scale: 0.96,
                  child: Opacity(opacity: 0.85, child: _CardFace(card: behind)),
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
                    children: [
                      _CardFace(
                        card: top,
                        onReport: () => _reportCard(top),
                        onBlock: () => _blockCard(top),
                      ),
                      Positioned(
                        top: 28,
                        left: 24,
                        child: Opacity(
                          opacity: (-_drag.dx / 120).clamp(0.0, 1.0),
                          child: _Stamp(label: t('discover.pass'), color: const Color(0xFF64748B)),
                        ),
                      ),
                      Positioned(
                        top: 28,
                        right: 24,
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
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundAction(
              color: const Color(0xFF64748B),
              icon: LucideIcons.x,
              onTap: _busy ? null : () => _act(like: false),
            ),
            const SizedBox(width: 28),
            _RoundAction(
              color: DiscoverTheme.red,
              icon: LucideIcons.heart,
              large: true,
              onTap: _busy ? null : () => _act(like: true),
            ),
          ],
        ),
      ],
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
      angle: label == t('discover.like') ? -0.2 : 0.2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 1.2)),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.color, required this.icon, this.onTap, this.large = false});
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 72.0 : 58.0;
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: large ? 32 : 26, color: color),
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
    final photos = _photoUrls(card);

    final genderLabel = switch (gender) {
      'male' => t('profile.genderMale'),
      'female' => t('profile.genderFemale'),
      _ => '',
    };

    return Material(
      elevation: 8,
      shadowColor: c.shadow,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 0.72,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photos.isEmpty)
              _fallback(name)
            else
              PageView.builder(
                controller: _page,
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _photoIndex = i),
                itemBuilder: (_, i) => CachedNetworkImage(
                  imageUrl: photos[i],
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _fallback(name),
                ),
              ),
            // Tap zones to flip photos without conflicting with horizontal swipe of the card.
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
                top: 12,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    for (var i = 0; i < photos.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: i == _photoIndex ? Colors.white : Colors.white38,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0x00000000), Color(0xCC0B1220)],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            if (widget.onReport != null || widget.onBlock != null)
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: PopupMenuButton<String>(
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
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    age > 0 ? '$name, $age' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [if (genderLabel.isNotEmpty) genderLabel, if (country != null && country.isNotEmpty) country].join(' · '),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w500),
                  ),
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
