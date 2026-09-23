import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';

enum StoryDialogVariant { error, danger, info }

/// components/stories/StoryDialog.vue — alert (one button) or confirm (two buttons).
class StoryDialog extends StatelessWidget {
  const StoryDialog({
    super.key,
    this.variant = StoryDialogVariant.error,
    this.confirm = false,
    this.title,
    this.message,
    this.confirmText,
    this.cancelText,
    this.loading = false,
    required this.onConfirm,
    this.onCancel,
  });

  final StoryDialogVariant variant;
  final bool confirm;
  final String? title;
  final String? message;
  final String? confirmText;
  final String? cancelText;
  final bool loading;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  String get _title {
    if (title?.isNotEmpty ?? false) return title!;
    return switch (variant) {
      StoryDialogVariant.error => t('common.error'),
      StoryDialogVariant.danger => t('stories.deleteSlideTitle'),
      StoryDialogVariant.info => t('stories.dialogNotice'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (IconData icon, Color fg, List<Color> bg, Color ring) = switch (variant) {
      StoryDialogVariant.danger => (LucideIcons.trash2, const Color(0xFFE53935), const [Color(0x2EE53935), Color(0x1AFF6584)], const Color(0x40E53935)),
      StoryDialogVariant.info => (LucideIcons.info, c.primary, const [Color(0x292563EB), Color(0x1A60A5FA)], const Color(0x382563EB)),
      StoryDialogVariant.error => (LucideIcons.circleAlert, c.danger, const [Color(0x33FF6584), Color(0x14FF6584)], const Color(0x47FF6584)),
    };
    final danger = confirm && variant == StoryDialogVariant.danger;
    final primaryLabel = confirmText ?? (danger ? t('common.delete') : t('common.ok'));

    Widget button({required String label, required Color bg, required Color fg, Color? border, VoidCallback? onTap, bool spinner = false}) => Expanded(
          child: Opacity(
            opacity: loading ? 0.75 : 1,
            child: Material(
              color: bg,
              shape: StadiumBorder(side: border == null ? BorderSide.none : BorderSide(color: border)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: loading ? null : onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (spinner) ...[
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg, backgroundColor: fg.withValues(alpha: 0.35))),
                      const SizedBox(width: 8),
                    ],
                    Flexible(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg))),
                  ]),
                ),
              ),
            ),
          ),
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Material(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          elevation: 8,
          shadowColor: c.shadow,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 52,
                  height: 52,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bg),
                    border: Border.all(color: ring),
                  ),
                  child: Icon(icon, size: 22, color: fg),
                ),
                Text(_title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35, color: c.textPrimary)),
                const SizedBox(height: 8),
                if (message?.isNotEmpty ?? false) ...[
                  Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.55, color: c.textSecondary)),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  if (confirm) ...[
                    button(label: cancelText ?? t('common.cancel'), bg: c.bgElevated, fg: c.textPrimary, border: c.border, onTap: onCancel),
                    const SizedBox(width: 10),
                  ],
                  button(
                    label: loading ? t('common.loading') : primaryLabel,
                    bg: danger ? c.danger : c.primary,
                    fg: Colors.white,
                    onTap: onConfirm,
                    spinner: loading,
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> _showStoryDialog<T>(BuildContext context, WidgetBuilder builder) => showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x85000000),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) => BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: builder(ctx)),
      transitionBuilder: (_, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
        );
      },
    );

Future<void> showStoryAlert(BuildContext context, String message, {String? title, StoryDialogVariant variant = StoryDialogVariant.error}) =>
    _showStoryDialog<void>(
      context,
      (ctx) => StoryDialog(variant: variant, title: title, message: message, onConfirm: () => Navigator.pop(ctx)),
    );

/// Stays open with a spinner while [onConfirm] runs; a failure replaces the content with an error alert.
Future<bool> showStoryConfirm(
  BuildContext context, {
  required String message,
  String? title,
  String? confirmText,
  StoryDialogVariant variant = StoryDialogVariant.danger,
  required Future<void> Function() onConfirm,
}) async {
  final ok = await _showStoryDialog<bool>(
    context,
    (ctx) => _ConfirmFlow(message: message, title: title, confirmText: confirmText, variant: variant, onConfirm: onConfirm),
  );
  return ok ?? false;
}

class _ConfirmFlow extends StatefulWidget {
  const _ConfirmFlow({required this.message, this.title, this.confirmText, required this.variant, required this.onConfirm});
  final String message;
  final String? title;
  final String? confirmText;
  final StoryDialogVariant variant;
  final Future<void> Function() onConfirm;

  @override
  State<_ConfirmFlow> createState() => _ConfirmFlowState();
}

class _ConfirmFlowState extends State<_ConfirmFlow> {
  bool _loading = false;
  String? _error;

  Future<void> _run() async {
    setState(() => _loading = true);
    try {
      await widget.onConfirm();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = Api.errorMessage(e, t('common.error'));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return PopScope(
      canPop: !_loading,
      child: error != null
          ? StoryDialog(message: error, onConfirm: () => Navigator.pop(context, false))
          : StoryDialog(
              variant: widget.variant,
              confirm: true,
              title: widget.title,
              message: widget.message,
              confirmText: widget.confirmText,
              loading: _loading,
              onConfirm: _run,
              onCancel: () => Navigator.pop(context, false),
            ),
    );
  }
}
