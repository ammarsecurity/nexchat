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
import 'profile_photos_sheet.dart';

bool isImageAvatar(String? v) => v != null && (v.startsWith('http') || v.startsWith('/'));

/// Opens the profile photo gallery (up to 4 real photos). Emoji presets removed.
Future<void> showAvatarPicker(BuildContext context) async {
  await showProfilePhotosSheet(context);
}

/// Legacy single-upload sheet (kept for rare call sites that need one shot).
Future<void> showSinglePhotoUpload(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const _SinglePhotoUpload());

class _SinglePhotoUpload extends ConsumerStatefulWidget {
  const _SinglePhotoUpload();

  @override
  ConsumerState<_SinglePhotoUpload> createState() => _SinglePhotoUploadState();
}

class _SinglePhotoUploadState extends ConsumerState<_SinglePhotoUpload> {
  bool _uploading = false;

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
    return Stack(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text(t('settings.uploadImage'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            GlassIconButton(icon: LucideIcons.x, onTap: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
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
          PillButton(label: t('settings.chooseImage'), onPressed: _uploading ? null : _upload),
          const SizedBox(height: 10),
          Text(t('settings.maxSize'), style: TextStyle(color: c.textMuted, fontSize: 13)),
        ]),
      ),
      LoaderOverlay(show: _uploading, text: t('settings.uploadingImage')),
    ]);
  }
}
