import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n/i18n.dart';
import '../core/network/api_client.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/layout.dart';

/// `.btn-primary` / `.update-btn` — the brand gradient button.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, this.onPressed, this.icon, this.loading = false, this.height = 48});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: disabled ? 0.6 : 1,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: const [BoxShadow(color: Color(0x666C63FF), blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: disabled ? null : onPressed,
            child: Center(
              child: loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[Icon(icon, size: 20, color: Colors.white), const SizedBox(width: 8)],
                        Flexible(
                          child: Text(label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
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

/// `.btn-secondary` — soft outlined button.
class SoftButton extends StatelessWidget {
  const SoftButton({super.key, required this.label, this.onPressed, this.icon, this.color, this.height = 48});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = color ?? c.textPrimary;
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: c.bgElevated,
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}

/// `.glass-card`
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = AppRadius.lg, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );
  }
}

/// Circle avatar with image or initial on the name-based palette colour.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.url, required this.name, this.size = 48, this.featured = false, this.online});
  final String? url;
  final String name;
  final double size;
  final bool featured;
  final bool? online;

  static const palette = [Color(0xFF6C63FF), Color(0xFFFF6584), Color(0xFF00D4FF), Color(0xFFFF8C42), Color(0xFFA8FF78)];

  static Color colorFor(String name) => name.isEmpty ? palette.first : palette[name.codeUnitAt(0) % palette.length];

  @override
  Widget build(BuildContext context) {
    final raw = url?.trim() ?? '';
    final isImage = raw.startsWith('http') || raw.startsWith('/');
    final emoji = raw.isNotEmpty && !isImage ? raw : null;
    final src = isImage ? Api.absoluteUrl(raw) : null;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    Widget fallback() => Container(
          color: colorFor(name),
          alignment: Alignment.center,
          child: emoji != null
              ? Text(emoji, textAlign: TextAlign.center, style: TextStyle(fontSize: size * 0.56, height: 1.1))
              : Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.4)),
        );
    Widget img = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: src == null
            ? fallback()
            : CachedNetworkImage(
                imageUrl: src,
                fit: BoxFit.cover,
                memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
                fadeInDuration: const Duration(milliseconds: 150),
                fadeOutDuration: Duration.zero,
                errorWidget: (_, _, _) => fallback(),
                placeholder: (_, _) => fallback(),
              ),
      ),
    );
    if (featured) {
      img = Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)])),
        child: img,
      );
    }
    if (online == null) return img;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        img,
        PositionedDirectional(
          bottom: 1,
          end: 1,
          child: Container(
            width: size * 0.26,
            height: size * 0.26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online! ? context.colors.success : context.colors.textMuted,
              border: Border.all(color: context.colors.bgCard, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// `.modern-glass-btn`
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onTap, this.color, this.badgeDot = false, this.overlay = false});
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final bool badgeDot;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: overlay ? const Color(0x590F172A) : c.bgCard,
      borderRadius: BorderRadius.circular(14),
      shadowColor: c.shadow,
      elevation: overlay ? 0 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(alignment: Alignment.center, children: [
            Icon(icon, size: 20, color: overlay ? Colors.white : (color ?? c.textPrimary)),
            if (badgeDot)
              PositionedDirectional(
                top: 10,
                end: 11,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: c.bgCard, width: 2),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// components/ui/ModernPageShell.vue
class ModernPage extends StatelessWidget {
  const ModernPage({
    super.key,
    required this.title,
    required this.body,
    this.showBack = true,
    this.backTo,
    this.actions = const [],
    this.scroll = true,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 24),
    this.bottom,
  });
  final String title;
  final Widget body;
  final bool showBack;
  final String? backTo;
  final List<Widget> actions;
  final bool scroll;
  final EdgeInsets padding;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pad = MediaQuery.paddingOf(context);
    void back() {
      if (backTo != null) {
        GoRouter.of(context).go(backTo!);
      } else if (GoRouter.of(context).canPop()) {
        GoRouter.of(context).pop();
      } else {
        GoRouter.of(context).go('/conversations');
      }
    }

    return Scaffold(
      backgroundColor: c.bgPrimary,
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, pad.top + 10, 16, 12),
          child: Row(children: [
            if (showBack)
              GlassIconButton(icon: rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft, onTap: back)
            else
              const SizedBox(width: 48),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
            ),
            const SizedBox(width: 10),
            if (actions.isEmpty) const SizedBox(width: 48) else Row(mainAxisSize: MainAxisSize.min, children: actions),
          ]),
        ),
        Expanded(
          child: scroll
              ? SingleChildScrollView(
                  padding: padding.copyWith(
                    bottom: padding.bottom >= kTabBarContentHeight ? padding.bottom : padding.bottom + pad.bottom,
                  ),
                  child: body,
                )
              : Padding(padding: padding.copyWith(bottom: 0), child: body),
        ),
        ?bottom,
      ]),
    );
  }
}

/// Header row used by most inner pages (back chevron + title + optional actions).
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.onBack, this.actions = const [], this.showBack = true});
  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, MediaQuery.paddingOf(context).top + 8, 8, 8),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              icon: Icon(rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft, color: c.textPrimary),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// `.btn-gradient` — solid primary pill.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, this.onPressed, this.loading = false, this.color, this.expand = true});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = color ?? c.primary;
    final btn = Opacity(
      opacity: onPressed == null && !loading ? 0.5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        elevation: 0,
        shadowColor: bg.withValues(alpha: 0.3),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: loading ? null : onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 28),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// `.modern-list-row`
class ModernListRow extends StatelessWidget {
  const ModernListRow({super.key, required this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.onLongPress, this.subtitleLtr = false});
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool subtitleLtr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: subtitleLtr ? TextDirection.ltr : null,
                        style: TextStyle(fontSize: 13, color: c.textSecondary)),
                ]),
              ),
              ?trailing,
            ]),
          ),
        ),
      ),
    );
  }
}

/// `.modern-search-bar`
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, required this.hint, this.onChanged, this.trailing});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 6)],
      ),
      child: Row(children: [
        Icon(LucideIcons.search, size: 18, color: c.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: TextStyle(color: c.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: c.textMuted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
            ),
          ),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Bottom sheet with the drag handle used across the Vue app (`.context-sheet`).
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: context.colors.bgCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: ctx.colors.textMuted.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
          ),
          Flexible(child: builder(ctx)),
        ]),
      ),
    ),
  );
}

class SheetAction extends StatelessWidget {
  const SheetAction({super.key, required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = danger ? c.danger : c.textPrimary;
    return ListTile(
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 15)),
      onTap: onTap,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: c.primary),
            ),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 15)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Branded spinning ring used by auth and page loaders.
class AppSpinner extends StatefulWidget {
  const AppSpinner({super.key, this.size = 36});
  final double size;

  @override
  State<AppSpinner> createState() => _AppSpinnerState();
}

class _AppSpinnerState extends State<AppSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final box = widget.size + 28;
    return SizedBox(
      width: box,
      height: box,
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.primarySoft, shape: BoxShape.circle),
        child: RotationTransition(
          turns: _c,
          child: CustomPaint(
            painter: _SpinnerRingPainter(color: c.primary, track: c.primaryMuted),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _SpinnerRingPainter extends CustomPainter {
  const _SpinnerRingPainter({required this.color, required this.track});
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 10;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..color = track,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -0.9,
      1.85,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SpinnerRingPainter old) => old.color != color || old.track != track;
}

/// Centered glass card: spinner + Arabic/English status line.
class AppLoaderCard extends StatelessWidget {
  const AppLoaderCard({super.key, this.text});
  final String? text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = (text?.trim().isNotEmpty ?? false) ? text!.trim() : t('common.loading');
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(color: c.shadow, blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppSpinner(),
              const SizedBox(height: 16),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// In-page loader (terms/privacy/onboarding) — no dark veil over the header.
class PageLoader extends StatelessWidget {
  const PageLoader({super.key, this.text});
  final String? text;

  @override
  Widget build(BuildContext context) => Center(child: AppLoaderCard(text: text));
}

/// Full-screen dim + [AppLoaderCard]. Parent must be a [Stack].
class LoaderOverlay extends StatelessWidget {
  const LoaderOverlay({super.key, required this.show, this.text});
  final bool show;
  final String? text;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    final light = Theme.of(context).brightness == Brightness.light;
    return Positioned.fill(
      child: AbsorbPointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          builder: (context, value, child) => Opacity(opacity: value, child: child),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(
                color: light ? const Color(0x4D0F172A) : const Color(0x99000000),
                child: Center(child: AppLoaderCard(text: text)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum ToastType { info, success, error }

/// stores/notify.js — one toast at a time, rendered by [AppToastHost].
class AppToast {
  AppToast._();

  static final current = ValueNotifier<({String message, ToastType type, int id})?>(null);
  static Timer? _hide;
  static int _seq = 0;

  static void show(String message, [ToastType type = ToastType.info]) {
    if (message.isEmpty) return;
    current.value = (message: message, type: type, id: ++_seq);
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 3800), close);
  }

  static void close() {
    _hide?.cancel();
    current.value = null;
  }
}

void showToast(BuildContext context, String message, {bool error = false, bool success = false}) =>
    AppToast.show(message, error ? ToastType.error : (success ? ToastType.success : ToastType.info));

/// components/AppToast.vue
class AppToastHost extends StatelessWidget {
  const AppToastHost({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = MediaQuery.paddingOf(context).top;
    return ValueListenableBuilder(
      valueListenable: AppToast.current,
      builder: (context, toast, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, -0.3), end: Offset.zero).animate(a), child: child),
        ),
        child: toast == null
            ? const SizedBox.shrink()
            : Align(
                key: ValueKey(toast.id),
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, top > 12 ? top : 12, 12, 0),
                  child: _ToastCard(message: toast.message, type: toast.type, colors: c),
                ),
              ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.message, required this.type, required this.colors});
  final String message;
  final ToastType type;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    const danger = Color(0xFFFF6584);
    final (Color fg, Color iconBg, BoxDecoration deco, IconData icon) = switch (type) {
      ToastType.error => (
          c.danger,
          danger.withValues(alpha: 0.2),
          BoxDecoration(
            gradient: LinearGradient(colors: [danger.withValues(alpha: 0.18), danger.withValues(alpha: 0.08)]),
            border: Border.all(color: danger.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(14),
          ),
          LucideIcons.circleAlert,
        ),
      ToastType.success => (
          c.primary,
          c.primary.withValues(alpha: 0.18),
          BoxDecoration(
            gradient: LinearGradient(colors: [c.primary.withValues(alpha: 0.2), c.primary.withValues(alpha: 0.08)]),
            border: Border.all(color: c.primary.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(14),
          ),
          LucideIcons.circleCheck,
        ),
      ToastType.info => (
          c.textPrimary,
          c.primary.withValues(alpha: 0.12),
          BoxDecoration(color: c.bgCard, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(14)),
          LucideIcons.info,
        ),
    };
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: AppToast.close,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: deco.copyWith(
            color: type == ToastType.info ? c.bgCard : c.bgPrimary,
            boxShadow: const [BoxShadow(color: Color(0x38000000), blurRadius: 28, offset: Offset(0, 8))],
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35)),
            ),
          ]),
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, {required String title, String? message, required String confirm, required String cancel, bool danger = false}) async {
  final c = context.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm, style: TextStyle(color: danger ? c.danger : c.primary, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok == true;
}
