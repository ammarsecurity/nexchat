import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'config/env.dart';
import 'i18n/i18n.dart';

/// Mirrors mobile-app/src/utils/shareLinks.js + shareExternal.js.
String normalizeInviteCode(String? code) {
  if (code == null) return '';
  final c = code.trim().toUpperCase();
  if (!c.startsWith('NX-')) return '';
  return c.length == 7 ? c : '';
}

String buildInvitePath(String? code) {
  final n = normalizeInviteCode(code);
  return n.isEmpty ? '/home' : '/join/${Uri.encodeComponent(n)}';
}

String buildInviteWebUrl(String? code) {
  final n = normalizeInviteCode(code);
  if (n.isEmpty) return Env.publicAppUrl;
  return '${Env.apiHost}/join/${Uri.encodeComponent(n)}';
}

String buildShortFilmShareUrl(String? filmId) {
  final id = (filmId ?? '').trim();
  if (id.isEmpty) return '${Env.publicAppUrl}/#/short-films';
  return '${Env.apiHost}/share/film/${Uri.encodeComponent(id)}';
}

String buildStoryShareUrl(String? userId) {
  final id = (userId ?? '').trim();
  if (id.isEmpty) return '${Env.publicAppUrl}/#/conversations';
  return '${Env.apiHost}/share/story/${Uri.encodeComponent(id)}';
}

sealed class ShareTarget {
  const ShareTarget();
}

class InviteTarget extends ShareTarget {
  const InviteTarget(this.code);
  final String code;
}

class ShortFilmTarget extends ShareTarget {
  const ShortFilmTarget(this.filmId);
  final String filmId;
}

class StoryTarget extends ShareTarget {
  const StoryTarget(this.userId);
  final String userId;
}

ShareTarget? parseShareTargetFromUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  Uri url;
  try {
    url = Uri.parse(raw.replaceFirst(RegExp(r'^nexchat://', caseSensitive: false), 'https://nexchat.app/'));
  } catch (_) {
    return null;
  }
  final fragment = url.fragment;
  final hashPath = fragment.split('?').first;
  final path = url.path + hashPath;
  final hashParams = fragment.contains('?') ? Uri.splitQueryString(fragment.substring(fragment.indexOf('?') + 1)) : const <String, String>{};

  final join = RegExp(r'/join/([A-Za-z0-9-]+)', caseSensitive: false).firstMatch(path);
  if (join != null) {
    final code = normalizeInviteCode(join.group(1));
    if (code.isNotEmpty) return InviteTarget(code);
  } else {
    final code = normalizeInviteCode(url.queryParameters['code'] ?? url.queryParameters['invite']);
    if (code.isNotEmpty) return InviteTarget(code);
  }

  final film = RegExp(r'/share/film/([0-9a-f-]{36})', caseSensitive: false).firstMatch(path);
  if (film != null) return ShortFilmTarget(film.group(1)!);
  if (path.contains('/short-films/watch')) {
    final id = url.queryParameters['start'] ?? hashParams['start'];
    if (id != null && id.isNotEmpty) return ShortFilmTarget(id);
  }

  final story = RegExp(r'/share/story/([0-9a-f-]{36})', caseSensitive: false).firstMatch(path) ??
      RegExp(r'/stories/view/([0-9a-f-]{36})', caseSensitive: false).firstMatch(path);
  if (story != null) return StoryTarget(story.group(1)!);
  return null;
}

/// Opens the native share sheet; falls back to the clipboard. Returns a toast message (or null).
Future<String?> shareTextPayload({String? title, required String text}) async {
  if (text.trim().isEmpty) return null;
  try {
    final r = await SharePlus.instance.share(ShareParams(text: text, subject: title, title: title));
    return r.status == ShareResultStatus.success ? t('share.shareOpened') : null;
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    return t('share.linkCopied');
  }
}

Future<String?> shareInviteCode(String? code, {String? inviterName}) async {
  final n = normalizeInviteCode(code);
  if (n.isEmpty) return null;
  final link = buildInviteWebUrl(n);
  return shareTextPayload(
    title: t('share.inviteTitle'),
    text: t('share.inviteMessage', {'code': n, 'name': inviterName ?? 'NexChat', 'link': link}),
  );
}

Future<String?> shareShortFilmPublic(String filmId, {String? title}) async {
  final link = buildShortFilmShareUrl(filmId);
  final name = (title?.isNotEmpty ?? false) ? title! : t('shortFilms.title');
  return shareTextPayload(title: name, text: t('shortFilms.shareMessage', {'title': name, 'link': link}));
}

Future<String?> shareStoryPublic(String userId, {String? publisherName}) async {
  final link = buildStoryShareUrl(userId);
  final name = (publisherName?.isNotEmpty ?? false) ? publisherName! : t('stories.allStory');
  return shareTextPayload(title: t('share.storyTitle', {'name': name}), text: t('share.storyMessage', {'name': name, 'link': link}));
}
