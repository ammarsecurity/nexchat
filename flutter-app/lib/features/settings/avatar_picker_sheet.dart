import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../services/media.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';

const presetAvatars = [
  '🦊', '🐺', '🦁', '🐯', '🐻', '🐼', '🐨', '🦋',
  '🦅', '🐬', '🦈', '🐙', '🌟', '🎭', '🎯', '🎮',
  '🚀', '⚡', '🔥', '💎', '👑', '🤖', '👻', '🎃',
  '🌈', '🌊', '🌺', '🍀', '⭐', '🎵',
];

bool isImageAvatar(String? v) => v != null && (v.startsWith('http') || v.startsWith('/'));

/// components/AvatarPickerSheet.vue
Future<void> showAvatarPicker(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const _AvatarPicker());

class _AvatarPicker extends ConsumerStatefulWidget {
  const _AvatarPicker();

  @override
  ConsumerState<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends ConsumerState<_AvatarPicker> {
  String _tab = 'preset';
  bool _uploading = false;

  Future<void> _select(String emoji) async {
    await ref.read(authProvider.notifier).setAvatar(emoji);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _upload() async {
    final file = await pickImage();
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final url = await uploadFile('/media/upload', file.path, filename: file.name);
      await ref.read(authProvider.notifier).setAvatar(url);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) showToast(context, t('common.error'), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final auth = ref.watch(authProvider);
    Widget tab(String id, IconData icon, String label) {
      final active = _tab == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 40,
            decoration: BoxDecoration(
              color: active ? const Color(0x336C63FF) : c.bgElevated,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? c.primary : c.border),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: active ? c.textPrimary : c.textSecondary),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 14, color: active ? c.textPrimary : c.textSecondary, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
        ),
      );
    }

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(t('settings.chooseAvatar'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          GlassIconButton(icon: LucideIcons.x, onTap: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          tab('preset', LucideIcons.image, t('settings.preset')),
          const SizedBox(width: 8),
          tab('upload', LucideIcons.upload, t('settings.uploadImage')),
        ]),
        const SizedBox(height: 16),
        if (_tab == 'preset')
          Flexible(
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 6,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                for (final e in presetAvatars)
                  GestureDetector(
                    onTap: () => _select(e),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: auth.avatar == e ? const Color(0x266C63FF) : auth.avatarColor,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: auth.avatar == e ? c.primary : Colors.transparent, width: 2),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
              ],
            ),
          )
        else
          Column(children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.border, width: 2), color: c.bgElevated),
              clipBehavior: Clip.antiAlias,
              child: isImageAvatar(auth.avatar)
                  ? CachedNetworkImage(imageUrl: Api.absoluteUrl(auth.avatar)!, fit: BoxFit.cover)
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(LucideIcons.image, size: 44, color: c.textMuted),
                      const SizedBox(height: 8),
                      Text(t('settings.noImage'), style: TextStyle(color: c.textMuted, fontSize: 13)),
                    ]),
            ),
            const SizedBox(height: 16),
            PillButton(
              label: t('settings.chooseImage'),
              onPressed: _uploading ? null : _upload,
            ),
            const SizedBox(height: 10),
            Text(t('settings.maxSize'), style: TextStyle(color: c.textMuted, fontSize: 13)),
          ]),
      ]),
    );
    return Stack(children: [content, LoaderOverlay(show: _uploading, text: t('settings.uploadingImage'))]);
  }
}
