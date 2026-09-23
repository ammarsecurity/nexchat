import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets.dart';

/// WhatsApp-like call chrome used by incoming, outgoing, and in-call screens.
class WaCall {
  static const bgTop = Color(0xFF0B141A);
  static const bgMid = Color(0xFF111B21);
  static const bgBottom = Color(0xFF0A1014);
  static const teal = Color(0xFF00A884);
  static const accept = Color(0xFF25D366);
  static const decline = Color(0xFFE54B4B);
  static const control = Color(0x33FFFFFF);
  static const controlActive = Color(0x59FFFFFF);

  static const nameStyle = TextStyle(
    color: Colors.white,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  static TextStyle statusStyle([double opacity = 0.72]) => TextStyle(
        color: Colors.white.withValues(alpha: opacity),
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.4,
      );
}

class CallPulseAvatar extends StatefulWidget {
  const CallPulseAvatar({super.key, this.url, required this.name, this.size = 132, this.pulse = true});
  final String? url;
  final String name;
  final double size;
  final bool pulse;

  @override
  State<CallPulseAvatar> createState() => _CallPulseAvatarState();
}

class _CallPulseAvatarState extends State<CallPulseAvatar> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void didUpdateWidget(CallPulseAvatar old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat();
    if (!widget.pulse && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = UserAvatar(url: widget.url, name: widget.name.isEmpty ? '?' : widget.name, size: widget.size);
    if (!widget.pulse) return avatar;
    return SizedBox(
      width: widget.size + 56,
      height: widget.size + 56,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          return Stack(alignment: Alignment.center, children: [
            for (final i in [0, 1])
              _ring((_c.value + i * 0.5) % 1),
            avatar,
          ]);
        },
      ),
    );
  }

  Widget _ring(double t) {
    final size = widget.size + 16 + 40 * t;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: (1 - t) * 0.28), width: 1.5),
      ),
    );
  }
}

class CallCircleButton extends StatelessWidget {
  const CallCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.background = WaCall.control,
    this.size = 64,
    this.iconSize = 26,
    this.label,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color background;
  final double size;
  final double iconSize;
  final String? label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bg = active && background == WaCall.control ? WaCall.controlActive : background;
    final btn = Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: Colors.white),
        ),
      ),
    );
    if (label == null || label!.isEmpty) return btn;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      btn,
      const SizedBox(height: 10),
      Text(label!, style: WaCall.statusStyle(0.85).copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }
}

/// Full-screen dark call backdrop + centered identity + bottom actions.
class WhatsAppRingingLayout extends StatelessWidget {
  const WhatsAppRingingLayout({
    super.key,
    this.avatarUrl,
    required this.name,
    required this.status,
    this.statusExtra,
    required this.actions,
    this.pulse = true,
    this.top,
  });

  final String? avatarUrl;
  final String name;
  final String status;
  final Widget? statusExtra;
  final List<Widget> actions;
  final bool pulse;
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [WaCall.bgTop, WaCall.bgMid, WaCall.bgBottom],
        ),
      ),
      child: Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.35),
                radius: 0.95,
                colors: [Color(0x3300A884), Color(0x0000A884)],
              ),
            ),
          ),
        ),
        if (top != null) Positioned(top: 0, left: 0, right: 0, child: top!),
        Padding(
          padding: EdgeInsets.fromLTRB(24, 88 + pad.top, 24, 28 + pad.bottom),
          child: Column(children: [
            const Spacer(),
            CallPulseAvatar(url: avatarUrl, name: name, size: 140, pulse: pulse),
            const SizedBox(height: 28),
            Text(
              name.isEmpty ? '…' : name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: WaCall.nameStyle,
            ),
            const SizedBox(height: 10),
            Text(status, textAlign: TextAlign.center, style: WaCall.statusStyle()),
            if (statusExtra != null) ...[const SizedBox(height: 12), statusExtra!],
            const Spacer(),
            Row(
              textDirection: TextDirection.ltr,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: actions,
            ),
          ]),
        ),
      ]),
    );
  }
}

class WhatsAppCallTopBar extends StatelessWidget {
  const WhatsAppCallTopBar({super.key, required this.name, this.subtitle, this.onMinimize, this.trailing});
  final String name;
  final String? subtitle;
  final VoidCallback? onMinimize;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(8, pad.top + 8, 8, 12),
      child: Row(children: [
        if (onMinimize != null)
          IconButton(
            onPressed: onMinimize,
            icon: const Icon(LucideIcons.chevronDown, color: Colors.white, size: 26),
          )
        else
          const SizedBox(width: 48),
        Expanded(
          child: Column(children: [
            Text(
              name.isEmpty ? '…' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: WaCall.statusStyle(0.8).copyWith(fontSize: 13)),
            ],
          ]),
        ),
        trailing ?? const SizedBox(width: 48),
      ]),
    );
  }
}
