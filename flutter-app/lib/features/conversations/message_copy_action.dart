import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../shared/widgets.dart';
import 'message_contract.dart';

/// One action in the existing long-press sheet, shared by received and own rows.
class MessageCopyAction extends StatelessWidget {
  const MessageCopyAction({super.key, required this.message, required this.onClose, required this.onCopied, required this.onFailure});
  final Json message;
  final VoidCallback onClose;
  final VoidCallback onCopied;
  final VoidCallback onFailure;

  @override
  Widget build(BuildContext context) {
    final text = copyableMessageText(message);
    if (text == null) return const SizedBox.shrink();
    return SheetAction(
      icon: LucideIcons.copy,
      label: t('conversationChat.copy'),
      onTap: () async {
        onClose();
        try {
          await Clipboard.setData(ClipboardData(text: text));
          onCopied();
        } catch (_) { onFailure(); }
      },
    );
  }
}
