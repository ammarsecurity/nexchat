import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../services/media.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';

const kMaxProfilePhotos = 4;

/// Discover / profile: upload-only gallery (1–4 real photos). No emoji presets.
Future<bool> showProfilePhotosSheet(BuildContext context) async {
  final ok = await showAppSheet<bool>(context, builder: (_) => const _ProfilePhotosSheet());
  return ok == true;
}

class _ProfilePhotosSheet extends ConsumerStatefulWidget {
  const _ProfilePhotosSheet();

  @override
  ConsumerState<_ProfilePhotosSheet> createState() => _ProfilePhotosSheetState();
}

class _ProfilePhotosSheetState extends ConsumerState<_ProfilePhotosSheet> {
  final List<String> _photos = [];
  /// Slot indexes currently uploading (loader shown in that tile).
  final Set<int> _uploadingSlots = {};
  bool _loading = true;
  bool _saving = false;

  bool get _busy => _uploadingSlots.isNotEmpty || _saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await Api.get('/user/me') as Map;
      final list = <String>[];
      final raw = me['profilePhotos'] ?? me['ProfilePhotos'];
      if (raw is List) {
        for (final e in raw) {
          final s = '$e'.trim();
          if (s.startsWith('http') || s.startsWith('/')) list.add(s);
        }
      }
      if (list.isEmpty) {
        final avatar = me.s('avatar');
        if (avatar != null && (avatar.startsWith('http') || avatar.startsWith('/'))) list.add(avatar);
        final cover = me.s('coverImageUrl');
        if (cover != null && (cover.startsWith('http') || cover.startsWith('/')) && !list.contains(cover)) {
          list.add(cover);
        }
      }
      if (mounted) {
        setState(() {
          _photos
            ..clear()
            ..addAll(list.take(kMaxProfilePhotos));
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPhotos() async {
    final start = _photos.length;
    final remaining = kMaxProfilePhotos - start;
    if (remaining <= 0 || _busy) return;
    final files = await pickImages(limit: remaining);
    if (files.isEmpty || !mounted) return;

    final batch = files.take(remaining).toList();
    setState(() {
      for (var i = 0; i < batch.length; i++) {
        _uploadingSlots.add(start + i);
      }
    });

    for (var i = 0; i < batch.length; i++) {
      final slot = start + i;
      try {
        final url = await uploadFile('/media/upload', batch[i].path, filename: batch[i].name);
        if (!mounted) return;
        setState(() {
          if (_photos.length < kMaxProfilePhotos && !_photos.contains(url)) {
            _photos.add(url);
          }
          _uploadingSlots.remove(slot);
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          // Clear this and any remaining queued slots for this batch.
          for (var j = i; j < batch.length; j++) {
            _uploadingSlots.remove(start + j);
          }
        });
        showToast(context, t('common.error'), error: true);
        break;
      }
    }
  }

  void _removeAt(int i) {
    if (_busy) return;
    setState(() => _photos.removeAt(i));
  }

  Future<void> _save() async {
    if (_photos.isEmpty) {
      showToast(context, t('discover.photosNeedOne'), error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await Api.put('/user/profile-photos', {'photos': _photos});
      final avatar = res is Map ? (res['avatar'] ?? res['Avatar']) as String? : _photos.first;
      await ref.read(authProvider.notifier).setAvatarLocal(avatar);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(t('discover.photosTitle'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            if (!_busy) GlassIconButton(icon: LucideIcons.x, onTap: () => Navigator.pop(context, false)),
          ]),
          const SizedBox(height: 6),
          Text(t('discover.photosHint'), style: TextStyle(fontSize: 13, color: c.textMuted, height: 1.35)),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: kMaxProfilePhotos,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemBuilder: (_, i) {
                if (i < _photos.length) return _PhotoTile(url: _photos[i], primary: i == 0, onRemove: _busy ? null : () => _removeAt(i));
                if (_uploadingSlots.contains(i)) return const _UploadSlotLoader();
                return _AddTile(enabled: !_busy, onTap: _addPhotos);
              },
            ),
          const SizedBox(height: 16),
          PillButton(
            label: t('discover.photosSave'),
            loading: _saving,
            onPressed: _loading || _busy ? null : _save,
          ),
          const SizedBox(height: 8),
          Text(t('settings.maxSize'), textAlign: TextAlign.center, style: TextStyle(color: c.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.url, required this.primary, this.onRemove});
  final String url;
  final bool primary;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final abs = Api.absoluteUrl(url)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(imageUrl: abs, fit: BoxFit.cover),
        ),
        if (onRemove != null)
          Positioned(
            top: 6,
            left: 6,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(LucideIcons.x, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        if (primary)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(8)),
              child: Text(t('discover.photosPrimary'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.bgElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(LucideIcons.imagePlus, size: 28, color: enabled ? c.textMuted : c.textMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text(
              t('discover.photosAdd'),
              style: TextStyle(
                fontSize: 13,
                color: enabled ? c.textSecondary : c.textMuted.withValues(alpha: 0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Compact, branded loader inside the add slot (not a full-screen overlay).
class _UploadSlotLoader extends StatelessWidget {
  const _UploadSlotLoader();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.primary.withValues(alpha: 0.55), width: 1.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.primary.withValues(alpha: 0.12),
            c.primarySoft.withValues(alpha: 0.35),
            c.bgElevated,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              color: c.primary,
              backgroundColor: c.primary.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t('settings.uploadingImage'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.primary, height: 1.25),
          ),
        ],
      ),
    );
  }
}
