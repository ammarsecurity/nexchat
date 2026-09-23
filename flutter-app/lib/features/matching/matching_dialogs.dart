import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import '../../core/theme/app_colors.dart';
import '../../services/ring_sound.dart';
import 'matching_controller.dart';

const _accentGradient = LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF60A5FA)]);
const _gold = Color(0xFFFACC15);

/// Shared `.req-overlay` / `.rm-overlay` + sliding sheet.
class _SheetOverlay extends StatelessWidget {
  const _SheetOverlay({required this.visible, required this.onBackdrop, required this.featured, required this.child});
  final bool visible;
  final VoidCallback onBackdrop;
  final bool featured;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pad = MediaQuery.paddingOf(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: visible ? 1 : 0,
        child: Stack(children: [
          Positioned.fill(child: GestureDetector(onTap: onBackdrop, child: const ColoredBox(color: Color(0x8C0F172A)))),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 280),
              curve: const Cubic(0.32, 0.72, 0, 1),
              offset: visible ? Offset.zero : const Offset(0, 1),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad.bottom),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border(
                        top: BorderSide(color: featured ? _gold.withValues(alpha: 0.35) : c.border),
                        left: BorderSide(color: c.border),
                        right: BorderSide(color: c.border),
                      ),
                      boxShadow: const [BoxShadow(color: Color(0x2E0F172A), blurRadius: 40, offset: Offset(0, -12))],
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(color: c.textMuted.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
                      ),
                      child,
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RequestAvatar extends StatelessWidget {
  const _RequestAvatar({required this.avatar, required this.name, required this.size, required this.featured, this.crownBottom = false});
  final String? avatar;
  final String name;
  final double size;
  final bool featured;
  final bool crownBottom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = avatar?.trim() ?? '';
    final isImage = a.startsWith('http') || a.startsWith('/');
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: featured && !crownBottom
                ? [_gold.withValues(alpha: 0.35), const Color(0x33FBBF24)]
                : [const Color(0x332563EB), const Color(0x5960A5FA)],
          ),
          boxShadow: [
            BoxShadow(color: c.bgCard, spreadRadius: 3),
            BoxShadow(color: featured ? _gold.withValues(alpha: 0.55) : const Color(0x402563EB), spreadRadius: 5),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: isImage
            ? Image.network(Api.absoluteUrl(a)!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())
            : Text(a.isNotEmpty ? a : letter,
                style: TextStyle(fontSize: a.isNotEmpty ? 38 : 32, fontWeight: FontWeight.w700, color: c.primary, height: 1)),
      ),
      if (featured)
        PositionedDirectional(
          top: crownBottom ? null : -4,
          bottom: crownBottom ? -2 : null,
          end: crownBottom ? -2 : -4,
          child: Icon(LucideIcons.crown, size: crownBottom ? 20 : 22, color: crownBottom ? _gold : const Color(0xFFFFD700),
              shadows: const [Shadow(color: Color(0x55000000), blurRadius: 2, offset: Offset(0, 1))]),
        ),
    ]);
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.icon, required this.label, required this.onTap, this.kind = 'accept', this.height = 50});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String kind;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = kind == 'accept';
    final (Color bg, Color fg, Color? border) = switch (kind) {
      'accept' => (Colors.transparent, Colors.white, null),
      'ghost' => (c.primarySoft, c.primary, null),
      'exit' => (const Color(0x142563EB), c.primary, const Color(0x472563EB)),
      _ => (c.bgElevated, c.textSecondary, c.border),
    };
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: accent ? null : bg,
          gradient: accent ? _accentGradient : null,
          borderRadius: BorderRadius.circular(14),
          border: border == null ? null : Border.all(color: border),
          boxShadow: accent ? const [BoxShadow(color: Color(0x592563EB), blurRadius: 18, offset: Offset(0, 6))] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: kind == 'exit' ? 14 : 15, fontWeight: FontWeight.w700))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// components/IncomingConnectionRequestDialog.vue
class IncomingConnectionRequestOverlay extends ConsumerStatefulWidget {
  const IncomingConnectionRequestOverlay({super.key});

  @override
  ConsumerState<IncomingConnectionRequestOverlay> createState() => _IncomingConnectionRequestOverlayState();
}

class _IncomingConnectionRequestOverlayState extends ConsumerState<IncomingConnectionRequestOverlay> {
  Timer? _expire;
  ConnectionRequest? _last;

  @override
  void dispose() {
    _expire?.cancel();
    super.dispose();
  }

  void _clear() {
    _expire?.cancel();
    RingSound.stop();
    ref.read(matchingProvider.notifier).clearIncomingConnectionRequest();
  }

  Future<void> _accept(ConnectionRequest r) async {
    _clear();
    try {
      await Hubs.matching.ensureConnected();
      await Hubs.matching.invoke('AcceptConnectionRequest', [r.requesterId]);
    } catch (_) {}
  }

  void _decline(ConnectionRequest r) {
    _clear();
    Hubs.matching.ensureConnected().then((_) => Hubs.matching.invoke('DeclineConnectionRequest', [r.requesterId])).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(matchingProvider.select((s) => s.incomingConnectionRequest), (_, r) {
      _expire?.cancel();
      if (r != null) {
        _expire = Timer(const Duration(seconds: 60), () {
          RingSound.stop();
          ref.read(matchingProvider.notifier).clearIncomingConnectionRequest();
        });
      }
    });
    final req = ref.watch(matchingProvider.select((s) => s.incomingConnectionRequest));
    if (req != null) _last = req;
    final r = req ?? _last;
    if (r == null) return const SizedBox.shrink();
    final c = context.colors;
    return _SheetOverlay(
      visible: req != null,
      featured: r.requesterIsFeatured,
      onBackdrop: () => _decline(r),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 2),
        _RequestAvatar(avatar: r.requesterAvatar, name: r.requesterName, size: 84, featured: r.requesterIsFeatured),
        const SizedBox(height: 14),
        Text(t('incomingRequest.title'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary)),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: r.requesterName, style: TextStyle(fontWeight: FontWeight.w700, color: c.textPrimary)),
            if (r.requesterIsFeatured)
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(LucideIcons.crown, size: 14, color: Color(0xFFFFD700))),
              ),
            TextSpan(text: ' ${t('incomingRequest.wantsToConnect')}'),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _SheetButton(icon: LucideIcons.x, label: t('incomingRequest.decline'), kind: 'outline', onTap: () => _decline(r))),
          const SizedBox(width: 10),
          Expanded(child: _SheetButton(icon: LucideIcons.check, label: t('incomingRequest.accept'), onTap: () => _accept(r))),
        ]),
      ]),
    );
  }
}

/// components/RandomMatchConsentDialog.vue
class RandomMatchConsentOverlay extends ConsumerStatefulWidget {
  const RandomMatchConsentOverlay({super.key});

  @override
  ConsumerState<RandomMatchConsentOverlay> createState() => _RandomMatchConsentOverlayState();
}

class _RandomMatchConsentOverlayState extends ConsumerState<RandomMatchConsentOverlay> {
  bool _waitingPeer = false;
  bool _acting = false;
  PendingRandomMatch? _last;

  Future<void> _accept(String sid) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _waitingPeer = true;
    });
    try {
      await Hubs.matching.ensureConnected();
      await Hubs.matching.invoke('AcceptRandomMatch', [sid]);
    } catch (_) {
      if (mounted) setState(() => _waitingPeer = false);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _declineOrSkip(String sid) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await Hubs.matching.ensureConnected();
      await Hubs.matching.invoke('DeclineRandomMatch', [sid]);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _exit(String sid) async {
    if (_acting) return;
    setState(() => _acting = true);
    final m = ref.read(matchingProvider.notifier)..armSkipRestartAfterRandomDecline();
    try {
      await Hubs.matching.ensureConnected();
      await Hubs.matching.invoke('DeclineRandomMatch', [sid]);
    } catch (_) {
      m.consumeSkipRestartAfterRandomDecline();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(matchingProvider.select((s) => s.pendingRandomMatch), (_, v) {
      if (v == null && _waitingPeer) setState(() => _waitingPeer = false);
    });
    final pending = ref.watch(matchingProvider.select((s) => s.pendingRandomMatch));
    if (pending != null) _last = pending;
    final pm = pending ?? _last;
    if (pm == null) return const SizedBox.shrink();
    final c = context.colors;
    final p = pm.partner ?? const <String, dynamic>{};
    final featured = p.b('isFeatured');
    final name = p.str('name');
    final code = p.s('uniqueCode');
    final sid = pm.sessionId;
    return _SheetOverlay(
      visible: pending != null,
      featured: featured,
      onBackdrop: () => _declineOrSkip(sid),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(t('randomMatch.hint'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.5)),
        const SizedBox(height: 16),
        _RequestAvatar(avatar: p.s('avatar'), name: name, size: 88, featured: featured, crownBottom: true),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: name.isNotEmpty ? name : '…'),
            if (featured)
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(padding: EdgeInsetsDirectional.only(start: 4), child: Icon(LucideIcons.crown, size: 14, color: _gold)),
              ),
          ]),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.textPrimary),
        ),
        const SizedBox(height: 4),
        if (code != null && code.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('${t('randomMatch.publicId')}: $code',
                style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        if (_waitingPeer)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.textSecondary)),
              const SizedBox(width: 8),
              Text(t('randomMatch.waitingPeer'), style: TextStyle(fontSize: 14, color: c.textSecondary)),
            ]),
          ),
        const SizedBox(height: 4),
        _SheetButton(
          icon: LucideIcons.check,
          label: t('randomMatch.accept'),
          height: 48,
          onTap: _acting || _waitingPeer ? null : () => _accept(sid),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _SheetButton(
                icon: LucideIcons.skipForward, label: t('randomMatch.skip'), kind: 'ghost', height: 48, onTap: _acting ? null : () => _declineOrSkip(sid)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SheetButton(
                icon: LucideIcons.x, label: t('randomMatch.decline'), kind: 'outline', height: 48, onTap: _acting ? null : () => _declineOrSkip(sid)),
          ),
        ]),
        const SizedBox(height: 10),
        _SheetButton(icon: LucideIcons.logOut, label: t('randomMatch.exitRandom'), kind: 'exit', height: 46, onTap: _acting ? null : () => _exit(sid)),
        const SizedBox(height: 14),
        Text(t('randomMatch.legalHint'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.45)),
      ]),
    );
  }
}
