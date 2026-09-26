import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';
import 'hidden_chats_vault.dart';

/// Prompts the user to create/confirm a local secret code for hidden chats.
Future<bool> ensureHiddenChatsPin(BuildContext context) async {
  if (await HiddenChatsVault.instance.hasPin) return true;
  if (!context.mounted) return false;
  return showHiddenChatsPinDialog(context);
}

Future<bool> showHiddenChatsPinDialog(BuildContext context, {bool changing = false}) async {
  final pin = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final c = ctx.colors;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: Row(children: [
            Icon(LucideIcons.lock, size: 20, color: c.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                changing ? t('conversations.changePin') : t('conversations.setPinTitle'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary),
              ),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('conversations.setPinHint'), style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4)),
              const SizedBox(height: 12),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(hintText: t('conversations.setPinHint')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirm,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(hintText: t('conversations.confirmPinHint')),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: TextStyle(color: c.danger, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
            TextButton(
              onPressed: () async {
                final a = pin.text.trim();
                final b = confirm.text.trim();
                if (a.length < HiddenChatsVault.minPinLength) {
                  setLocal(() => error = t('conversations.pinTooShort'));
                  return;
                }
                if (a != b) {
                  setLocal(() => error = t('conversations.pinMismatch'));
                  return;
                }
                final saved = await HiddenChatsVault.instance.setPin(a);
                if (!ctx.mounted) return;
                if (!saved) {
                  setLocal(() => error = t('conversations.pinTooShort'));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(t('common.save')),
            ),
          ],
        ),
      );
    },
  );
  pin.dispose();
  confirm.dispose();
  // Toast after the next frame so it isn't tied to the dialog route teardown.
  if (ok == true && context.mounted) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) showToast(context, t('conversations.pinSaved'));
    });
  }
  return ok == true;
}
