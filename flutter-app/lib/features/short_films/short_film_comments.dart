import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets.dart';

class FilmComment {
  const FilmComment({
    required this.id,
    required this.filmId,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.body,
    required this.isMine,
    required this.createdAt,
  });

  final String id;
  final String filmId;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String body;
  final bool isMine;
  final DateTime? createdAt;

  factory FilmComment.fromJson(Map m) => FilmComment(
        id: m.str('id'),
        filmId: m.str('shortFilmId'),
        userId: m.str('userId'),
        userName: m.str('userName'),
        userAvatar: m.s('userAvatar'),
        body: m.str('body'),
        isMine: m.b('isMine'),
        createdAt: m.date('createdAt'),
      );
}

class ShortFilmCommentsApi {
  ShortFilmCommentsApi._();
  static final instance = ShortFilmCommentsApi._();

  Future<({List<FilmComment> items, int total, bool hasMore})> list(String filmId, {int page = 1}) async {
    final data = await Api.get('/short-films/films/$filmId/comments', query: {'page': page, 'pageSize': 20});
    final m = data is Map ? data : const {};
    return (
      items: asJsonList(m.v('items')).map(FilmComment.fromJson).toList(),
      total: m.i('total'),
      hasMore: m.b('hasMore'),
    );
  }

  Future<FilmComment> create(String filmId, String body) async {
    final data = await Api.post('/short-films/films/$filmId/comments', {'body': body});
    if (data is! Map) throw StateError('bad_response');
    return FilmComment.fromJson(data);
  }

  Future<void> delete(String commentId) => Api.delete('/short-films/comments/$commentId');

  Future<void> report(String commentId, {String? reason}) =>
      Api.post('/short-films/comments/$commentId/report', {'reason': reason});
}

Future<int?> openShortFilmCommentsSheet(BuildContext context, {required String filmId, int initialCount = 0}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: context.colors.bgCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _CommentsSheet(filmId: filmId, initialCount: initialCount),
  );
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.filmId, required this.initialCount});
  final String filmId;
  final int initialCount;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _items = <FilmComment>[];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _total = widget.initialCount;
    _scroll.addListener(_onScroll);
    Future.microtask(_reload);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_hasMore) return;
    if (_scroll.position.extentAfter < 120) _loadMore();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _page = 1;
    });
    try {
      final page = await ShortFilmCommentsApi.instance.list(widget.filmId, page: 1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _total = page.total;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final page = await ShortFilmCommentsApi.instance.list(widget.filmId, page: next);
      if (!mounted) return;
      setState(() {
        _page = next;
        _items.addAll(page.items);
        _hasMore = page.hasMore;
        _total = page.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final row = await ShortFilmCommentsApi.instance.create(widget.filmId, body);
      if (!mounted) return;
      _text.clear();
      setState(() {
        _items.insert(0, row);
        _total += 1;
        _sending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showToast(context, t('shortFilms.commentFailed'), error: true);
    }
  }

  Future<void> _delete(FilmComment c) async {
    final ok = await confirmDialog(
      context,
      title: t('shortFilms.deleteComment'),
      message: t('shortFilms.deleteCommentConfirm'),
      confirm: t('common.delete'),
      cancel: t('common.cancel'),
      danger: true,
    );
    if (!ok) return;
    try {
      await ShortFilmCommentsApi.instance.delete(c.id);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((x) => x.id == c.id);
        _total = (_total - 1).clamp(0, 1 << 30);
      });
    } catch (_) {
      if (mounted) showToast(context, t('common.error'), error: true);
    }
  }

  Future<void> _report(FilmComment c) async {
    try {
      await ShortFilmCommentsApi.instance.report(c.id);
      if (mounted) showToast(context, t('shortFilms.commentReported'));
    } catch (_) {
      if (mounted) showToast(context, t('common.error'), error: true);
    }
  }

  void _openMenu(FilmComment c) {
    showAppSheet<void>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        if (c.isMine)
          SheetAction(
            icon: LucideIcons.trash2,
            label: t('shortFilms.deleteComment'),
            danger: true,
            onTap: () {
              Navigator.pop(ctx);
              _delete(c);
            },
          )
        else
          SheetAction(
            icon: LucideIcons.flag,
            label: t('shortFilms.reportComment'),
            danger: true,
            onTap: () {
              Navigator.pop(ctx);
              _report(c);
            },
          ),
        const SizedBox(height: 8),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.72;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: c.textMuted.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(99)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Text(
                    t('shortFilms.comments'),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.textPrimary),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.primarySoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$_total',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.primary),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context, _total),
                    icon: Icon(LucideIcons.x, size: 20, color: c.textMuted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: c.primary))
                  : _items.isEmpty
                      ? EmptyState(icon: LucideIcons.messageCircle, text: t('shortFilms.emptyComments'))
                      : ListView.separated(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount: _items.length + (_loadingMore ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            if (i >= _items.length) {
                              return const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            final row = _items[i];
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                UserAvatar(url: row.userAvatar, name: row.userName, size: 36),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              row.userName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: c.textPrimary,
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () => _openMenu(row),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(LucideIcons.ellipsis, size: 16, color: c.textMuted),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        row.body,
                                        style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(
                color: c.bgCard,
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 300,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: TextStyle(color: c.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: t('shortFilms.commentPlaceholder'),
                        hintStyle: TextStyle(color: c.textMuted),
                        filled: true,
                        fillColor: c.bgElevated,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: c.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: c.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: c.primary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _sending ? null : _send,
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(LucideIcons.send, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
