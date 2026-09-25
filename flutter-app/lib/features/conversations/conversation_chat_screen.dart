import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import '../../core/network/network_status.dart';
import '../../core/storage/prefs.dart';
import '../../core/theme/app_colors.dart';
import '../../services/media.dart';
import '../../services/ring_sound.dart';
import '../../shared/media_widgets.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../calls/active_call_bar.dart';
import '../calls/call_state.dart';
import '../calls/incoming_call_dialog.dart';
import '../calls/video_call_screen.dart';
import '../calls/whatsapp_call_ui.dart';
import '../stories/stories_controller.dart';
import 'active_conversation.dart';
import 'conversations_list_controller.dart';

const reactionEmojis = ['❤️', '👍', '😂', '😮', '😢', '🙏'];

Json normalizeMsg(Map<dynamic, dynamic> m) => {
      'id': m.s('id'),
      'senderId': m.s('senderId'),
      'content': m.s('content'),
      'type': m.s('type') ?? 'text',
      'sentAt': m.s('sentAt'),
      'deletedForEveryone': m.b('deletedForEveryone'),
      'isRead': m.b('isRead'),
      'replyToMessageId': m.s('replyToMessageId'),
      'replyToContent': m.s('replyToContent'),
      'replyToSenderName': m.s('replyToSenderName'),
      'replyToType': m.s('replyToType'),
      'senderName': m.s('senderName'),
      'senderAvatar': m.s('senderAvatar'),
      'reactions': m.v('reactions') ?? const [],
      'myReaction': m.s('myReaction'),
    };

String msgKey(Json m) => '${m['tempId'] ?? m['id']}';

String replyPreviewText(String? content, String? type) {
  if (type == 'video') return t('conversationChat.replyPreviewVideo');
  if (type == 'album') return t('conversationChat.replyPreviewAlbum');
  if (type == 'audio') return t('conversationChat.voiceMessage');
  if (type == 'image') return t('conversationChat.replyPreviewImage');
  if (type == 'story_reply') return parseStoryReplyMessage('story_reply', content ?? '')?.listPreview ?? t('stories.storyReplyPreview');
  if (type == 'call') return formatCallMessagePreview(content, mine: false);
  if (content == null || content.isEmpty) return '';
  if (parseAlbumMessage(content) != null) return t('conversationChat.replyPreviewAlbum');
  final lower = content.toLowerCase();
  if (RegExp(r'\.(webm|m4a|ogg|opus|mp3|wav)(\?|$)').hasMatch(lower)) return t('conversationChat.voiceMessage');
  if (RegExp(r'\.(mp4|mov)(\?|$)').hasMatch(lower)) return t('conversationChat.replyPreviewVideo');
  if (RegExp(r'\.(jpg|jpeg|png|gif|webp)(\?|$)').hasMatch(lower)) return t('conversationChat.replyPreviewImage');
  return content;
}

final _joinCounts = <String, int>{};
Object? _storeOwner;

/// views/ConversationChatView.vue
class ConversationChatScreen extends ConsumerStatefulWidget {
  const ConversationChatScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<ConversationChatScreen> createState() => _ConversationChatScreenState();
}

class _ConversationChatScreenState extends ConsumerState<ConversationChatScreen> with WidgetsBindingObserver {
  String get _cid => widget.conversationId;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _disposers = <void Function()>[];
  StreamSubscription<void>? _reconnectSub;
  Timer? _typingTimer;
  Timer? _markReadTimer;
  Timer? _markReadInterval;
  Timer? _saveTimer;
  bool _loading = true;
  bool _uploadingImage = false, _uploadingVideo = false, _uploadingAlbum = false, _uploadingVoice = false;
  Json? _replyingTo;
  Map<String, Json> _groupSenders = {};
  String? _highlighted;
  final _keys = <String, GlobalKey>{};
  bool _callingOut = false;
  bool _callingVoiceOnly = false;
  /// `calling` = جاري الاتصال · `ringing` = يرن عنده
  String _callPhase = 'calling';
  bool _callDeclined = false;
  bool _callBusy = false;
  Timer? _outgoingRing;
  bool _hasMore = true;
  bool _loadingOlder = false;
  bool _showJumpFab = false;
  int _unreadWhileAway = 0;
  bool _flushingOutbox = false;
  Timer? _typingExpire;

  final _recorder = AudioRecorder();
  bool _recording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  final _pendingAudio = <String, String>{};

  late final ActiveConversationController _store;

  String get _me => ref.read(authProvider).user?.id ?? '';
  bool get _uploading => _uploadingImage || _uploadingVideo || _uploadingAlbum || _uploadingVoice;
  bool get _ownsStore => identical(_storeOwner, this);

  @override
  void initState() {
    super.initState();
    _store = ref.read(activeConversationProvider.notifier);
    _storeOwner = this;
    _joinCounts.update(_cid, (n) => n + 1, ifAbsent: () => 1);
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_init);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _markRead();
  }

  String get _cacheKey => 'nexchat_msgs_$_cid';
  String get _outboxKey => 'nexchat_outbox_$_cid';

  void _saveDebounced() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      final active = ref.read(activeConversationProvider);
      if (active.conversationId != _cid) return;
      final list = active.messages.where((m) => m['status'] != 'pending' && m['status'] != 'failed').toList();
      final tail = list.length > 150 ? list.sublist(list.length - 150) : list;
      Prefs.instance.setString(_cacheKey, jsonEncode(tail));
      _persistOutbox();
    });
  }

  void _persistOutbox() {
    final active = ref.read(activeConversationProvider);
    if (active.conversationId != _cid) return;
    final pending = active.messages
        .where((m) => (m['status'] == 'pending' || m['status'] == 'failed') && (m.s('type') ?? 'text') == 'text')
        .toList();
    Prefs.instance.setString(_outboxKey, pending.isEmpty ? null : jsonEncode(pending));
  }

  List<Json> _readOutbox() {
    try {
      return asJsonList(jsonDecode(Prefs.instance.getString(_outboxKey) ?? '[]'));
    } catch (_) {
      return [];
    }
  }

  Future<void> _init() async {
    final fromList = ref.read(conversationsListProvider).where((c) => c.str('id') == _cid).firstOrNull;
    Json? partner = fromList == null
        ? null
        : {
            'id': fromList.s('partnerId'),
            'name': fromList.s('partnerName'),
            'avatar': fromList.s('partnerAvatar'),
            'isOnline': fromList.b('partnerIsOnline'),
          };
    var isGroup = fromList?.b('isGroup') ?? false;
    if (fromList == null && ref.read(networkProvider)) {
      try {
        final data = await Api.get('/conversations/$_cid') as Map;
        if (data.s('type') == 'group') {
          isGroup = true;
          partner = {'id': _cid, 'name': data.s('groupName') ?? 'مجموعة', 'avatar': data.s('groupImageUrl')};
        } else if (data.s('partnerId') != null) {
          partner = {'id': data.s('partnerId'), 'name': data.s('partnerName') ?? '', 'avatar': data.s('partnerAvatar'), 'isOnline': data.b('partnerIsOnline')};
        }
      } catch (_) {}
    }
    if (!mounted || !_ownsStore) return;
    _store.setConversation(_cid, partner, isGroup: isGroup);
    if (isGroup && ref.read(networkProvider)) _fetchGroupSenders();

    final cached = Prefs.instance.getString(_cacheKey);
    if (cached != null) {
      try {
        final msgs = asJsonList(jsonDecode(cached));
        final outbox = _readOutbox();
        final ids = msgs.map((m) => m['tempId'] ?? m['id']).toSet();
        final merged = [...msgs, ...outbox.where((m) => !ids.contains(m['tempId'] ?? m['id']))];
        _store.setMessages(merged);
        _scrollToBottom(force: true);
      } catch (_) {}
    }
    setState(() => _loading = false);
    _scroll.addListener(_onScroll);

    final h = Hubs.conversation;
    _disposers.addAll([
      h.on('ConversationListUpdated', (a) => _onListUpdated(a.firstOrNull)),
      h.on('ReceiveMessage', (a) => _onReceive(a.firstOrNull)),
      h.on('UserTyping', (_) {
        _store.setTyping(true);
        _typingExpire?.cancel();
        _typingExpire = Timer(const Duration(seconds: 3), () => _store.setTyping(false));
      }),
      h.on('UserStoppedTyping', (_) {
        _typingExpire?.cancel();
        _store.setTyping(false);
      }),
      h.on('MessageDeletedForMe', (a) => _store.removeMessage('${a.firstOrNull}')),
      h.on('MessageDeletedForEveryone', (a) => _store.setDeletedForEveryone('${a.firstOrNull}')),
      h.on('ConversationDeletedForMe', (_) {
        ref.read(conversationsListProvider.notifier).removeConversation(_cid);
        Prefs.instance.setString(_cacheKey, null);
        Prefs.instance.setString(_outboxKey, null);
        if (mounted) context.go('/conversations');
      }),
      h.on('ConversationJoined', (a) => _onJoined(a.firstOrNull)),
      h.on('OlderMessages', (a) => _onOlderMessages(a.firstOrNull)),
      h.on('PartnerReadUpTo', (a) {
        final p = a.firstOrNull;
        if (p is! Map || p.str('readerId') == _me) return;
        final at = p.date('lastReadAt');
        if (at != null) _store.setPartnerLastReadAt(at);
      }),
      h.on('MessagesRead', (a) {
        final p = a.firstOrNull;
        final ids = p is Map ? p.v('messageIds') : null;
        if (ids is List && ids.isNotEmpty) _store.setMessagesRead(ids.map((e) => '$e'));
      }),
      h.on('Error', (a) {
        if ('${a.firstOrNull}'.contains('not found') && mounted) context.go('/conversations');
      }),
      h.on('ReactionUpdated', (a) {
        final p = a.firstOrNull;
        if (p is! Map) return;
        final mid = p.s('messageId');
        if (mid != null) {
          _store.updateReactions(mid, (p.v('reactions') as List?) ?? const []);
          _saveDebounced();
        }
      }),
      h.on('VideoCallDeclined', (a) {
        final cid = '${a.firstOrNull ?? ''}';
        if (cid.isNotEmpty && cid != _cid) return;
        if (!mounted) return;
        _stopOutgoingRingUi();
        if (ref.read(activeCallProvider).sessionId == _cid) {
          ref.read(activeCallProvider.notifier).clear();
        }
        setState(() {
          _callingOut = false;
          _callDeclined = true;
          _callBusy = false;
        });
        Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _callDeclined = false);
        });
      }),
      h.on('VideoCallBusy', (a) {
        final cid = '${a.firstOrNull ?? ''}';
        if (cid.isNotEmpty && cid != _cid) return;
        if (!mounted) return;
        _stopOutgoingRingUi();
        if (ref.read(activeCallProvider).sessionId == _cid) {
          ref.read(activeCallProvider.notifier).clear();
        }
        setState(() {
          _callingOut = false;
          _callDeclined = false;
          _callBusy = true;
        });
        Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _callBusy = false);
        });
      }),
      h.on('VideoCallRinging', (a) {
        final cid = '${a.firstOrNull ?? ''}';
        if (cid.isNotEmpty && cid != _cid) return;
        if (!mounted || !_callingOut) return;
        if (_callPhase == 'ringing') return;
        setState(() => _callPhase = 'ringing');
        unawaited(RingSound.start(RingKind.outgoing));
      }),
      h.on('VideoCallAccepted', (_) {
        _stopOutgoingRingUi();
        if (mounted) setState(() => _callingOut = false);
      }),
    ]);
    _reconnectSub = h.onReconnected.listen((_) async {
      await h.invoke('JoinConversation', [_cid]).catchError((_) => null);
      await _flushOutbox();
    });

    if (!ref.read(networkProvider)) return;
    try {
      await h.invoke('JoinConversation', [_cid]);
      await _flushOutbox();
    } catch (_) {}
    if (!mounted) return;
    _markReadInterval = Timer.periodic(const Duration(seconds: 4), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) _markRead();
    });
  }

  void _markRead() {
    if (!mounted || !ref.read(networkProvider)) return;
    Hubs.conversation.invoke('MarkAsRead', [_cid]).catchError((_) => null);
  }

  void _onListUpdated(Object? payload) {
    if (payload is! Map || payload.str('conversationId') != _cid) return;
    final type = payload.s('lastMessageType');
    ref.read(conversationsListProvider.notifier).updateConversation(_cid, {
      'lastMessagePreview': formatConversationListPreview(payload.s('lastMessagePreview'), type: type),
      'lastMessageAt': payload.v('lastMessageAt'),
      'lastMessageType': type,
    });
  }

  void _markReadDebounced() {
    _markReadTimer?.cancel();
    _markReadTimer = Timer(const Duration(milliseconds: 300), _markRead);
  }

  void _onReceive(Object? raw) {
    if (raw is! Map) return;
    final m = normalizeMsg(raw);
    final fromMe = m['senderId'] == _me;
    if (fromMe) {
      if (!_store.updatePendingMessage(m)) _store.addMessage({...m, 'status': 'sent'});
    } else {
      _store.addMessage({...m, 'status': 'sent'});
      _markReadDebounced();
    }
    _maybeScrollOrFab(fromOwnSend: fromMe);
    _saveDebounced();
  }

  void _onJoined(Object? raw) {
    if (raw is! Map) return;
    final p = raw.v('partner');
    final type = raw.v('type');
    final isGroup = type == 1 || type == 'Group' || raw.v('groupName') != null;
    Json? partner = p is Map
        ? {
            'id': p.s('id') ?? p.s('userId'),
            'name': p.s('name'),
            'avatar': p.s('avatar'),
            'isOnline': p.b('isOnline'),
            'uniqueCode': p.s('uniqueCode'),
          }
        : ref.read(activeConversationProvider).partner;
    if (isGroup) partner = {'id': _cid, 'name': raw.s('groupName') ?? 'مجموعة', 'avatar': raw.s('groupImageUrl')};
    final pending = ref.read(activeConversationProvider).messages.where((m) => m['tempId'] != null).toList();
    ref.read(conversationsListProvider.notifier).updateConversation(_cid, {'unreadCount': 0, 'UnreadCount': 0, 'partnerAvatar': partner?['avatar']});
    final server = [for (final m in (raw.v('messages') as List? ?? const [])) if (m is Map) {...normalizeMsg(m), 'status': 'sent'}];
    final ids = server.map((m) => m['id']).toSet();
    final merged = [...server, ...pending.where((m) => !ids.contains(m['id']))]
      ..sort((a, b) => (a.date('sentAt') ?? DateTime(0)).compareTo(b.date('sentAt') ?? DateTime(0)));
    _store.setConversationAndMessages(_cid, partner, isGroup: isGroup, messages: merged);
    final hasMore = raw.b('hasMore') || raw.v('HasMore') == true;
    if (mounted) {
      setState(() {
        _loading = false;
        _hasMore = hasMore;
      });
    } else {
      _hasMore = hasMore;
    }
    _scrollToBottom(force: true);
    _saveDebounced();
    if (isGroup) _fetchGroupSenders();
  }

  void _onOlderMessages(Object? raw) {
    if (raw is! Map) return;
    if (raw.str('conversationId') != _cid && raw.str('ConversationId') != _cid) {
      // tolerate missing id
    }
    final server = [for (final m in (raw.v('messages') as List? ?? const [])) if (m is Map) {...normalizeMsg(m), 'status': 'sent'}];
    final hasMore = raw.b('hasMore') || raw.v('HasMore') == true;
    _store.prependMessages(server);
    if (mounted) {
      setState(() {
        _loadingOlder = false;
        _hasMore = hasMore;
      });
    } else {
      _loadingOlder = false;
      _hasMore = hasMore;
    }
    _saveDebounced();
  }

  bool _isNearBottom() {
    if (!_scroll.hasClients) return true;
    // reverse:true → bottom is offset ≈ 0
    return _scroll.offset <= 80;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final near = _isNearBottom();
    if (near && (_showJumpFab || _unreadWhileAway > 0) && mounted) {
      setState(() {
        _showJumpFab = false;
        _unreadWhileAway = 0;
      });
    } else if (!near && !_showJumpFab && mounted && _unreadWhileAway == 0) {
      // keep fab hidden until a new message arrives while away
    }
    // Load older when approaching the "top" of a reverse list (maxScrollExtent).
    if (_hasMore && !_loadingOlder && _scroll.position.maxScrollExtent > 0 && _scroll.offset >= _scroll.position.maxScrollExtent - 240) {
      unawaited(_loadOlder());
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || !ref.read(networkProvider)) return;
    final msgs = ref.read(activeConversationProvider).messages;
    String? beforeId;
    for (final m in msgs) {
      final id = m.s('id');
      if (m['tempId'] == null && id != null && id.isNotEmpty) {
        beforeId = id;
        break;
      }
    }
    if (beforeId == null) return;
    setState(() => _loadingOlder = true);
    try {
      await Hubs.conversation.invoke('GetOlderMessages', [_cid, beforeId, 60]);
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _maybeScrollOrFab({required bool fromOwnSend}) {
    if (fromOwnSend || _isNearBottom()) {
      _scrollToBottom(force: fromOwnSend);
      if (_showJumpFab || _unreadWhileAway > 0) {
        setState(() {
          _showJumpFab = false;
          _unreadWhileAway = 0;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _showJumpFab = true;
        _unreadWhileAway += 1;
      });
    }
  }

  void _jumpToLatest() {
    setState(() {
      _showJumpFab = false;
      _unreadWhileAway = 0;
    });
    _scrollToBottom(force: true);
  }

  Future<void> _flushOutbox() async {
    if (_flushingOutbox || !ref.read(networkProvider)) return;
    _flushingOutbox = true;
    try {
      final items = ref
          .read(activeConversationProvider)
          .messages
          .where((m) => (m['status'] == 'pending' || m['status'] == 'failed') && (m.s('type') ?? 'text') == 'text' && m['tempId'] != null)
          .toList();
      for (final msg in items) {
        final tempId = '${msg['tempId']}';
        _store.updateByTempId(tempId, {'status': 'pending'});
        try {
          await Hubs.conversation.ensureConnected(timeout: const Duration(seconds: 15));
          await Hubs.conversation.invoke('SendMessage', [_cid, msg.str('content'), 'text', msg.s('replyToMessageId') ?? '']);
          _armPendingTimeout(tempId);
        } catch (_) {
          _store.updateByTempId(tempId, {'status': 'failed'});
        }
      }
      _persistOutbox();
    } finally {
      _flushingOutbox = false;
    }
  }

  Future<void> _recoverAfterOnline() async {
    if (!mounted) return;
    try {
      await Hubs.conversation.forceReconnect();
      await Hubs.conversation.ensureConnected(timeout: const Duration(seconds: 20));
      await Hubs.conversation.invoke('JoinConversation', [_cid]);
      await _flushOutbox();
      if (ref.read(activeConversationProvider).isGroup) await _fetchGroupSenders();
    } catch (_) {
      // Will retry on next hub onReconnected / network poll.
    }
  }

  Future<void> _fetchGroupSenders() async {
    try {
      final list = asJsonList(await Api.get('/conversations/$_cid/members'));
      final map = <String, Json>{};
      for (final m in list) {
        final id = m.s('userId');
        if (id != null) map[id] = {'name': m.s('name') ?? '—', 'avatar': m.s('avatar')};
      }
      if (mounted) setState(() => _groupSenders = map);
    } catch (_) {}
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_isNearBottom()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final d in _disposers) {
      d();
    }
    _reconnectSub?.cancel();
    _typingTimer?.cancel();
    _markReadTimer?.cancel();
    _markReadInterval?.cancel();
    _saveTimer?.cancel();
    _typingExpire?.cancel();
    _outgoingRing?.cancel();
    _recordTimer?.cancel();
    if (_callingOut) {
      _callingOut = false;
      // Don't cancel if Accept already opened the LiveKit screen for this call.
      if (videoScreenMounts(_cid) == 0) {
        if (ref.read(activeCallProvider).sessionId == _cid) {
          ref.read(activeCallProvider.notifier).clear();
        }
        Hubs.conversation
            .ensureConnected()
            .then((_) => Hubs.conversation.invoke('DeclineVideoCall', [_cid]))
            .catchError((_) => null);
      }
    }
    unawaited(RingSound.stop());
    _scroll.removeListener(_onScroll);
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    final joins = (_joinCounts[_cid] ?? 1) - 1;
    if (joins > 0) {
      _joinCounts[_cid] = joins;
    } else {
      _joinCounts.remove(_cid);
      if (NetworkStatus.online.value) {
        Hubs.conversation.invoke('LeaveConversation', [_cid]).catchError((_) => null);
      }
    }
    if (_ownsStore) {
      _storeOwner = null;
      final store = _store;
      Future.microtask(() {
        if (_storeOwner == null) store.clear();
      });
    }
    super.dispose();
  }

  // ---------- sending ----------
  void _onTextChanged(String _) {
    setState(() {});
    if (!ref.read(networkProvider)) return;
    if (_typingTimer == null) Hubs.conversation.invoke('StartTyping', [_cid]).catchError((_) => null);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1500), () {
      Hubs.conversation.invoke('StopTyping', [_cid]).catchError((_) => null);
      _typingTimer = null;
    });
  }

  bool _requireOnline({bool send = false}) {
    if (ref.read(networkProvider)) return true;
    if (mounted) showToast(context, t(send ? 'noConnection.sendFailed' : 'noConnection.actionFailed'), error: true);
    return false;
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final online = ref.read(networkProvider);
    final reply = _replyingTo;
    _text.clear();
    setState(() => _replyingTo = null);
    if (_typingTimer != null) {
      _typingTimer!.cancel();
      _typingTimer = null;
      if (online) Hubs.conversation.invoke('StopTyping', [_cid]).catchError((_) => null);
    }
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    _store.addMessage({
      'tempId': tempId,
      'senderId': _me,
      'content': text,
      'type': 'text',
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending',
      'replyToMessageId': reply?['id'],
      'replyToContent': reply?['content'],
      'replyToSenderName': reply?['senderName'],
      'replyToType': reply?['type'],
    });
    _scrollToBottom(force: true);
    _persistOutbox();
    if (!online) {
      if (mounted) showToast(context, t('conversationChat.queuedOffline'));
      return;
    }
    try {
      await Hubs.conversation.invoke('SendMessage', [_cid, text, 'text', reply?['id'] ?? '']);
      _armPendingTimeout(tempId);
    } catch (_) {
      _store.updateByTempId(tempId, {'status': 'failed'});
      _persistOutbox();
    }
  }

  void _armPendingTimeout(String tempId) {
    Timer(const Duration(seconds: 12), () {
      final m = ref.read(activeConversationProvider).messages.where((x) => x['tempId'] == tempId).firstOrNull;
      if (m != null && m['status'] == 'pending') _store.updateByTempId(tempId, {'status': 'failed'});
    });
  }

  Future<void> _sendUploaded(String content, String type) async {
    if (!_requireOnline(send: true)) return;
    final reply = _replyingTo;
    if (reply != null && mounted) setState(() => _replyingTo = null);
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    _store.addMessage({
      'tempId': tempId,
      'senderId': _me,
      'content': content,
      'type': type,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending',
      'replyToMessageId': reply?['id'],
      'replyToContent': reply?['content'],
      'replyToSenderName': reply?['senderName'],
      'replyToType': reply?['type'],
    });
    _scrollToBottom(force: true);
    try {
      await Hubs.conversation.ensureConnected(timeout: const Duration(seconds: 25));
      await Hubs.conversation.invoke('SendMessage', [_cid, content, type, reply?['id'] ?? '']);
      _armPendingTimeout(tempId);
    } catch (_) {
      _store.updateByTempId(tempId, {'status': 'failed'});
    }
  }

  Future<void> _attachImage() async {
    if (!_requireOnline(send: true)) return;
    final f = await pickImage();
    if (f == null) return;
    setState(() => _uploadingImage = true);
    try {
      final url = await uploadFile('/media/upload', f.path);
      await _sendUploaded(url, 'image');
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('conversationChat.imageUploadFailed')), error: true);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _attachVideo() async {
    if (!_requireOnline(send: true)) return;
    final f = await pickVideo();
    if (f == null) return;
    setState(() => _uploadingVideo = true);
    try {
      final url = await uploadFile('/media/upload-chat-video', f.path, timeout: const Duration(seconds: 120));
      await _sendUploaded(url, 'video');
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('conversationChat.videoUploadFailed')), error: true);
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _attachAlbum() async {
    if (!_requireOnline(send: true)) return;
    final files = await pickImages();
    if (files.isEmpty) return;
    if (files.length > maxAlbumImages) {
      if (mounted) showToast(context, t('conversationChat.albumTooMany'), error: true);
      return;
    }
    setState(() => _uploadingAlbum = true);
    try {
      final urls = <String>[];
      for (final f in files) {
        urls.add(await uploadFile('/media/upload', f.path));
      }
      await _sendUploaded(buildAlbumPayload(urls), 'album');
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('conversationChat.albumUploadFailed')), error: true);
    } finally {
      if (mounted) setState(() => _uploadingAlbum = false);
    }
  }

  Future<void> _startRecording() async {
    if (!_requireOnline(send: true)) return;
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) showToast(context, t('conversationChat.voicePermissionDenied'), error: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() {
        _recording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _recordSeconds++));
    } catch (_) {
      if (mounted) showToast(context, t('conversationChat.voicePermissionDenied'), error: true);
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _recorder.cancel();
    setState(() {
      _recording = false;
      _recordSeconds = 0;
    });
  }

  Future<void> _stopAndSendVoice() async {
    _recordTimer?.cancel();
    final seconds = _recordSeconds;
    final path = await _recorder.stop();
    setState(() {
      _recording = false;
      _recordSeconds = 0;
    });
    if (path == null || seconds < 1) {
      if (mounted) showToast(context, t('conversationChat.voiceRecordingTooShort'), error: true);
      return;
    }
    final reply = _replyingTo;
    if (reply != null && mounted) setState(() => _replyingTo = null);
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    _pendingAudio[tempId] = path;
    _store.addMessage({
      'tempId': tempId,
      'senderId': _me,
      'content': path,
      'type': 'audio',
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending',
      'replyToMessageId': reply?['id'],
      'replyToContent': reply?['content'],
      'replyToSenderName': reply?['senderName'],
    });
    _scrollToBottom(force: true);
    await _uploadVoice(tempId, path);
  }

  Future<void> _uploadVoice(String tempId, String path) async {
    setState(() => _uploadingVoice = true);
    try {
      final url = await uploadFile('/media/upload-audio', path, filename: 'voice.m4a');
      _store.updateByTempId(tempId, {'content': url});
      _pendingAudio.remove(tempId);
      var sent = false;
      for (var attempt = 0; attempt < 2 && !sent; attempt++) {
        try {
          await Hubs.conversation.ensureConnected(timeout: const Duration(seconds: 25));
          final pending = ref.read(activeConversationProvider).messages.where((x) => x['tempId'] == tempId).firstOrNull;
          await Hubs.conversation.invoke('SendMessage', [_cid, url, 'audio', pending?['replyToMessageId'] ?? '']);
          sent = true;
          _armPendingTimeout(tempId);
        } catch (_) {
          if (attempt == 1) _store.updateByTempId(tempId, {'status': 'failed'});
        }
      }
    } catch (e) {
      _store.updateByTempId(tempId, {'status': 'failed'});
      if (mounted) showToast(context, Api.errorMessage(e, t('conversationChat.voiceUploadFailed')), error: true);
    } finally {
      if (mounted) setState(() => _uploadingVoice = false);
    }
  }

  Future<void> _retry(Json msg) async {
    if (msg['status'] != 'failed') return;
    if (!_requireOnline(send: true)) return;
    final oldTemp = '${msg['tempId']}';
    final newTemp = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    _store.updateByTempId(oldTemp, {'tempId': newTemp, 'status': 'pending'});
    final localAudio = _pendingAudio.remove(oldTemp);
    if (localAudio != null) {
      _pendingAudio[newTemp] = localAudio;
      await _uploadVoice(newTemp, localAudio);
      return;
    }
    try {
      await Hubs.conversation.ensureConnected(timeout: const Duration(seconds: 20));
      await Hubs.conversation.invoke('SendMessage', [_cid, msg.str('content'), msg.s('type') ?? 'text', msg.s('replyToMessageId') ?? '']);
      _armPendingTimeout(newTemp);
    } catch (_) {
      _store.updateByTempId(newTemp, {'status': 'failed'});
    }
  }

  // ---------- message actions ----------
  void _reply(Json msg) {
    final mine = msg['senderId'] == _me;
    final type = msg.s('type') ?? 'text';
    final sf = parseShortFilmMessage(type, msg.str('content'));
    final album = parseAlbumMessage(msg.s('content'));
    String preview;
    if (sf != null) {
      final title = sf.title.isEmpty ? t('shortFilms.title') : sf.title;
      preview = '🎬 ${title.length > 48 ? title.substring(0, 48) : title}';
    } else if (type == 'video') {
      preview = t('conversationChat.replyPreviewVideo');
    } else if (type == 'album' || album != null) {
      preview = t('conversationChat.replyPreviewAlbum');
    } else if (type == 'story_reply') {
      preview = parseStoryReplyMessage(type, msg.str('content'))?.listPreview ?? t('stories.storyReplyPreview');
    } else if (type == 'text') {
      final s = msg.str('content');
      preview = s.length > 50 ? s.substring(0, 50) : s;
    } else {
      preview = type == 'audio' ? '🎤' : '🖼';
    }
    final partner = ref.read(activeConversationProvider).partner;
    setState(() => _replyingTo = {
          'id': msg['id'],
          'content': preview,
          'type': type,
          'senderName': mine
              ? t('conversationChat.you')
              : (msg.s('senderName') ?? _groupSenders[msg.str('senderId')]?.s('name') ?? partner?.s('name') ?? '—'),
        });
    _focus.requestFocus();
  }

  void _share(Json msg) {
    final type = msg.s('type') ?? 'text';
    final sf = parseShortFilmMessage(type, msg.str('content'));
    final share = sf != null
        ? {'type': 'short_film', 'content': buildShortFilmShareContent(sf.id, sf.title, sf.thumbnailUrl)}
        : {'type': type, 'content': msg.str('content')};
    context.push('/share-message', extra: {'shareMessage': share, 'sourceConversationId': _cid});
  }

  Future<void> _download(Json msg) async {
    try {
      await downloadMessageMedia(msg);
      if (mounted) showToast(context, t('conversationChat.downloadSuccess'));
    } catch (_) {
      if (mounted) showToast(context, t('conversationChat.downloadFailed'), error: true);
    }
  }

  void _openMenu(Json msg) {
    final type = msg.s('type') ?? 'text';
    final label = switch (type) {
      'video' => t('conversationChat.downloadVideo'),
      'audio' => t('conversationChat.downloadAudio'),
      'album' => t('conversationChat.downloadAlbum'),
      _ => t('conversationChat.downloadImage'),
    };
    showAppSheet<void>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final e in reactionEmojis)
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _pickReaction(msg, e);
                },
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(e, style: const TextStyle(fontSize: 28))),
              ),
          ]),
        ),
        SheetAction(icon: LucideIcons.reply, label: t('conversationChat.reply'), onTap: () {
          Navigator.pop(ctx);
          _reply(msg);
        }),
        SheetAction(icon: LucideIcons.forward, label: t('conversationChat.share'), onTap: () {
          Navigator.pop(ctx);
          _share(msg);
        }),
        if (canDownloadMessage(msg))
          SheetAction(icon: LucideIcons.download, label: label, onTap: () {
            Navigator.pop(ctx);
            _download(msg);
          }),
        SheetAction(icon: LucideIcons.trash2, label: t('conversationChat.deleteForMe'), onTap: () {
          Navigator.pop(ctx);
          if (!_requireOnline()) return;
          Hubs.conversation.invoke('DeleteMessageForMe', [_cid, msg.str('id')]).catchError((_) => null);
        }),
        if (msg['senderId'] == _me)
          SheetAction(icon: LucideIcons.userX, label: t('conversationChat.deleteForEveryone'), danger: true, onTap: () {
            Navigator.pop(ctx);
            if (!_requireOnline()) return;
            Hubs.conversation.invoke('DeleteMessageForEveryone', [_cid, msg.str('id')]).catchError((_) => null);
          }),
        const SizedBox(height: 8),
      ]),
    );
  }

  void _openReactionPicker(Json msg) {
    if (msg['id'] == null || msg.b('deletedForEveryone')) return;
    showAppSheet<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (final e in reactionEmojis)
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _pickReaction(msg, e);
              },
              child: Text(e, style: const TextStyle(fontSize: 30)),
            ),
        ]),
      ),
    );
  }

  Future<void> _pickReaction(Json msg, String emoji) async {
    if (!_requireOnline()) return;
    final id = msg.s('id');
    if (id == null) return;
    final previous = msg['reactions'] as List? ?? const [];
    _store.applyOptimisticReaction(id, _me, emoji);
    try {
      await Hubs.conversation.invoke('AddReaction', [_cid, id, emoji]);
    } catch (_) {
      _store.updateReactions(id, previous);
    }
  }

  Future<void> _scrollToReplied(String? id) async {
    if (id == null) return;
    final s = ref.read(activeConversationProvider);
    final msgs = s.messages;
    final idx = msgs.indexWhere((m) => m.s('id') == id);
    if (idx < 0) return;
    final key = msgKey(msgs[idx]);
    var ctx = _keys[key]?.currentContext;
    if (ctx == null && _scroll.hasClients) {
      final pos = _scroll.position;
      final count = msgs.length + (s.partnerTyping ? 1 : 0);
      final avg = (pos.maxScrollExtent + pos.viewportDimension) / count;
      final reversed = count - 1 - idx;
      _scroll.jumpTo((reversed * avg - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
      for (var step = 0; step < 40 && mounted && _scroll.hasClients; step++) {
        ctx = _keys[key]?.currentContext;
        if (ctx != null) break;
        int? lo, hi;
        for (var j = 0; j < msgs.length; j++) {
          if (_keys[msgKey(msgs[j])]?.currentContext != null) {
            lo ??= j;
            hi = j;
          }
        }
        if (lo == null || hi == null) break;
        final p = _scroll.position;
        final delta = p.viewportDimension * 0.8 * (idx < lo ? 1 : -1);
        final next = (p.pixels + delta).clamp(0.0, p.maxScrollExtent);
        if (next == p.pixels) break;
        _scroll.jumpTo(next);
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    if (!mounted || ctx == null || !ctx.mounted) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.5);
    setState(() => _highlighted = key);
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _highlighted = null);
    });
  }

  bool _isRead(Json msg, DateTime? partnerLastRead, {required bool isGroup}) {
    if (msg['senderId'] != _me) return false;
    if (msg['status'] == 'pending' || msg['status'] == 'failed') return false;
    if (msg['isRead'] == true) return true;
    if (isGroup) return false;
    if (partnerLastRead == null) return false;
    final sent = msg.date('sentAt');
    return sent != null && !sent.isAfter(partnerLastRead);
  }

  Future<void> _startCall({required bool voiceOnly}) async {
    if (_callingOut) return;
    if (!_requireOnline()) return;
    clearGhostActiveCall(ref);
    final active = ref.read(activeCallProvider);
    if (active.sessionId == _cid) {
      ref.read(activeCallProvider.notifier).expand();
      openVideoRoute(GoRouter.of(context), _cid, {'voiceOnly': active.voiceOnly || voiceOnly, 'fromConversation': true});
      return;
    }
    if (active.sessionId != null) {
      showToast(context, t('videoCall.alreadyInCall'), error: true);
      return;
    }
    setState(() {
      _callingOut = true;
      _callingVoiceOnly = voiceOnly;
      _callPhase = 'calling';
      _callDeclined = false;
      _callBusy = false;
    });
    final partner = ref.read(activeConversationProvider).partner;
    ref.read(activeCallProvider.notifier).syncMeta(
          sessionId: _cid,
          voiceOnly: voiceOnly,
          isConversation: true,
          partnerName: partner?.s('name') ?? '',
          partnerAvatar: partner?.s('avatar'),
          partnerUserId: partner?.s('id'),
        );
    _outgoingRing?.cancel();
    _outgoingRing = Timer(kIncomingCallRingTimeout, () {
      if (!mounted || !_callingOut) return;
      _cancelOutgoing(noAnswer: true);
    });
    try {
      await Hubs.conversation.invoke('RequestVideoCall', [_cid, voiceOnly]);
    } catch (_) {
      _stopOutgoingRingUi();
      if (ref.read(activeCallProvider).sessionId == _cid) ref.read(activeCallProvider.notifier).clear();
      if (mounted) setState(() => _callingOut = false);
    }
  }

  void _stopOutgoingRingUi() {
    _outgoingRing?.cancel();
    unawaited(RingSound.stop());
  }

  void _cancelOutgoing({bool noAnswer = false}) {
    if (!_callingOut) return;
    _stopOutgoingRingUi();
    setState(() => _callingOut = false);
    if (ref.read(activeCallProvider).sessionId == _cid) ref.read(activeCallProvider.notifier).clear();
    final outcome = noAnswer ? 'missed' : 'cancelled';
    Hubs.conversation
        .ensureConnected()
        .then((_) => Hubs.conversation.invoke('DeclineVideoCall', [_cid, false, outcome]))
        .catchError((_) => null);
  }

  Future<void> _deleteConversation() async {
    if (!_requireOnline()) return;
    final ok = await confirmDialog(
      context,
      title: '${t('conversationChat.deleteConversation')}؟',
      confirm: t('common.delete'),
      cancel: t('common.cancel'),
      danger: true,
    );
    if (!ok) return;
    try {
      await Hubs.conversation.invoke('DeleteConversationForMe', [_cid]);
      if (mounted) context.go('/conversations');
    } catch (_) {
      if (mounted) showToast(context, t('common.error'), error: true);
    }
  }

  void _openPartner() {
    final s = ref.read(activeConversationProvider);
    if (s.isGroup) {
      context.push('/conversation/$_cid/group-info');
      return;
    }
    final pid = s.partner?.s('id');
    if (pid != null) context.push('/profile/$pid', extra: {'conversationId': _cid});
  }

  void _openInputMenu() {
    showAppSheet<void>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        SheetAction(icon: LucideIcons.image, label: t('conversationChat.attachImage'), onTap: () {
          Navigator.pop(ctx);
          _attachImage();
        }),
        SheetAction(icon: LucideIcons.images, label: t('conversationChat.attachAlbum'), onTap: () {
          Navigator.pop(ctx);
          _attachAlbum();
        }),
        SheetAction(icon: LucideIcons.video, label: t('conversationChat.attachVideo'), onTap: () {
          Navigator.pop(ctx);
          _attachVideo();
        }),
        SheetAction(icon: LucideIcons.mic, label: t('conversationChat.voiceMessage'), onTap: () {
          Navigator.pop(ctx);
          _startRecording();
        }),
        const SizedBox(height: 8),
      ]),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    ref.listen(networkProvider, (prev, next) {
      if (prev == false && next == true) unawaited(_recoverAfterOnline());
    });
    final c = context.colors;
    final s = ref.watch(activeConversationProvider);
    final partner = s.partner;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pad = MediaQuery.paddingOf(context);
    final online = partner?.b('isOnline') ?? false;

    return Scaffold(
      backgroundColor: c.bgPrimary,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Column(children: [
          Container(
            padding: EdgeInsets.fromLTRB(12, pad.top + 8, 12, 10),
            decoration: BoxDecoration(
              color: c.bgPrimary,
              boxShadow: [
                BoxShadow(color: c.shadow.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(children: [
              GlassIconButton(
                icon: rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
                onTap: () => context.go('/conversations'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openPartner,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            UserAvatar(url: partner?.s('avatar'), name: partner?.s('name') ?? '', size: 44),
                            if (!s.isGroup)
                              PositionedDirectional(
                                end: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: online ? c.success : c.textMuted,
                                    border: Border.all(color: c.bgPrimary, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                partner?.s('name') ?? '…',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              if (s.partnerTyping)
                                Text(
                                  t('conversationChat.typing'),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.primary),
                                )
                              else if (s.isGroup)
                                Text(t('groups.members'), style: TextStyle(fontSize: 12, color: c.textMuted))
                              else
                                Text(
                                  online ? t('profile.online') : t('profile.offline'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: online ? c.success : c.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (!s.isGroup) ...[
                _HeaderAction(icon: LucideIcons.video, onTap: () => _startCall(voiceOnly: false)),
                const SizedBox(width: 6),
                _HeaderAction(icon: LucideIcons.phone, onTap: () => _startCall(voiceOnly: true)),
                const SizedBox(width: 6),
              ],
              _HeaderAction(icon: LucideIcons.trash2, onTap: _deleteConversation, danger: true),
            ]),
          ),
          ActiveCallBar(embeddedFor: _cid),
          Expanded(
            child: ColoredBox(
              color: c.bgPrimary,
              child: s.messages.isEmpty && !s.partnerTyping
                  ? Center(child: Text(t('conversationChat.empty'), style: TextStyle(color: c.textMuted, fontSize: 13)))
                  : Stack(
                      children: [
                        ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          itemCount: s.messages.length + (s.partnerTyping ? 1 : 0) + (_loadingOlder ? 1 : 0),
                          itemBuilder: (context, i) {
                            final typing = s.partnerTyping ? 1 : 0;
                            if (i < typing) return const TypingBubble();
                            final msgIndexFromEnd = i - typing;
                            if (_loadingOlder && msgIndexFromEnd == s.messages.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: Text(t('conversationChat.loadingOlder'), style: TextStyle(fontSize: 12, color: c.textMuted)),
                                ),
                              );
                            }
                            final msg = s.messages[s.messages.length - 1 - msgIndexFromEnd];
                            final key = _keys.putIfAbsent(msgKey(msg), GlobalKey.new);
                            return KeyedSubtree(
                              key: key,
                              child: MessageItem(
                                msg: msg,
                                mine: msg['senderId'] == _me,
                                me: _me,
                                isGroup: s.isGroup,
                                sender: _groupSenders[msg.str('senderId')],
                                highlighted: _highlighted == msgKey(msg),
                                read: _isRead(msg, s.partnerLastReadAt, isGroup: s.isGroup),
                                onMenu: () => _openMenu(msg),
                                onLongPress: () => _openReactionPicker(msg),
                                onReaction: (e) => _pickReaction(msg, e),
                                onRetry: () => _retry(msg),
                                onReplyTap: () => _scrollToReplied(msg.s('replyToMessageId')),
                                onSenderTap: () => context.push('/profile/${msg.str('senderId')}', extra: {'conversationId': _cid}),
                              ),
                            );
                          },
                        ),
                        if (_showJumpFab)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 12,
                            child: Center(
                              child: Material(
                                color: c.bgElevated,
                                elevation: 3,
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  onTap: _jumpToLatest,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(LucideIcons.chevronsDown, size: 16, color: c.primary),
                                        const SizedBox(width: 6),
                                        Text(
                                          _unreadWhileAway > 0
                                              ? '${t('conversationChat.newMessages')} ($_unreadWhileAway)'
                                              : t('conversationChat.newMessages'),
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          _buildInput(context),
        ]),
        LoaderOverlay(
          show: _loading || _uploadingVideo || _uploadingAlbum,
          text: _uploadingVideo
              ? t('conversationChat.uploadingVideo')
              : _uploadingAlbum
                  ? t('conversationChat.uploadingAlbum')
                  : t('common.loading'),
        ),
        if (_callingOut)
          _CallingOverlay(
            name: partner?.s('name') ?? '',
            avatar: partner?.s('avatar'),
            voiceOnly: _callingVoiceOnly,
            ringing: _callPhase == 'ringing',
            onCancel: _cancelOutgoing,
          ),
        if (_callDeclined || _callBusy)
          Positioned(
            left: 32,
            right: 32,
            bottom: 28 + pad.bottom,
            child: Material(
              color: const Color(0xE6111B21),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  _callBusy
                      ? t('conversationChat.userBusy')
                      : t('conversationChat.callDeclined', {'name': partner?.s('name') ?? '…'}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildInput(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + (MediaQuery.viewInsetsOf(context).bottom > 0 ? 0 : bottom)),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(top: BorderSide(color: c.border)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_replyingTo != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0x266C63FF), Color(0x0F6C63FF)]),
              border: Border.all(color: const Color(0x406C63FF)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(LucideIcons.reply, size: 16, color: c.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_replyingTo!.str('senderName'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.primary)),
                  Text(_replyingTo!.str('content'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                ]),
              ),
              IconButton(onPressed: () => setState(() => _replyingTo = null), icon: Icon(LucideIcons.x, size: 18, color: c.textMuted)),
            ]),
          ),
        if (_recording)
          RecordingBar(seconds: _recordSeconds, onDiscard: _cancelRecording, onSend: _stopAndSendVoice)
        else ...[
          if (_uploadingVoice)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)),
                const SizedBox(width: 8),
                Text(t('conversationChat.uploadingVoice'), style: TextStyle(fontSize: 12, color: c.textSecondary)),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _RoundBtn(
              icon: LucideIcons.ellipsisVertical,
              bg: c.bgElevated,
              fg: c.textSecondary,
              border: c.border,
              onTap: _uploading ? null : _openInputMenu,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                minLines: 1,
                maxLines: 5,
                maxLength: 5000,
                onChanged: _onTextChanged,
                textInputAction: TextInputAction.newline,
                style: TextStyle(color: c.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: t('conversationChat.messagePlaceholder'),
                  hintStyle: TextStyle(color: c.textMuted),
                  filled: true,
                  fillColor: c.bgElevated,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: c.primary)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _RoundBtn(
              icon: LucideIcons.send,
              bg: c.primary,
              fg: Colors.white,
              shadow: true,
              onTap: _text.text.trim().isEmpty ? null : _send,
            ),
          ]),
        ],
      ]),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.bg, required this.fg, this.onTap, this.border, this.shadow = false});
  final IconData icon;
  final Color bg;
  final Color fg;
  final Color? border;
  final VoidCallback? onTap;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: border == null ? null : Border.all(color: border!),
          boxShadow: shadow ? const [BoxShadow(color: Color(0x472563EB), blurRadius: 14, offset: Offset(0, 4))] : null,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Icon(icon, size: 20, color: fg)),
        ),
      ),
    );
  }
}

/// `.recording-bar`
class RecordingBar extends StatefulWidget {
  const RecordingBar({super.key, required this.seconds, required this.onDiscard, required this.onSend});
  final int seconds;
  final VoidCallback onDiscard;
  final VoidCallback onSend;

  @override
  State<RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<RecordingBar> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 550))..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const red = Color(0xFFEF4444);
    const heights = [12.0, 10.0, 18.0, 14.0, 20.0, 12.0, 10.0, 14.0, 18.0, 20.0, 10.0, 14.0];
    final time = '${widget.seconds ~/ 60}:${(widget.seconds % 60).toString().padLeft(2, '0')}';
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 8, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(colors: [red.withValues(alpha: 0.1), c.bgElevated, c.bgElevated], stops: const [0, 0.42, 1]),
        border: Border.all(color: red.withValues(alpha: 0.22)),
      ),
      child: Row(children: [
        Material(
          color: red.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onDiscard,
            child: const SizedBox(width: 44, height: 44, child: Icon(LucideIcons.trash2, size: 20, color: red)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              FadeTransition(
                opacity: Tween(begin: 0.4, end: 1.0).animate(_anim),
                child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: red, shape: BoxShape.circle)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('conversationChat.recordingVoice'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary)),
              ),
              Text(time, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: red, letterSpacing: 0.5)),
            ]),
            const SizedBox(height: 6),
            SizedBox(
              height: 22,
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, _) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < 12; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 3,
                      height: heights[i] * (0.35 + 0.65 * ((_anim.value + i * 0.065) % 1)),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFFF87171), c.primary]),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Material(
          color: c.primary,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onSend,
            child: const SizedBox(width: 44, height: 44, child: Icon(LucideIcons.send, size: 20, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: c.msgTheirsBg, borderRadius: BorderRadius.circular(16)),
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.textMuted.withValues(alpha: 0.4 + 0.6 * (((_anim.value * 3 - i) % 3) < 1 ? 1 : 0)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, required this.onTap, this.danger = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: danger ? c.danger.withValues(alpha: 0.1) : c.bgCard,
      borderRadius: BorderRadius.circular(14),
      shadowColor: c.shadow,
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: danger ? c.danger : c.textSecondary),
        ),
      ),
    );
  }
}

class _CallingOverlay extends StatelessWidget {
  const _CallingOverlay({
    required this.name,
    this.avatar,
    required this.voiceOnly,
    required this.ringing,
    required this.onCancel,
  });
  final String name;
  final String? avatar;
  final bool voiceOnly;
  final bool ringing;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final phase = ringing ? t('conversationChat.ringingCall') : t('conversationChat.connectingCall');
    final kind = voiceOnly ? t('conversationChat.incomingVoiceCall') : t('conversationChat.incomingVideoCall');
    return Positioned.fill(
      child: Material(
        color: WaCall.bgTop,
        child: WhatsAppRingingLayout(
          avatarUrl: avatar,
          name: name,
          status: '$phase\n$kind',
          actions: [
            CallCircleButton(
              icon: LucideIcons.phoneOff,
              onTap: onCancel,
              background: WaCall.decline,
              size: 68,
              label: t('videoCall.endCall'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single message row (bubble + meta + reactions), shared with the random ChatView.
class MessageItem extends StatelessWidget {
  const MessageItem({
    super.key,
    required this.msg,
    required this.mine,
    required this.me,
    this.isGroup = false,
    this.sender,
    this.highlighted = false,
    this.read = false,
    this.onMenu,
    this.onLongPress,
    this.onReaction,
    this.onRetry,
    this.onReplyTap,
    this.onSenderTap,
  });

  final Json msg;
  final bool mine;
  final String me;
  final bool isGroup;
  final Json? sender;
  final bool highlighted;
  final bool read;
  final VoidCallback? onMenu;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onReaction;
  final VoidCallback? onRetry;
  final VoidCallback? onReplyTap;
  final VoidCallback? onSenderTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final type = msg.s('type') ?? 'text';
    final content = msg.str('content');
    final deleted = msg.b('deletedForEveryone');
    final album = type == 'album' ? parseAlbumMessage(content) : null;
    final sf = parseShortFilmMessage(type, content);
    final storyReply = parseStoryReplyMessage(type, content);
    final fg = mine ? Colors.white : c.msgTheirsColor;
    final reactions = (msg['reactions'] as List? ?? const []).whereType<Map>().toList();
    String? myReaction;
    for (final r in reactions) {
      final ids = (r.v('userIds') as List? ?? const []).map((e) => '$e');
      if (ids.contains(me)) myReaction = r.s('emoji');
    }
    myReaction ??= msg.s('myReaction');

    final isMediaBubble = type == 'image' || album != null || type == 'video' || sf != null || storyReply != null;

    Widget body;
    if (deleted) {
      body = Text(t('conversationChat.messageDeleted'), style: TextStyle(fontStyle: FontStyle.italic, color: fg.withValues(alpha: 0.7), fontSize: 14));
    } else if (type == 'call') {
      return _CallHistoryRow(msg: msg, mine: mine, me: me);
    } else if (storyReply != null) {
      body = _StoryReplyBubble(reply: storyReply, mine: mine, fg: fg);
    } else if (type == 'image') {
      body = GestureDetector(
        onTap: () => showImageViewer(context, [content]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320),
            child: Image(image: mediaImage(content, cacheWidth: bubbleImageCacheWidth), fit: BoxFit.cover),
          ),
        ),
      );
    } else if (album != null) {
      body = AlbumGrid(urls: album, onOpen: (i) => showImageViewer(context, album, start: i));
    } else if (type == 'video') {
      body = ChatVideo(url: content, onExpand: () => showVideoViewer(context, content));
    } else if (sf != null) {
      body = ShortFilmCard(title: sf.title, thumbnailUrl: sf.thumbnailUrl, mine: mine, onOpen: () => context.push('/short-films/watch?start=${sf.id}'));
    } else if (type == 'audio') {
      body = AudioBubble(url: content, mine: mine);
    } else {
      body = LinkifiedText(content, style: TextStyle(color: fg, fontSize: 15, height: 1.5), linkColor: mine ? Colors.white : c.primary);
    }

    final hasReply = (msg.s('replyToContent') ?? msg.s('replyToSenderName')) != null;
    final bubble = GestureDetector(
      onLongPress: deleted ? null : onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: isMediaBubble && !deleted ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? null : c.msgTheirsBg,
          gradient: mine ? AppColors.msgMineGradient : null,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(16),
            topEnd: const Radius.circular(16),
            bottomStart: Radius.circular(mine ? 16 : 4),
            bottomEnd: Radius.circular(mine ? 4 : 16),
          ),
          boxShadow: highlighted ? [BoxShadow(color: (mine ? Colors.white : const Color(0xFF6C63FF)).withValues(alpha: 0.4), blurRadius: 0, spreadRadius: 8)] : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (hasReply)
            GestureDetector(
              onTap: onReplyTap,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: mine ? Colors.white.withValues(alpha: 0.15) : const Color(0x1A6C63FF),
                  borderRadius: BorderRadius.circular(8),
                  border: BorderDirectional(start: BorderSide(color: mine ? Colors.white70 : c.primary, width: 3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(LucideIcons.reply, size: 12, color: mine ? Colors.white : c.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(msg.s('replyToSenderName') ?? '—',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: mine ? Colors.white : c.primary)),
                      Text(replyPreviewText(msg.s('replyToContent'), msg.s('replyToType')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: mine ? Colors.white.withValues(alpha: 0.9) : c.textSecondary)),
                    ]),
                  ),
                ]),
              ),
            ),
          body,
        ]),
      ),
    );

    final sentAt = msg.date('sentAt');
    final status = msg.s('status');
    Widget? statusIcon;
    if (mine && !deleted) {
      if (status == 'pending') {
        statusIcon = Icon(LucideIcons.clock, size: 14, color: c.textMuted.withValues(alpha: 0.8));
      } else if (status == 'failed') {
        statusIcon = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.circleAlert, size: 14, color: c.danger),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRetry,
            child: Row(children: [
              Icon(LucideIcons.rotateCcw, size: 12, color: c.danger),
              const SizedBox(width: 2),
              Text(t('conversationChat.retry'), style: TextStyle(fontSize: 12, color: c.danger)),
            ]),
          ),
        ]);
      } else {
        statusIcon = Icon(read ? LucideIcons.checkCheck : LucideIcons.check, size: 14, color: c.primary);
      }
    }

    final maxW = MediaQuery.sizeOf(context).width * 0.8;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            if (isGroup && !mine)
              GestureDetector(
                onTap: onSenderTap,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 2, bottom: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    UserAvatar(url: msg.s('senderAvatar') ?? sender?.s('avatar'), name: msg.s('senderName') ?? sender?.s('name') ?? '?', size: 22),
                    const SizedBox(width: 8),
                    Text(msg.s('senderName') ?? sender?.s('name') ?? '—',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.primary)),
                  ]),
                ),
              ),
            bubble,
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (sentAt != null) Text(formatTime12(sentAt), style: TextStyle(fontSize: 12, color: c.textMuted)),
              if (statusIcon != null) ...[const SizedBox(width: 6), statusIcon],
              if (!deleted && onMenu != null)
                GestureDetector(
                  onTap: onMenu,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Icon(LucideIcons.ellipsisVertical, size: 14, color: c.textMuted),
                  ),
                ),
            ]),
            if (!deleted && reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 4, children: [
                  for (final r in reactions)
                    GestureDetector(
                      onTap: () => onReaction?.call(r.str('emoji')),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: myReaction == r.s('emoji') ? const Color(0x266C63FF) : c.bgElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: myReaction == r.s('emoji') ? c.primary : c.border),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(r.str('emoji'), style: const TextStyle(fontSize: 13)),
                          if (r.i('count') > 1) ...[
                            const SizedBox(width: 2),
                            Text('${r.i('count')}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textSecondary)),
                          ],
                        ]),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _StoryReplyBubble extends StatelessWidget {
  const _StoryReplyBubble({required this.reply, required this.mine, required this.fg});

  final StoryReplyRef reply;
  final bool mine;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 72,
        height: 96,
        child: reply.isText
            ? DecoratedBox(
                decoration: storyBackgroundDecoration(reply.backgroundColor),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      (reply.caption ?? '').trim().isEmpty ? t('stories.allStory') : reply.caption!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, height: 1.25),
                    ),
                  ),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image(
                    image: mediaImage(reply.mediaUrl!, cacheWidth: bubbleImageCacheWidth),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: Colors.black26,
                      child: Icon(reply.isVideo ? LucideIcons.video : LucideIcons.image, color: Colors.white70, size: 22),
                    ),
                  ),
                  if (reply.isVideo)
                    const Center(child: Icon(LucideIcons.play, color: Colors.white, size: 22)),
                ],
              ),
      ),
    );

    final text = reply.text.trim().isEmpty
        ? t('stories.storyReplyPreview')
        : reply.text.trim();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          thumb,
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('stories.storyReplyPreview'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg.withValues(alpha: 0.75)),
                ),
                const SizedBox(height: 4),
                LinkifiedText(
                  text,
                  style: TextStyle(color: fg, fontSize: 15, height: 1.45),
                  linkColor: mine ? Colors.white : context.colors.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// System-style call event in the chat transcript (NexChat soft tokens).
class _CallHistoryRow extends StatelessWidget {
  const _CallHistoryRow({required this.msg, required this.mine, required this.me});

  final Json msg;
  final bool mine;
  final String me;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = msg.str('content');
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final status = '${data?['status'] ?? 'missed'}';
    final voiceOnly = data?['voiceOnly'] == true || data?['voiceOnly'] == 'true';
    final durationSec = int.tryParse('${data?['durationSec'] ?? 0}') ?? 0;
    final failed = status == 'missed' || status == 'declined' || status == 'cancelled' || status == 'busy';
    final accent = failed ? c.danger : c.primary;
    final title = formatCallMessagePreview(content, mine: mine)
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s·\s.*$'), '')
        .trim();
    final kind = voiceOnly ? t('conversationChat.voiceCallKind') : t('conversationChat.videoCallKind');
    final sentAt = msg.date('sentAt');
    final metaParts = <String>[kind];
    if (status == 'ended' && durationSec > 0) {
      final m = (durationSec ~/ 60).toString().padLeft(2, '0');
      final s = (durationSec % 60).toString().padLeft(2, '0');
      metaParts.add('$m:$s');
    }
    if (sentAt != null) metaParts.add(formatTime12(sentAt));

    final icon = failed
        ? (voiceOnly ? LucideIcons.phoneOff : LucideIcons.videoOff)
        : (voiceOnly ? LucideIcons.phone : LucideIcons.video);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: failed ? accent.withValues(alpha: 0.08) : c.systemMsgBg,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: accent.withValues(alpha: failed ? 0.14 : 0.10)),
              boxShadow: [
                BoxShadow(color: c.shadow.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 16, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          metaParts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                            color: c.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
