import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../services/media.dart';
import '../../shared/video_poster.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import 'stories_controller.dart';
import 'story_dialog.dart';
import 'story_editor.dart';

class _ExportFailed implements Exception {}

/// views/StoryCreateView.vue
class StoryCreateScreen extends ConsumerStatefulWidget {
  const StoryCreateScreen({super.key});

  @override
  ConsumerState<StoryCreateScreen> createState() => _StoryCreateScreenState();
}

class _StoryCreateScreenState extends ConsumerState<StoryCreateScreen> {
  final _editorKey = GlobalKey<StoryEditorState>();
  final _caption = TextEditingController();
  String _step = 'pick';
  String? _imageSrc;
  String? _videoSrc;
  String? _videoFile;
  String? _originalImageFile;
  bool _textOnly = false;
  String _background = defaultStoryBackground;
  bool _publishing = false;
  String? _editingSlideId;
  String? _editingOverlay;
  String _editingFilterId = 'none';
  List<StorySlide> _mySlides = const [];
  bool _mySlidesLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMySlides();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _loadMySlides() async {
    setState(() => _mySlidesLoading = true);
    try {
      final data = await Api.get('/stories/mine');
      if (mounted) setState(() => _mySlides = asJsonList(data).map(StorySlide.fromJson).toList());
    } catch (_) {
      if (mounted) setState(() => _mySlides = const []);
    } finally {
      if (mounted) setState(() => _mySlidesLoading = false);
    }
  }

  void _resetEditor() {
    _editingSlideId = null;
    _editingOverlay = null;
    _editingFilterId = 'none';
    _imageSrc = null;
    _videoSrc = null;
    _videoFile = null;
    _originalImageFile = null;
    _textOnly = false;
    _caption.clear();
    _background = defaultStoryBackground;
  }

  void _goBack() {
    if (_step == 'edit') {
      setState(() {
        _resetEditor();
        _step = 'pick';
      });
      _loadMySlides();
    } else {
      context.go('/conversations');
    }
  }

  Future<void> _pickMedia() async {
    final file = await ImagePicker().pickMedia(imageQuality: 90);
    if (file == null || !mounted) return;
    final isVideo = (file.mimeType ?? '').startsWith('video/') || isVideoUrl(file.path);
    setState(() {
      _resetEditor();
      if (isVideo) {
        _videoFile = file.path;
        _videoSrc = file.path;
      } else {
        _imageSrc = file.path;
        _originalImageFile = file.path;
      }
      _step = 'edit';
    });
  }

  void _startTextStory() => setState(() {
        _resetEditor();
        _textOnly = true;
        _step = 'edit';
      });

  void _startEdit(StorySlide s) => setState(() {
        _resetEditor();
        _editingSlideId = s.id;
        _caption.text = s.caption ?? '';
        _editingFilterId = (s.filterId?.isNotEmpty ?? false) ? s.filterId! : 'none';
        _editingOverlay = (s.isText || s.isVideo || s.mediaUrl == null) ? s.overlayJson : null;
        if (s.isVideo && s.mediaUrl != null) {
          _videoSrc = s.mediaUrl;
        } else if (s.isText || (s.backgroundColor != null && s.mediaUrl == null)) {
          _textOnly = true;
          _background = s.backgroundColor ?? _background;
        } else if (s.mediaUrl != null) {
          _imageSrc = s.mediaUrl;
        } else {
          _textOnly = true;
        }
        _step = 'edit';
      });

  Future<void> _viewMyStory(StorySlide s) async {
    final uid = ref.read(authProvider).user?.id;
    if (uid == null) return;
    await context.push(Uri(path: '/stories/view/$uid', queryParameters: {'slideId': s.id, 'from': 'create'}).toString());
    if (mounted && _step == 'pick') _loadMySlides();
  }

  Future<void> _requestDelete(StorySlide s) async {
    final stories = ref.read(storiesProvider.notifier);
    await showStoryConfirm(
      context,
      message: t('stories.confirmDeleteSlide'),
      onConfirm: () async {
        await Api.delete('/stories/${s.id}');
        if (!mounted) return;
        setState(() => _mySlides = _mySlides.where((x) => x.id != s.id).toList());
        stories.invalidate();
        await stories.fetchFeed(force: true);
      },
    );
  }

  Future<void> _alert(String message) => showStoryAlert(context, message);

  String _errorMessage(Object e) {
    if (e is _ExportFailed) return t('stories.exportFailed');
    if (e is DioException && (e.response?.statusCode ?? 0) >= 500) return t('stories.publishFailed');
    return Api.errorMessage(e, t('common.error'));
  }

  Future<String?> _export({required bool required}) async {
    final file = await _editorKey.currentState?.exportImage();
    if (file == null && required) throw _ExportFailed();
    if (file == null) return null;
    return uploadFile('/media/upload-story-image', file.path, filename: 'story.jpg', timeout: mediaUploadTimeout);
  }

  Options get _publishOptions => Options(sendTimeout: storyPublishTimeout, receiveTimeout: storyPublishTimeout);

  Future<void> _publish() async {
    if (_publishing) return;
    FocusScope.of(context).unfocus();
    setState(() => _publishing = true);
    try {
      if (_editingSlideId != null) {
        await _saveEdit();
        return;
      }
      String? mediaUrl;
      var mediaType = 'image';

      if (_textOnly) {
        mediaUrl = await _export(required: true);
        mediaType = 'image';
      } else if (_videoFile != null) {
        mediaType = 'video';
        mediaUrl = await uploadFile('/media/upload-story-video', _videoFile!, timeout: mediaUploadTimeout);
      } else if (_imageSrc != null) {
        final useOriginal = _originalImageFile != null && !(_editorKey.currentState?.hasEditorChanges ?? false);
        mediaUrl = useOriginal
            ? await uploadFile('/media/upload-story-image', _originalImageFile!, timeout: mediaUploadTimeout)
            : await _export(required: true);
        mediaType = 'image';
      }

      final editor = _editorKey.currentState;
      final filterId = editor?.filterId ?? 'none';
      await Api.post(
        '/stories',
        {
          'mediaUrl': mediaUrl,
          'mediaType': mediaType,
          'caption': _caption.text.trim().isEmpty ? null : _caption.text.trim(),
          'overlayJson': editor?.overlayJson,
          'backgroundColor': _textOnly ? _background : null,
          'filterId': filterId == 'none' ? null : filterId,
          'videoDurationSeconds': editor?.videoDurationSeconds,
        },
        _publishOptions,
      );
      final stories = ref.read(storiesProvider.notifier);
      stories.invalidate();
      await stories.fetchFeed(force: true);
      if (mounted) context.go('/conversations');
    } catch (e) {
      if (mounted) _alert(_errorMessage(e));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _saveEdit() async {
    final slideId = _editingSlideId;
    if (slideId == null) return;
    final editor = _editorKey.currentState;
    final filterId = editor?.filterId ?? 'none';
    String? mediaUrl;
    if (_textOnly) {
      mediaUrl = await _export(required: true);
    } else if (_videoFile == null && _imageSrc != null) {
      mediaUrl = await _export(required: true);
    }
    final body = <String, dynamic>{
      'caption': _caption.text.trim().isEmpty ? null : _caption.text.trim(),
      'overlayJson': editor?.overlayJson,
      'backgroundColor': _textOnly ? _background : null,
      'filterId': filterId == 'none' ? null : filterId,
      'mediaUrl': ?mediaUrl,
    };
    await Api.dio.put('stories/$slideId', data: body, options: _publishOptions);
    final stories = ref.read(storiesProvider.notifier);
    stories.invalidate();
    await stories.fetchFeed(force: true);
    if (!mounted) return;
    setState(() {
      _resetEditor();
      _step = 'pick';
    });
    await _loadMySlides();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 'pick',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: _step == 'pick' ? _pickStep() : _editStep(),
    );
  }

  Widget _pickStep() {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ModernPage(
      title: t('stories.createTitle'),
      backTo: '/conversations',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            gradient: const LinearGradient(colors: [Color(0x1A2563EB), Color(0x1460A5FA)]),
            border: Border.all(color: const Color(0x1F2563EB)),
          ),
          child: Text(t('stories.pickSubtitle'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.55, color: c.textSecondary)),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _CreateTile(
              icon: LucideIcons.film,
              colors: const [Color(0xFF2563EB), Color(0xFF60A5FA)],
              title: t('stories.pickPhotoVideo'),
              desc: t('stories.pickPhotoVideoDesc'),
              chevron: rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
              onTap: _pickMedia,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _CreateTile(
              icon: LucideIcons.type,
              colors: const [Color(0xFF1D4ED8), Color(0xFF93C5FD)],
              title: t('stories.pickText'),
              desc: t('stories.pickTextDesc'),
              chevron: rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
              onTap: _startTextStory,
            ),
          ),
        ]),
        const SizedBox(height: 24),
        if (_mySlidesLoading || _mySlides.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Row(children: [
              Expanded(child: Text(t('stories.myActiveStories'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary))),
              if (!_mySlidesLoading && _mySlides.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0x1F2563EB), borderRadius: BorderRadius.circular(12)),
                  child: Text('${_mySlides.length}', style: TextStyle(color: c.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
          if (_mySlidesLoading)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: c.bgCard, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: c.border)),
              child: Text(t('common.loading'), textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.textMuted)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: c.border),
                boxShadow: [BoxShadow(color: c.shadow, blurRadius: 6)],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var i = 0; i < _mySlides.length; i++)
                    Padding(
                      padding: EdgeInsetsDirectional.only(end: i == _mySlides.length - 1 ? 0 : 12),
                      child: _MyStoryCard(
                        slide: _mySlides[i],
                        order: i + 1,
                        onView: () => _viewMyStory(_mySlides[i]),
                        onEdit: () => _startEdit(_mySlides[i]),
                        onDelete: () => _requestDelete(_mySlides[i]),
                      ),
                    ),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _editStep() {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: c.bgPrimary,
      resizeToAvoidBottomInset: true,
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, pad.top + 10, 16, 12),
          child: Row(children: [
            GlassIconButton(icon: rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft, onTap: _goBack),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_editingSlideId != null ? t('stories.editStory') : t('stories.createTitle'),
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
            ),
            const SizedBox(width: 10),
            Opacity(
              opacity: _publishing ? 0.9 : 1,
              child: Material(
                color: c.primary,
                shape: const CircleBorder(),
                elevation: 0,
                shadowColor: const Color(0x472563EB),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _publishing ? null : _publish,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: _publishing
                        ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(LucideIcons.send, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: StoryEditor(
            key: _editorKey,
            imageSrc: _imageSrc,
            videoSrc: _videoSrc,
            textOnly: _textOnly,
            backgroundColor: _background,
            initialFilterId: _editingFilterId,
            initialOverlayJson: _editingOverlay,
            onBackgroundChanged: (bg) => setState(() => _background = bg),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + pad.bottom),
          decoration: BoxDecoration(color: c.bgCard, border: Border(top: BorderSide(color: c.border))),
          child: TextField(
            controller: _caption,
            style: TextStyle(fontSize: 14, color: c.textPrimary),
            decoration: InputDecoration(
              hintText: t('stories.captionPlaceholder'),
              hintStyle: TextStyle(color: c.textMuted),
              filled: true,
              fillColor: c.bgElevated,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: c.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: c.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: c.primary)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CreateTile extends StatelessWidget {
  const _CreateTile({required this.icon, required this.colors, required this.title, required this.desc, required this.chevron, required this.onTap});
  final IconData icon;
  final List<Color> colors;
  final String title;
  final String desc;
  final IconData chevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: c.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 168),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                ),
                child: Icon(icon, size: 26, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.35, color: c.textPrimary)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 18),
                child: Text(desc, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.45, color: c.textSecondary)),
              ),
            ]),
            PositionedDirectional(bottom: 0, end: 0, child: Icon(chevron, size: 18, color: c.textMuted.withValues(alpha: 0.65))),
          ]),
        ),
      ),
    );
  }
}

class _MyStoryCard extends StatelessWidget {
  const _MyStoryCard({required this.slide, required this.order, required this.onView, required this.onEdit, required this.onDelete});
  final StorySlide slide;
  final int order;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final textLike = slide.isText || (slide.backgroundColor != null && slide.mediaUrl == null);
    Widget content;
    if (slide.mediaUrl != null && !slide.isText) {
      content = slide.isVideo
          ? VideoFramePoster(url: slide.mediaUrl!)
          : CachedNetworkImage(imageUrl: Api.absoluteUrl(slide.mediaUrl)!, fit: BoxFit.cover);
    } else {
      content = Stack(fit: StackFit.expand, children: [
        if (slide.caption?.isNotEmpty ?? false)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(slide.caption!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.35, shadows: [Shadow(color: Color(0x59000000), blurRadius: 3)])),
            ),
          )
        else if (firstOverlayText(slide.overlayJson) == null)
          const Center(
            child: Text('Aa', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, shadows: [Shadow(color: Color(0x40000000), blurRadius: 4)])),
          ),
        StoryOverlayLayer(overlayJson: slide.overlayJson),
      ]);
    }
    Widget badge(Widget child, {EdgeInsets padding = EdgeInsets.zero}) => Container(
          padding: padding,
          decoration: BoxDecoration(color: const Color(0x80000000), borderRadius: BorderRadius.circular(999)),
          child: child,
        );
    return SizedBox(
      width: 108,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          onTap: onView,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2563EB), Color(0xFF60A5FA)]),
            ),
            child: AspectRatio(
              aspectRatio: 9 / 14,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: (textLike
                        ? storyBackgroundDecoration(slide.backgroundColor ?? 'linear-gradient(160deg,#2563eb,#60a5fa)', radius: BorderRadius.circular(14))
                        : BoxDecoration(color: c.bgElevated, borderRadius: BorderRadius.circular(14)))
                    .copyWith(border: Border.all(color: c.bgCard, width: 2)),
                child: Stack(fit: StackFit.expand, children: [
                  content,
                  PositionedDirectional(
                    top: 6,
                    start: 6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: const Color(0x8C0F172A), borderRadius: BorderRadius.circular(999)),
                      child: Text('$order', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1)),
                    ),
                  ),
                  if (slide.isVideo)
                    PositionedDirectional(
                      bottom: 6,
                      start: 6,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(color: Color(0x73000000), shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  if (slide.viewCount > 0)
                    PositionedDirectional(
                      bottom: 6,
                      end: 6,
                      child: badge(
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(LucideIcons.eye, size: 10, color: Colors.white),
                          const SizedBox(width: 3),
                          Text('${slide.viewCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        ]),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _ActionBtn(icon: LucideIcons.pencil, color: c.primary, bg: c.bgElevated, border: c.border, onTap: onEdit)),
          const SizedBox(width: 6),
          Expanded(
            child: _ActionBtn(icon: LucideIcons.trash2, color: c.danger, bg: const Color(0x14F44336), border: const Color(0x33F44336), onTap: onDelete),
          ),
        ]),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.color, required this.bg, required this.border, required this.onTap});
  final IconData icon;
  final Color color;
  final Color bg;
  final Color border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(height: 34, child: Icon(icon, size: 14, color: color)),
        ),
      );
}
