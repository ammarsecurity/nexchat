import 'dart:convert';

import 'package:intl/intl.dart';

import 'i18n/i18n.dart';

String _tag() => I18n.current == 'ar' ? 'ar' : 'en_US';

/// formatTime12() — `hh:mm AM/PM` in the current locale.
String formatTime12(DateTime d) => DateFormat('hh:mm a', _tag()).format(d);

/// formatGregorianDateTime()
String formatGregorianDateTime(DateTime d) => '${DateFormat('d/M/yyyy', _tag()).format(d)} ${formatTime12(d)}';

/// Relative time used in the conversations list.
String formatRelative(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return t('connectionHistory.now');
  if (diff.inMinutes < 60) return t('connectionHistory.minutesAgo', {'n': diff.inMinutes});
  if (diff.inHours < 24) return t('connectionHistory.hoursAgo', {'n': diff.inHours});
  return formatGregorianDateTime(d);
}

// ---- conversationAlbum.js ----
const maxAlbumImages = 10;

String buildAlbumPayload(List<String> urls) => jsonEncode({'urls': urls.where((u) => u.isNotEmpty).take(maxAlbumImages).toList()});

List<String>? parseAlbumMessage(String? content) {
  final s = content?.trim() ?? '';
  if (!s.startsWith('{')) return null;
  try {
    final data = jsonDecode(s);
    final raw = data is Map ? (data['urls'] ?? data['Urls']) : null;
    if (raw is! List || raw.isEmpty) return null;
    final urls = raw.map((e) => '$e').where((e) => e.isNotEmpty).take(maxAlbumImages).toList();
    return urls.isEmpty ? null : urls;
  } catch (_) {
    return null;
  }
}

String albumListPreviewLabel(String? content, String? previewText) {
  final album = parseAlbumMessage(content ?? previewText);
  if (album != null) {
    return album.length == 1 ? t('conversationChat.replyPreviewImage') : t('conversationChat.albumPhotoCount', {'n': album.length});
  }
  final m = RegExp(r'^(\d+)\s*صور$').firstMatch(previewText ?? '');
  if (m != null) return t('conversationChat.albumPhotoCount', {'n': int.parse(m.group(1)!)});
  if (previewText == 'صورة') return t('conversationChat.replyPreviewImage');
  return t('conversationChat.albumMessage');
}

// ---- shortFilmShare.js ----
final _videoRe = RegExp(r'\.(mp4|mov|webm)(\?|$)', caseSensitive: false);
final _imageRe = RegExp(r'\.(jpg|jpeg|png|gif|webp)(\?|$)', caseSensitive: false);
final _audioRe = RegExp(r'\.(webm|m4a|ogg|opus|mp3|wav)(\?|$)', caseSensitive: false);
final shortFilmLinkRe = RegExp(r'short-films/watch\?start=([0-9a-f-]{36})', caseSensitive: false);

String? _previewFromType(String? type, String? preview) {
  switch (type) {
    case 'video':
      return t('conversationChat.videoMessage');
    case 'image':
      return t('conversationChat.replyPreviewImage');
    case 'audio':
      return t('conversationChat.voiceMessage');
    case 'album':
      return albumListPreviewLabel(preview, preview);
    case 'short_film':
      if (preview == null || preview.isEmpty) return '🎬 ${t('shortFilms.title')}';
      return formatConversationListPreview(preview);
  }
  return null;
}

String formatConversationListPreview(String? preview, {String? type}) {
  final byType = _previewFromType(type, preview);
  if (byType != null) return byType;
  if (preview == null || preview.isEmpty) return '';
  final s = preview.trim();
  if (s == 'فيديو' || s.toLowerCase() == 'video') return t('conversationChat.videoMessage');
  if (s == 'صورة' || s == 'image') return t('conversationChat.replyPreviewImage');
  if (s == 'رسالة صوتية') return t('conversationChat.voiceMessage');
  if (s == 'ألبوم صور' || RegExp(r'^\d+ صور$').hasMatch(s)) return albumListPreviewLabel(null, s);
  final lower = s.toLowerCase();
  if (_videoRe.hasMatch(lower) || (lower.contains('/uploads/') && lower.contains('.mp4'))) return t('conversationChat.videoMessage');
  if (_audioRe.hasMatch(lower)) return t('conversationChat.voiceMessage');
  if (_imageRe.hasMatch(lower) && type != 'album') return t('conversationChat.replyPreviewImage');
  if (s.startsWith('🎬')) return s;
  if (!s.startsWith('{')) return preview;
  if (parseAlbumMessage(s) != null) return albumListPreviewLabel(s, s);
  try {
    final data = jsonDecode(s);
    final id = data is Map ? (data['id'] ?? data['Id']) : null;
    if (id == null) return preview;
    final title = '${data['title'] ?? data['Title'] ?? ''}'.trim();
    final out = '🎬 ${title.isEmpty ? t('shortFilms.title') : title}';
    return out.length > 50 ? '${out.substring(0, 50)}…' : out;
  } catch (_) {
    return preview;
  }
}

class ShortFilmRef {
  const ShortFilmRef(this.id, this.title, this.thumbnailUrl);
  final String id;
  final String title;
  final String? thumbnailUrl;
}

ShortFilmRef? parseShortFilmMessage(String type, String content) {
  if (type == 'short_film') {
    try {
      final data = jsonDecode(content);
      final id = data['id'] ?? data['Id'];
      if (id == null) return null;
      return ShortFilmRef('$id', '${data['title'] ?? data['Title'] ?? ''}', (data['thumbnailUrl'] ?? data['ThumbnailUrl']) as String?);
    } catch (_) {
      return null;
    }
  }
  if (type != 'text' || content.isEmpty) return null;
  final m = shortFilmLinkRe.firstMatch(content);
  if (m == null) return null;
  final titleLine = content.split('\n').firstWhere((l) => l.trim().isNotEmpty && !l.contains('short-films/watch'), orElse: () => '');
  return ShortFilmRef(m.group(1)!, titleLine.replaceFirst(RegExp(r'^🎬\s*'), '').trim(), null);
}

String buildShortFilmShareContent(String id, String title, String? thumbnailUrl) =>
    jsonEncode({'id': id, 'title': title, 'thumbnailUrl': thumbnailUrl});
