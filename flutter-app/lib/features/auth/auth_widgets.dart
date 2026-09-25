import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/share_links.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// خلفية باترن مميزة لصفحات المصادقة (دخول / تسجيل).
class AuthPatternBackground extends StatelessWidget {
  const AuthPatternBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    return ColoredBox(
      color: c.bgPrimary,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // توهج علوي بلون البراند
          Positioned(
            top: -120,
            right: -80,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c.primary.withValues(alpha: light ? 0.18 : 0.22),
                      c.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -90,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF7C75FF).withValues(alpha: light ? 0.14 : 0.18),
                      const Color(0xFF7C75FF).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.42,
            left: -40,
            child: IgnorePointer(
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF60A5FA).withValues(alpha: light ? 0.10 : 0.12),
                      const Color(0xFF60A5FA).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // باترن فقاعات الدردشة المتكرر
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AuthChatPatternPainter(
                  color: c.primary,
                  opacity: light ? 0.11 : 0.07,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AuthChatPatternPainter extends CustomPainter {
  _AuthChatPatternPainter({required this.color, required this.opacity});
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color.withValues(alpha: opacity * 0.55)
      ..style = PaintingStyle.fill;

    const tile = 88.0;
    final cols = (size.width / tile).ceil() + 1;
    final rows = (size.height / tile).ceil() + 1;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final ox = col * tile + ((row.isOdd) ? tile * 0.35 : 0);
        final oy = row * tile;
        _drawBubble(canvas, Offset(ox + 18, oy + 22), 34, 22, stroke);
        _drawBubble(canvas, Offset(ox + 52, oy + 10), 18, 12, stroke);
        canvas.drawCircle(Offset(ox + 12, oy + 12), 2.0, fill);
        canvas.drawCircle(Offset(ox + 70, oy + 68), 1.6, fill);
      }
    }
  }

  void _drawBubble(Canvas canvas, Offset origin, double w, double h, Paint paint) {
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(origin.dx, origin.dy, w, h), Radius.circular(h * 0.28));
    canvas.drawRRect(r, paint);
    // ذيل الفقاعة
    final path = Path()
      ..moveTo(origin.dx + 6, origin.dy + h)
      ..lineTo(origin.dx + 2, origin.dy + h + 6)
      ..lineTo(origin.dx + 12, origin.dy + h);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AuthChatPatternPainter old) =>
      old.color != color || old.opacity != opacity;
}

/// `.input-native` from the auth pages.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.hint,
    this.password = false,
    this.maxLength,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String hint;
  final bool password;
  final int? maxLength;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border));
    return TextField(
      controller: widget.controller,
      obscureText: widget.password && !_show,
      maxLength: widget.maxLength,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofillHints: widget.autofillHints,
      style: TextStyle(fontFamily: kAppFont, color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        counterText: '',
        hintText: widget.hint,
        hintStyle: TextStyle(fontFamily: kAppFont, color: c.textMuted),
        filled: true,
        fillColor: c.bgCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: BorderSide(color: c.primary)),
        suffixIcon: widget.password
            ? IconButton(
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? LucideIcons.eyeOff : LucideIcons.eye, size: 20, color: c.primary),
              )
            : null,
      ),
    );
  }
}

/// `.error-toast`
class AuthError extends StatelessWidget {
  const AuthError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 18, color: c.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: c.danger, fontSize: 14))),
        ],
      ),
    );
  }
}

/// Solid primary submit button (`.login-btn`, `.register-btn`).
class AuthSubmit extends StatelessWidget {
  const AuthSubmit({super.key, required this.label, required this.onPressed, this.loading = false, this.pill = false});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !loading;
    final radius = BorderRadius.circular(pill ? 999 : 14);
    return Opacity(
      opacity: enabled || loading ? 1 : 0.5,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: radius,
          boxShadow: pill && enabled ? const [BoxShadow(color: Color(0x472563EB), blurRadius: 14, offset: Offset(0, 4))] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(label,
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: pill ? FontWeight.w700 : FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }
}

class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, required this.privacy, required this.terms, required this.onPrivacy, required this.onTerms});
  final String privacy;
  final String terms;
  final VoidCallback onPrivacy;
  final VoidCallback onTerms;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontFamily: kAppFont, color: c.primary, fontSize: 13, fontWeight: FontWeight.w500);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      children: [
        GestureDetector(onTap: onPrivacy, child: Text(privacy, style: style)),
        Text('·', style: TextStyle(fontFamily: kAppFont, color: c.textSecondary.withValues(alpha: 0.45))),
        GestureDetector(onTap: onTerms, child: Text(terms, style: style)),
      ],
    );
  }
}

/// صف الموافقة على الخصوصية والشروط في صفحة التسجيل.
class LegalAcceptRow extends StatefulWidget {
  const LegalAcceptRow({
    super.key,
    required this.accepted,
    required this.onChanged,
    required this.prefix,
    required this.privacyLabel,
    required this.mid,
    required this.termsLabel,
    required this.onPrivacy,
    required this.onTerms,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;
  final String prefix;
  final String privacyLabel;
  final String mid;
  final String termsLabel;
  final VoidCallback onPrivacy;
  final VoidCallback onTerms;

  @override
  State<LegalAcceptRow> createState() => _LegalAcceptRowState();
}

class _LegalAcceptRowState extends State<LegalAcceptRow> {
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()..onTap = widget.onPrivacy;
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()..onTap = widget.onTerms;

  @override
  void didUpdateWidget(covariant LegalAcceptRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onPrivacy != widget.onPrivacy) _privacyTap.onTap = widget.onPrivacy;
    if (oldWidget.onTerms != widget.onTerms) _termsTap.onTap = widget.onTerms;
  }

  @override
  void dispose() {
    _privacyTap.dispose();
    _termsTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accepted = widget.accepted;
    final body = TextStyle(fontFamily: kAppFont, fontSize: 13, height: 1.55, color: c.textSecondary, fontWeight: FontWeight.w500);
    final link = TextStyle(
      fontFamily: kAppFont,
      fontSize: 13,
      height: 1.55,
      color: c.primary,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: c.primary.withValues(alpha: 0.45),
      decorationThickness: 1.2,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onChanged(!accepted),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: accepted ? c.primarySoft : c.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accepted ? c.primary.withValues(alpha: 0.35) : c.border),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: 4)],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: accepted ? c.primary : c.bgElevated,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: accepted ? c.primary : c.border, width: 1.5),
                ),
                child: accepted ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: body,
                    children: [
                      TextSpan(text: '${widget.prefix} '),
                      TextSpan(text: widget.privacyLabel, style: link, recognizer: _privacyTap),
                      TextSpan(text: ' ${widget.mid} '),
                      TextSpan(text: widget.termsLabel, style: link, recognizer: _termsTap),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Invite code from the `invite` query param, else the one stored by /join/:code (sessionStorage in the Vue app).
/// Always clears the stored code.
String? takePendingInvite(String? fromQuery) {
  final stored = Prefs.instance.getString(Keys.pendingInvite);
  if (stored != null) Prefs.instance.setString(Keys.pendingInvite, null);
  final code = normalizeInviteCode((fromQuery?.trim().isNotEmpty ?? false) ? fromQuery : stored);
  return code.isEmpty ? null : code;
}

/// Birth-date dropdown box (.date-box).
class DateSelect extends StatelessWidget {
  const DateSelect({super.key, required this.hint, required this.value, required this.items, required this.onChanged});
  final String hint;
  final int? value;
  final List<int> items;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // DropdownButton ignores Theme.fontFamily unless style/hint set it explicitly.
    final hintStyle = TextStyle(fontFamily: kAppFont, color: c.textMuted, fontSize: 15, fontWeight: FontWeight.w600);
    final valueStyle = TextStyle(fontFamily: kAppFont, color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 4)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: items.contains(value) ? value : null,
          isExpanded: true,
          menuMaxHeight: 320,
          dropdownColor: c.bgCard,
          borderRadius: BorderRadius.circular(14),
          alignment: Alignment.center,
          icon: const SizedBox.shrink(),
          hint: Center(child: Text(hint, style: hintStyle)),
          style: valueStyle,
          items: [
            for (final i in items)
              DropdownMenuItem(
                value: i,
                alignment: Alignment.center,
                child: Text('$i', style: valueStyle),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

