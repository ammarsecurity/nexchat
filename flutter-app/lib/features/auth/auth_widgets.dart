import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/share_links.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';

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
      style: TextStyle(color: c.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        counterText: '',
        hintText: widget.hint,
        hintStyle: TextStyle(color: c.textMuted),
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
    final style = TextStyle(color: c.primary, fontSize: 13, fontWeight: FontWeight.w500);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      children: [
        GestureDetector(onTap: onPrivacy, child: Text(privacy, style: style)),
        Text('·', style: TextStyle(color: c.textSecondary.withValues(alpha: 0.45))),
        GestureDetector(onTap: onTerms, child: Text(terms, style: style)),
      ],
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
          hint: Center(child: Text(hint, style: TextStyle(color: c.textMuted, fontSize: 15, fontWeight: FontWeight.w600))),
          style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
          items: [for (final i in items) DropdownMenuItem(value: i, alignment: Alignment.center, child: Text('$i'))],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

