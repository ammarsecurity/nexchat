import 'dart:convert';

import 'package:intl/intl.dart';

import 'i18n/i18n.dart';
import 'time.dart';

export 'time.dart' show asUtc, toIraq, iraqNow, parseApiDate, iraqOffset;

String _tag() => I18n.current == 'ar' ? 'ar' : 'en_US';

/// formatTime12() — `hh:mm AM/PM` in Iraq (UTC+3).
String formatTime12(DateTime d) => DateFormat('hh:mm a', _tag()).format(toIraq(d));

/// formatGregorianDateTime() — date + time in Iraq.
String formatGregorianDateTime(DateTime d) =>
    '${DateFormat('d/M/yyyy', _tag()).format(toIraq(d))} ${formatTime12(d)}';

/// Relative time used in the conversations list (UTC duration; absolute in Iraq).
String formatRelative(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().toUtc().difference(asUtc(d));
  if (diff.inSeconds < 60) return t('connectionHistory.now');
  if (diff.inMinutes < 60) return t('connectionHistory.minutesAgo', {'n': diff.inMinutes});
  if (diff.inHours < 24) return t('connectionHistory.hoursAgo', {'n': diff.inHours});
  return formatGregorianDateTime(d);
}

/// WhatsApp-style day label above a message group (Today / Yesterday / full date).
String formatChatDayLabel(DateTime? d) {
  if (d == null) return '';
  final iraq = toIraq(d);
  final now = iraqNow();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(iraq.year, iraq.month, iraq.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return t('conversationChat.today');
  if (diff == 1) return t('conversationChat.yesterday');
  return DateFormat('d MMMM yyyy', _tag()).format(iraq);
}

bool isSameChatDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) return false;
  final ia = toIraq(a);
  final ib = toIraq(b);
  return ia.year == ib.year && ia.month == ib.month && ia.day == ib.day;
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

// ---- location / file share ----

class LocationShare {
  const LocationShare({required this.lat, required this.lng, this.name, this.address});
  final double lat;
  final double lng;
  final String? name;
  final String? address;

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final a = address?.trim();
    if (a != null && a.isNotEmpty) return a;
    return t('conversationChat.locationMessage');
  }

  String get mapsUrl => 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  String get staticMapUrl =>
      'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng&zoom=16&size=600x280&maptype=mapnik&markers=$lat,$lng,red-pushpin';
}

class FileShare {
  const FileShare({required this.url, required this.name, this.size, this.contentType});
  final String url;
  final String name;
  final int? size;
  final String? contentType;

  String get ext {
    final i = name.lastIndexOf('.');
    return i >= 0 ? name.substring(i + 1).toLowerCase() : '';
  }
}

String buildLocationPayload({required double lat, required double lng, String? name, String? address}) {
  final map = <String, dynamic>{'lat': lat, 'lng': lng};
  if (name != null && name.trim().isNotEmpty) map['name'] = name.trim();
  if (address != null && address.trim().isNotEmpty) map['address'] = address.trim();
  return jsonEncode(map);
}

LocationShare? parseLocationMessage(String? type, String? content) {
  if (type != null && type != 'location') return null;
  final s = content?.trim() ?? '';
  if (!s.startsWith('{')) return null;
  try {
    final data = jsonDecode(s);
    if (data is! Map) return null;
    final lat = double.tryParse('${data['lat'] ?? data['latitude'] ?? ''}');
    final lng = double.tryParse('${data['lng'] ?? data['lon'] ?? data['longitude'] ?? ''}');
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LocationShare(
      lat: lat,
      lng: lng,
      name: '${data['name'] ?? data['Name'] ?? ''}'.trim().isEmpty ? null : '${data['name'] ?? data['Name']}'.trim(),
      address: '${data['address'] ?? data['Address'] ?? ''}'.trim().isEmpty ? null : '${data['address'] ?? data['Address']}'.trim(),
    );
  } catch (_) {
    return null;
  }
}

String buildFilePayload({required String url, required String name, int? size, String? contentType}) {
  final map = <String, dynamic>{'url': url, 'name': name};
  if (size != null && size > 0) map['size'] = size;
  if (contentType != null && contentType.isNotEmpty) map['contentType'] = contentType;
  return jsonEncode(map);
}

FileShare? parseFileMessage(String? type, String? content) {
  if (type != null && type != 'file') return null;
  final s = content?.trim() ?? '';
  if (!s.startsWith('{')) return null;
  try {
    final data = jsonDecode(s);
    if (data is! Map) return null;
    final url = '${data['url'] ?? data['Url'] ?? ''}'.trim();
    final name = '${data['name'] ?? data['Name'] ?? data['fileName'] ?? ''}'.trim();
    if (url.isEmpty || name.isEmpty) return null;
    final sizeRaw = data['size'] ?? data['Size'];
    final size = sizeRaw is int ? sizeRaw : int.tryParse('$sizeRaw');
    final ct = '${data['contentType'] ?? data['ContentType'] ?? ''}'.trim();
    return FileShare(url: url, name: name, size: size, contentType: ct.isEmpty ? null : ct);
  } catch (_) {
    return null;
  }
}

String formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';
}

String locationListPreview(String? content) {
  final loc = parseLocationMessage('location', content);
  if (loc == null) return '📍 ${t('conversationChat.locationMessage')}';
  final label = loc.displayName;
  final out = '📍 $label';
  return out.length > 50 ? '${out.substring(0, 50)}…' : out;
}

String fileListPreview(String? content) {
  final file = parseFileMessage('file', content);
  if (file == null) return '📎 ${t('conversationChat.fileMessage')}';
  final out = '📎 ${file.name}';
  return out.length > 50 ? '${out.substring(0, 50)}…' : out;
}

// ---- shortFilmShare.js ----
final _videoRe = RegExp(r'\.(mp4|mov|webm)(\?|$)', caseSensitive: false);
final _imageRe = RegExp(r'\.(jpg|jpeg|png|gif|webp)(\?|$)', caseSensitive: false);
final _audioRe = RegExp(r'\.(webm|m4a|ogg|opus|mp3|wav)(\?|$)', caseSensitive: false);
final shortFilmLinkRe = RegExp(r'short-films/watch\?start=([0-9a-f-]{36})', caseSensitive: false);

bool _isViewOncePreview(String? preview) {
  if (preview == null || preview.isEmpty) return false;
  final s = preview.trim();
  return s.contains('مشاهدة مرة') ||
      s.toLowerCase().contains('view once') ||
      s == t('conversationChat.viewOncePhoto') ||
      s == t('conversationChat.viewOnceVideo');
}

String? _previewFromType(String? type, String? preview) {
  switch (type) {
    case 'video':
      if (_isViewOncePreview(preview)) return preview;
      return t('conversationChat.videoMessage');
    case 'image':
      if (_isViewOncePreview(preview)) return preview;
      return t('conversationChat.replyPreviewImage');
    case 'audio':
      return t('conversationChat.voiceMessage');
    case 'album':
      return albumListPreviewLabel(preview, preview);
    case 'short_film':
      if (preview == null || preview.isEmpty) return '🎬 ${t('shortFilms.title')}';
      // Do not recurse via formatConversationListPreview(..., type: short_film).
      if (!preview.trim().startsWith('{')) {
        return preview.startsWith('🎬') ? preview : '🎬 $preview';
      }
      try {
        final data = jsonDecode(preview);
        if (data is Map) {
          final title = '${data['title'] ?? data['Title'] ?? ''}'.trim();
          final out = '🎬 ${title.isEmpty ? t('shortFilms.title') : title}';
          return out.length > 50 ? '${out.substring(0, 50)}…' : out;
        }
      } catch (_) {}
      return '🎬 ${t('shortFilms.title')}';
    case 'story_share':
      if (preview != null && preview.isNotEmpty && !preview.trim().startsWith('{')) return preview;
      return parseStoryShareMessage('story_share', preview ?? '')?.listPreview ?? t('share.storySharePreview');
    case 'story_reply':
      return parseStoryReplyMessage('story_reply', preview ?? '')?.listPreview ?? t('stories.storyReplyPreview');
    case 'call':
      if (preview != null && preview.isNotEmpty && !preview.trim().startsWith('{')) return preview;
      return formatCallMessagePreview(preview, mine: false);
    case 'location':
      if (preview != null && preview.isNotEmpty && !preview.trim().startsWith('{')) return preview;
      return locationListPreview(preview);
    case 'file':
      if (preview != null && preview.isNotEmpty && !preview.trim().startsWith('{')) return preview;
      return fileListPreview(preview);
  }
  return null;
}

/// WhatsApp-style call history label for list + bubbles.
String formatCallMessagePreview(String? content, {required bool mine}) {
  Map<String, dynamic>? data;
  if (content != null && content.trim().startsWith('{')) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  final status = '${data?['status'] ?? 'missed'}';
  final voiceOnly = data?['voiceOnly'] == true || data?['voiceOnly'] == 'true';
  final durationSec = int.tryParse('${data?['durationSec'] ?? 0}') ?? 0;
  final kind = voiceOnly ? t('conversationChat.voiceCallKind') : t('conversationChat.videoCallKind');
  switch (status) {
    case 'ended':
      final time = durationSec > 0 ? ' · ${_fmtCallDur(durationSec)}' : '';
      return mine ? '${t('conversationChat.outgoingCall')} ($kind)$time' : '${t('conversationChat.incomingCall')} ($kind)$time';
    case 'cancelled':
      return mine ? '${t('conversationChat.cancelledCall')} ($kind)' : '${t('conversationChat.missedCall')} ($kind)';
    case 'declined':
      return mine ? '${t('conversationChat.declinedCall')} ($kind)' : '${t('conversationChat.missedCall')} ($kind)';
    case 'busy':
      return mine ? t('conversationChat.userBusy') : '${t('conversationChat.missedCall')} ($kind)';
    case 'missed':
    default:
      return mine ? '${t('conversationChat.noAnswerCall')} ($kind)' : '${t('conversationChat.missedCall')} ($kind)';
  }
}

String _fmtCallDur(int sec) {
  final m = (sec ~/ 60).toString().padLeft(2, '0');
  final s = (sec % 60).toString().padLeft(2, '0');
  return '$m:$s';
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
  if (s.startsWith('🎬') || s.startsWith('📍') || s.startsWith('📎') || s.startsWith('◌')) return s;
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

String buildStoryShareContent({
  required String userId,
  String? slideId,
  required String name,
  String? mediaUrl,
  String mediaType = 'image',
  String? caption,
  String? backgroundColor,
}) =>
    jsonEncode({
      'userId': userId,
      if (slideId != null && slideId.isNotEmpty) 'slideId': slideId,
      'name': name,
      if (mediaUrl != null && mediaUrl.isNotEmpty) 'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      if (caption != null && caption.isNotEmpty) 'caption': caption,
      if (backgroundColor != null && backgroundColor.isNotEmpty) 'backgroundColor': backgroundColor,
    });

class StoryShareRef {
  const StoryShareRef({
    required this.userId,
    required this.name,
    this.slideId,
    this.mediaUrl,
    this.mediaType = 'image',
    this.caption,
    this.backgroundColor,
  });

  final String userId;
  final String name;
  final String? slideId;
  final String? mediaUrl;
  final String mediaType;
  final String? caption;
  final String? backgroundColor;

  bool get isVideo =>
      mediaType == 'video' || (mediaUrl != null && _videoRe.hasMatch(mediaUrl!.toLowerCase()));
  bool get isText => mediaType == 'text' || mediaUrl == null || mediaUrl!.isEmpty;

  String get listPreview {
    final n = name.trim();
    if (n.isEmpty) return t('share.storySharePreview');
    final out = '◌ ${t('share.storyShareOf', {'name': n})}';
    return out.length > 50 ? '${out.substring(0, 50)}…' : out;
  }
}

StoryShareRef? parseStoryShareMessage(String type, String content) {
  if (type != 'story_share' || content.isEmpty || !content.trim().startsWith('{')) return null;
  try {
    final data = jsonDecode(content);
    if (data is! Map) return null;
    final userId = '${data['userId'] ?? data['UserId'] ?? ''}'.trim();
    if (userId.isEmpty) return null;
    final name = '${data['name'] ?? data['Name'] ?? ''}'.trim();
    return StoryShareRef(
      userId: userId,
      name: name.isEmpty ? t('stories.allStory') : name,
      slideId: data['slideId']?.toString() ?? data['SlideId']?.toString(),
      mediaUrl: (data['mediaUrl'] ?? data['MediaUrl']) as String?,
      mediaType: '${data['mediaType'] ?? data['MediaType'] ?? 'image'}'.toLowerCase(),
      caption: (data['caption'] ?? data['Caption']) as String?,
      backgroundColor: (data['backgroundColor'] ?? data['BackgroundColor']) as String?,
    );
  } catch (_) {
    return null;
  }
}

class StoryReplyRef {
  const StoryReplyRef({
    required this.text,
    this.slideId,
    this.mediaUrl,
    this.mediaType = 'image',
    this.backgroundColor,
    this.caption,
  });

  final String text;
  final String? slideId;
  final String? mediaUrl;
  final String mediaType;
  final String? backgroundColor;
  final String? caption;

  bool get isVideo =>
      mediaType == 'video' ||
      (mediaUrl != null && _videoRe.hasMatch(mediaUrl!.toLowerCase()));
  bool get isText => mediaType == 'text' || mediaUrl == null || mediaUrl!.isEmpty;

  String get listPreview {
    final t0 = text.trim();
    if (t0.isEmpty) return t('stories.storyReplyPreview');
    final out = '↩ $t0';
    return out.length > 50 ? '${out.substring(0, 50)}…' : out;
  }
}

StoryReplyRef? parseStoryReplyMessage(String type, String content) {
  if (type != 'story_reply' || content.isEmpty || !content.trim().startsWith('{')) return null;
  try {
    final data = jsonDecode(content);
    if (data is! Map) return null;
    final text = '${data['text'] ?? data['Text'] ?? ''}'.trim();
    return StoryReplyRef(
      text: text,
      slideId: data['slideId']?.toString() ?? data['SlideId']?.toString(),
      mediaUrl: (data['mediaUrl'] ?? data['MediaUrl']) as String?,
      mediaType: '${data['mediaType'] ?? data['MediaType'] ?? 'image'}'.toLowerCase(),
      backgroundColor: (data['backgroundColor'] ?? data['BackgroundColor']) as String?,
      caption: (data['caption'] ?? data['Caption']) as String?,
    );
  } catch (_) {
    return null;
  }
}
