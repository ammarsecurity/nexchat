import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../services/media.dart';
import '../../services/ring_sound.dart';
import '../../services/secure_screen.dart';
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
import 'conversation_cache.dart';
import 'conversation_refresh.dart';
import 'message_contract.dart';
import 'message_copy_action.dart';
import 'message_outbox.dart';

const reactionEmojis = ['❤️', '👍', '😂', '😮', '😢', '🙏'];

String msgKey(Json m) => '${m['tempId'] ?? m['id']}';

String replyPreviewText(String? content, String? type) {
  if (type == 'video') return t('conversationChat.replyPreviewVideo');
  if (type == 'album') return t('conversationChat.replyPreviewAlbum');
  if (type == 'audio') return t('conversationChat.voiceMessage');
  if (type == 'image') return t('conversationChat.replyPreviewImage');
  if (type == 'location') return locationListPreview(content);
  if (type == 'file') return fileListPreview(content);
  if (type == 'story_share') return parseStoryShareMessage('story_share', content ?? '')?.listPreview ?? t('share.storySharePreview');
  if (type == 'story_reply') return parseStoryReplyMessage('story_reply', content ?? '')?.listPreview ?? t('stories.storyReplyPreview');
  if (type == 'call') return formatCallMessagePreview(content, mine: false);
  if (content == null || content.isEmpty) return '';
  if (parseAlbumMessage(content) != null) return t('conversationChat.replyPreviewAlbum');
  final loc = parseLocationMessage(null, content);
  if (loc != null) return locationListPreview(content);
  final file = parseFileMessage(null, content);
  if (file != null) return fileListPreview(content);
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
  bool _refreshing = false;
  Object? _refreshError;
  late final ConversationRefreshController _refresh;
  late final String? _sessionToken;
  bool _uploadingImage = false, _uploadingVideo = false, _uploadingAlbum = false, _uploadingVoice = false, _uploadingFile = false, _sharingLocation = false;
  Json? _replyingTo;
  Map<String, Json> _groupSenders = {};
  String? _highlighted;
  final _keys = <String, GlobalKey>{};
  String? _outgoingCallId;
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
  Timer? _typingExpire;
  Timer? _expirySweep;
  int _disappearMode = 0;

  final _recorder = AudioRecorder();
  bool _recording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  final _pendingAudio = <String, String>{};

  late final ActiveConversationController _store;

  late final String _accountId;
  String get _me => _accountId;
  bool get _uploading => _uploadingImage || _uploadingVideo || _uploadingAlbum || _uploadingVoice || _uploadingFile || _sharingLocation;
  bool get _ownsStore => mounted && identical(_storeOwner, this) && ref.read(authProvider).user?.id == _accountId && ref.read(authProvider).token == _sessionToken;

  @override
  void initState() {
    super.initState();
    _accountId = ref.read(authProvider).user?.id ?? '';
    _sessionToken = ref.read(authProvider).token;
    _store = ref.read(activeConversationProvider.notifier);
    _storeOwner = this;
    _joinCounts.update(_cid, (n) => n + 1, ifAbsent: () => 1);
    WidgetsBinding.instance.addObserver(this);
    unawaited(SecureScreen.acquire());
    _refresh = ConversationRefreshController(
      conversation: _cid,
      isCurrent: () => _ownsStore && ref.read(activeConversationProvider).conversationId == _cid,
      load: () async => Map<String, dynamic>.from((await Api.dio.get(
        'conversations/$_cid/messages',
        options: Options(headers: {'Authorization': 'Bearer $_sessionToken'},
          extra: {'preserveAuthorization': true}),
      )).data as Map),
      readMessages: () => ref.read(activeConversationProvider).messages,
      apply: (messages, hasMore) {
        _store.setMessages(messages);
        _hasMore = hasMore;
        for (final m in messages) {
          if (m.str('senderId') == _accountId && m['status'] == 'sent') {
            unawaited(MessageOutbox.acknowledge(_accountId, m));
          }
        }
        _scheduleExpirySweep();
        _saveDebounced();
        _scrollToBottom();
        _markReadDebounced();
      },
      onState: (loading, error) {
        if (_ownsStore) setState(() { _refreshing = loading; _refreshError = error; });
      },
    );
    ref.listenManual(conversationRefreshIntentProvider, (_, intent) {
      if (intent.conversation == _cid) unawaited(_refresh.refresh());
    });
    Future.microtask(_init);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh.refresh());
      _markRead();
    }
  }

  void _saveNow() {
    if (!_ownsStore) return;
    final active = ref.read(activeConversationProvider);
    if (active.conversationId != _cid) return;
    unawaited(ConversationCache.save(_accountId, _cid, active.messages));
    _persistOutbox();
  }

  void _saveDebounced() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  void _persistOutbox() {
    if (!_ownsStore) return;
    final active = ref.read(activeConversationProvider);
    if (active.conversationId != _cid) return;
    for (final message in active.messages) {
      if ((message['status'] == 'pending' || message['status'] == 'failed') && (message.s('type') ?? 'text') == 'text') {
        unawaited(MessageOutbox.enqueue(_accountId, {...message, 'conversationId': _cid}));
      }
    }
  }

  bool _accepts(Object? payload) => _ownsStore && payload is Map && belongsToConversation(payload, _cid);

  void _deleteMessage(Object? payload, {required bool everyone}) {
    if (!_accepts(payload)) return;
    final id = (payload as Map).str('messageId');
    if (id.isEmpty) return;
    if (everyone) { _store.setDeletedForEveryone(id); } else { _refresh.removedIds.add(id); _store.removeMessage(id); }
    if (_replyingTo?.str('id') == id && mounted) setState(() => _replyingTo = null);
    unawaited(ConversationCache.redact(_accountId, _cid, [id]));
    _saveNow();
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
    final isGroup = fromList?.b('isGroup') ?? false;
    final isSupport = fromList?.b('isSupport') ?? false;
    final isOfficial = isOfficialConversation(fromList);
    if (!mounted || !_ownsStore) return;
    if (isOfficial) {
      partner = {
        ...?partner,
        'name': t('conversations.officialName'),
        'uniqueCode': 'NX-NEWS',
      };
    }
    _store.setConversation(_cid, partner, isGroup: isGroup, isSupport: isSupport, isOfficial: isOfficial);
    if (isGroup && ref.read(networkProvider)) _fetchGroupSenders();

    final msgs = ConversationCache.read(_accountId, _cid);
    final outbox = MessageOutbox.read(_accountId, _cid);
    final ids = msgs.map(clientMessageId).where((id) => id.isNotEmpty).toSet();
    _store.setMessages([...msgs, ...outbox.where((m) => !ids.contains(clientMessageId(m)))]);
    _scrollToBottom(force: true);
    _scheduleExpirySweep();
    setState(() => _loading = false);
    _scroll.addListener(_onScroll);

    final ackSub = MessageOutbox.acknowledgments.stream.listen((event) {
      if (event.account != _accountId || !_accepts(event.message)) return;
      if (!_store.updatePendingMessage(event.message)) _store.addMessage(event.message);
      _saveDebounced();
    });
    final failedSub = MessageOutbox.failures.stream.listen((event) {
      if (!_ownsStore || event.account != _accountId || event.conversation != _cid) return;
      _store.updateByTempId(event.clientId, {'status': 'failed'});
    });
    _disposers.add(() { unawaited(ackSub.cancel()); unawaited(failedSub.cancel()); });
    final h = Hubs.conversation;
    _disposers.addAll([
      h.on('ConversationListUpdated', (a) => _onListUpdated(a.firstOrNull)),
      h.on('ReceiveMessage', (a) => _onReceive(a.firstOrNull)),
      h.on('UserTypingV2', (a) {
        if (!_accepts(a.firstOrNull)) return;
        _store.setTyping(true);
        _typingExpire?.cancel();
        _typingExpire = Timer(const Duration(seconds: 3), () => _store.setTyping(false));
      }),
      h.on('UserStoppedTypingV2', (a) {
        if (!_accepts(a.firstOrNull)) return;
        _typingExpire?.cancel();
        _store.setTyping(false);
      }),
      h.on('MessageDeletedForMeV2', (a) => _deleteMessage(a.firstOrNull, everyone: false)),
      h.on('MessageDeletedForEveryoneV2', (a) => _deleteMessage(a.firstOrNull, everyone: true)),
      h.on('ReplyPreviewsRedacted', (a) {
        if (!_accepts(a.firstOrNull)) return;
        final ids = (a.first as Map).v('messageIds');
        if (ids is List) { _store.redactReplies(ids.map((id) => '$id')); _saveNow(); }
      }),
      h.on('MessageUpdated', (a) {
        final raw = a.firstOrNull;
        if (!_accepts(raw) || raw is! Map) return;
        final m = Map<String, dynamic>.from(raw);
        final id = m.str('id');
        if (id.isEmpty) return;
        _store.updateById(id, {
          'content': m.s('content') ?? m['content'],
          'type': m.s('type') ?? m['type'],
          'deletedForEveryone': false,
        });
        _saveNow();
      }),
      h.on('MessagesExpired', (a) {
        if (!_accepts(a.firstOrNull)) return;
        final p = a.firstOrNull;
        final ids = p is Map ? p.v('messageIds') : null;
        if (ids is List && ids.isNotEmpty) {
          _refresh.removedIds.addAll(ids.map((e) => '$e'));
          _store.removeMessages(ids.map((e) => '$e'));
          _saveDebounced();
        }
      }),
      h.on('MessagesExpiring', (a) {
        if (!_accepts(a.firstOrNull)) return;
        final p = a.firstOrNull;
        if (p is! Map) return;
        final ids = p.v('messageIds');
        if (ids is! List || ids.isEmpty) return;
        final expiresAt = p.s('expiresAt') ?? p.v('ExpiresAt')?.toString();
        _store.setExpiresAt(ids.map((e) => '$e'), expiresAt);
        _scheduleExpirySweep();
        _saveDebounced();
      }),
      h.on('DisappearModeChanged', (a) {
        if (!_accepts(a.firstOrNull)) return;
        final p = a.firstOrNull;
        if (p is! Map) return;
        final cid = '${p.v('conversationId') ?? p.v('ConversationId') ?? ''}';
        if (cid.isNotEmpty && cid != _cid) return;
        final mode = p.i('disappearMode');
        if (mounted) setState(() => _disappearMode = mode);
      }),
      h.on('ConversationDeletedForMeV2', (a) => _onConversationRemoved(a.firstOrNull)),
      h.on('ConversationRemoved', (a) => _onConversationRemoved(a.firstOrNull)),
      h.on('ConversationJoined', (a) => _onJoined(a.firstOrNull)),
      h.on('OlderMessages', (a) => _onOlderMessages(a.firstOrNull)),
      h.on('PartnerReadUpTo', (a) {
        if (!_accepts(a.firstOrNull)) return;
        final p = a.firstOrNull;
        if (p is! Map || p.str('readerId') == _me) return;
        final active = ref.read(activeConversationProvider);
        if (!active.isGroup && p.str('readerId') != active.partner?.str('id')) return;
        final at = p.date('lastReadAt');
        if (at != null) _store.setPartnerLastReadAt(at);
      }),
      h.on('MessagesRead', (a) {
        if (!_accepts(a.firstOrNull)) return;
        // Private chats use PartnerReadUpTo / lastReadAt for ticks — skip heavy list patch.
        if (!ref.read(activeConversationProvider).isGroup) return;
        final p = a.firstOrNull;
        final ids = p is Map ? p.v('messageIds') : null;
        if (ids is List && ids.isNotEmpty) _store.setMessagesRead(ids.map((e) => '$e'));
      }),
      h.on('Error', (a) {
        if ('${a.firstOrNull}'.contains('not found') && mounted) context.go('/conversations');
      }),
      h.on('ReactionUpdated', (a) {
        if (!_accepts(a.firstOrNull)) return;
        final p = a.firstOrNull;
        if (p is! Map) return;
        final mid = p.s('messageId');
        if (mid != null) {
          _store.updateReactions(mid, (p.v('reactions') as List?) ?? const []);
          _saveDebounced();
        }
      }),
      h.on('ViewOnceOpened', (a) {
        if (!_accepts(a.firstOrNull)) return;
        final p = a.firstOrNull;
        if (p is! Map) return;
        final mid = p.s('messageId') ?? '${p.v('messageId') ?? ''}';
        if (mid.isEmpty) return;
        final openerId = p.s('userId') ?? '${p.v('userId') ?? ''}';
        // Per-user receipts: only the opener marks opened locally.
        // Sender marks opened when anyone opens (matches history load).
        final existing = ref.read(activeConversationProvider).messages.where((m) => msgId(m) == mid).firstOrNull;
        final isSender = existing != null && existing.str('senderId') == _me;
        if (isSender || openerId == _me) {
          _store.updateById(mid, {'viewOnceOpened': true});
          _saveDebounced();
        }
      }),
      h.on('ViewOnceScreenshot', (a) {
        if (!_accepts(a.firstOrNull)) return;
        if (mounted) showToast(context, t('conversationChat.viewOnceScreenshotTaken'));
      }),
      h.on('VideoCallEnded', (a) {
        if (a.length < 3 || a[0] != _cid || a[2] != _outgoingCallId) return;
        _stopOutgoingRingUi();
        if (mounted) setState(() => _callingOut = false);
      }),
      h.on('VideoCallDeclined', (a) {
        final cid = '${a.firstOrNull ?? ''}';
        if (cid != _cid || a.length < 2 || a[1] != _outgoingCallId) return;
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
        if (cid != _cid || a.length < 2 || a[1] != _outgoingCallId) return;
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
        if (cid != _cid || a.length < 2 || a[1] != _outgoingCallId) return;
        if (!mounted || !_callingOut) return;
        if (_callPhase == 'ringing') return;
        setState(() => _callPhase = 'ringing');
        unawaited(RingSound.start(RingKind.outgoing));
      }),
      h.on('VideoCallAccepted', (a) {
        if (a.length < 3 || a[0] != _cid || a[2] != _outgoingCallId) return;
        _stopOutgoingRingUi();
        if (mounted) setState(() => _callingOut = false);
      }),
    ]);
    _reconnectSub = h.onReconnected.listen((_) async {
      if (!_ownsStore) return;
      unawaited(_refresh.refresh());
      await h.invoke('JoinConversation', [_cid]).catchError((_) => null);
      await _flushOutbox();
    });

    unawaited(_refresh.refresh());
    if (fromList == null) unawaited(_loadMetadata());
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

  Future<void> _loadMetadata() async {
    try {
      final data = (await Api.dio.get('conversations/$_cid', options: Options(
        headers: {'Authorization': 'Bearer $_sessionToken'}, extra: {'preserveAuthorization': true},
      ))).data as Map;
      if (!_ownsStore || ref.read(activeConversationProvider).conversationId != _cid) return;
      final active = ref.read(activeConversationProvider);
      // A joined hub may already have supplied richer metadata while HTTP ran.
      if (active.partner != null) return;
      final group = data.s('type') == 'group';
      final support = data.b('isSupport');
      final official = data.b('isOfficial') || data.b('isReadOnly');
      final partner = group
          ? <String, dynamic>{'id': _cid, 'name': data.s('groupName') ?? 'مجموعة', 'avatar': data.s('groupImageUrl')}
          : <String, dynamic>{'id': data.s('partnerId'), 'name': official ? t('conversations.officialName') : data.s('partnerName') ?? '',
              'avatar': data.s('partnerAvatar'), 'isOnline': data.b('partnerIsOnline'),
              'uniqueCode': official ? 'NX-NEWS' : (support ? 'NX-SUPPORT' : null)};
      _store.setConversationAndMessages(_cid, partner, isGroup: group,
        isSupport: support, isOfficial: official, messages: active.messages);
      if (group) unawaited(_fetchGroupSenders());
    } catch (_) {}
  }

  void _markRead() {
    if (!_ownsStore || !ref.read(networkProvider)) return;
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
    if (!_accepts(raw) || raw is! Map) return;
    final m = normalizeMsg(raw);
    if (messageIsExpired(m)) return;
    final fromMe = m.str('senderId').toLowerCase() == _me.toLowerCase();
    if (fromMe) {
      unawaited(MessageOutbox.acknowledge(_accountId, {...m, 'status': 'sent'}));
      if (!_store.updatePendingMessage(m)) _store.addMessage({...m, 'status': 'sent'});
    } else {
      _store.addMessage({...m, 'status': 'sent'});
      _markReadDebounced();
    }
    _scheduleExpirySweep();
    _maybeScrollOrFab(fromOwnSend: fromMe);
    _saveDebounced();
  }

  void _scheduleExpirySweep() {
    if (!_ownsStore) return;
    _expirySweep?.cancel();
    _store.setMessages(withoutExpiredMessages(ref.read(activeConversationProvider).messages));
    final msgs = ref.read(activeConversationProvider).messages;
    DateTime? next;
    final now = DateTime.now().toUtc();
    for (final m in msgs) {
      final replyAt = m.date('replyToExpiresAt');
      if (replyAt != null && replyAt.isAfter(now) && (next == null || replyAt.isBefore(next))) next = replyAt;
      final at = m.date('expiresAt');
      if (at == null) continue;
      if (!at.isAfter(now)) {
        _store.removeMessage(msgId(m));
        _saveNow();
        continue;
      }
      if (next == null || at.isBefore(next)) next = at;
    }
    if (next == null) return;
    final wait = next.difference(now);
    _expirySweep = Timer(wait.isNegative ? Duration.zero : wait + const Duration(milliseconds: 200), () {
      if (!_ownsStore) return;
      final kept = withoutExpiredMessages(ref.read(activeConversationProvider).messages);
      _store.setMessages(kept);
      _saveNow();
      _scheduleExpirySweep();
    });
  }

  void _onJoined(Object? raw) {
    if (!_ownsStore || raw is! Map || raw.str('id') != _cid) return;
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
    ref.read(conversationsListProvider.notifier).updateConversation(_cid, {'unreadCount': 0, 'UnreadCount': 0, 'partnerAvatar': partner?['avatar']});
    final server = [for (final m in (raw.v('messages') as List? ?? const [])) if (m is Map && belongsToConversation(m, _cid)) {...normalizeMsg(m), 'status': 'sent'}];
    for (final message in server) {
      if (message.str('senderId') == _accountId) unawaited(MessageOutbox.acknowledge(_accountId, message));
    }
    // Join can complete after HTTP or a live arrival. Never replace newer state.
    final merged = mergeConversationSnapshot(baseline: const [],
      current: ref.read(activeConversationProvider).messages, server: server,
      hasMore: raw.b('hasMore'), removedIds: _refresh.removedIds, additive: true);
    final isSupport = ref.read(activeConversationProvider).isSupport ||
        partner?.s('uniqueCode') == 'NX-SUPPORT' ||
        (partner?.s('name') == 'دعم');
    final isOfficial = ref.read(activeConversationProvider).isOfficial ||
        isOfficialConversation(partner) ||
        partner?.s('uniqueCode') == 'NX-NEWS';
    if (isOfficial) {
      partner = {...?partner, 'name': t('conversations.officialName'), 'uniqueCode': 'NX-NEWS'};
    }
    _store.setConversationAndMessages(_cid, partner, isGroup: isGroup, isSupport: isSupport, isOfficial: isOfficial, messages: merged);
    final mode = raw.i('disappearMode');
    final hasMore = raw.b('hasMore') || raw.v('HasMore') == true;
    final effectiveMode = isGroup && mode == 1 ? 0 : mode;
    if (mounted) {
      setState(() {
        _loading = false;
        _hasMore = hasMore;
        _disappearMode = effectiveMode;
      });
    } else {
      _hasMore = hasMore;
      _disappearMode = effectiveMode;
    }
    _scheduleExpirySweep();
    _scrollToBottom(force: true);
    _saveDebounced();
    if (isGroup) _fetchGroupSenders();
  }

  void _onOlderMessages(Object? raw) {
    if (!_accepts(raw) || raw is! Map) return;
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
      if (id != null && id.isNotEmpty) {
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

  Future<void> _flushOutbox() => MessageOutbox.flush(_accountId);

  void _onConversationRemoved(Object? payload) {
    if (!_accepts(payload)) return;
    ref.read(conversationsListProvider.notifier).removeConversation(_cid);
    unawaited(ConversationCache.forget(_accountId, _cid));
    unawaited(MessageOutbox.forgetConversation(_accountId, _cid));
    _store.clear();
    if (mounted) context.go('/conversations');
  }

  Future<void> _recoverAfterOnline() async {
    if (!_ownsStore) return;
    try {
      await Hubs.conversation.resume();
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
    _saveNow();
    _refresh.dispose();
    unawaited(SecureScreen.release());
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
    _expirySweep?.cancel();
    _outgoingRing?.cancel();
    _recordTimer?.cancel();
    if (_callingOut) {
      final callId = _outgoingCallId;
      _callingOut = false;
      // Don't cancel if Accept already opened the LiveKit screen for this call.
      if (videoScreenMounts(_cid) == 0) {
        if (ref.read(activeCallProvider).sessionId == _cid) {
          ref.read(activeCallProvider.notifier).clear();
        }
        Hubs.conversation
            .ensureConnected()
            .then((_) => Hubs.conversation.invoke('DeclineVideoCallV2', [_cid, false, 'cancelled', callId ?? '']))
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

  /// Mark failed only when the server never echoed an id (invoke error must not clobber a saved msg).
  void _markSendResult(String tempId, {required bool ok}) {
    if (!_ownsStore) return;
    final m = ref.read(activeConversationProvider).messages.where((x) => x['tempId'] == tempId).firstOrNull;
    if (m == null) return;
    final hasServerId = (m.s('id') ?? '').isNotEmpty;
    if (hasServerId) {
      if (m['status'] != 'sent') _store.updateByTempId(tempId, {'status': 'sent'});
    } else {
      _store.updateByTempId(tempId, {'status': 'failed'});
    }
    _persistOutbox();
  }

  Future<void> _hubSendMessage(String content, String type, String replyId, {required String clientId, bool viewOnce = false}) async {
    if (!_ownsStore) throw StateError('Account changed');
    final result = await Hubs.conversation.invokeReliable('SendMessageWithClientId', conversationSendArguments(_cid, content, type, replyId, viewOnce, clientId));
    if (result is! Map || result.str('id').isEmpty || !belongsToConversation(result, _cid) || result.str('clientMessageId') != clientId) {
      throw StateError('Missing durable message acknowledgment');
    }
    final message = {...normalizeMsg(result), 'status': 'sent'};
    await MessageOutbox.acknowledge(_accountId, message);
    _onReceive(result);
  }

  Future<void> _send() async {
    if (!_ownsStore) return;
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final online = ref.read(networkProvider);
    final reply = _replyingTo;
    _text.clear();
    setState(() => _replyingTo = null);
    // Stop typing through the same invoke queue (never fire concurrent with SendMessage).
    if (_typingTimer != null) {
      _typingTimer!.cancel();
      _typingTimer = null;
    }
    final tempId = newClientMessageId();
    final replyId = '${reply?['id'] ?? ''}';
    _store.addMessage({
      'tempId': tempId,
      'clientMessageId': tempId,
      'conversationId': _cid,
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
      if (online) {
        try {
          await Hubs.conversation.invoke('StopTyping', [_cid]);
        } catch (_) {}
      }
      await _hubSendMessage(text, 'text', replyId, clientId: tempId);
      _markSendResult(tempId, ok: true);
    } catch (_) {
      _markSendResult(tempId, ok: false);
    }
  }

  Future<void> _sendUploaded(String content, String type, {bool viewOnce = false}) async {
    if (!_requireOnline(send: true)) return;
    final reply = _replyingTo;
    if (reply != null && mounted) setState(() => _replyingTo = null);
    final tempId = newClientMessageId();
    _store.addMessage({
      'tempId': tempId,
      'clientMessageId': tempId,
      'conversationId': _cid,
      'senderId': _me,
      'content': content,
      'type': type,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending',
      'replyToMessageId': reply?['id'],
      'replyToContent': reply?['content'],
      'replyToSenderName': reply?['senderName'],
      'replyToType': reply?['type'],
      'isViewOnce': viewOnce,
      'viewOnceOpened': false,
    });
    _scrollToBottom(force: true);
    try {
      await _hubSendMessage(content, type, '${reply?['id'] ?? ''}', clientId: tempId, viewOnce: viewOnce);
      _markSendResult(tempId, ok: true);
    } catch (e) {
      _markSendResult(tempId, ok: false);
      if (mounted) {
        final msg = e.toString();
        final unsupported = msg.contains('Unsupported message type');
        showToast(
          context,
          unsupported
              ? t('conversationChat.serverUpdateRequired')
              : Api.errorMessage(e, t('common.error')),
          error: true,
        );
      }
    }
  }

  /// Returns true = view once, false = normal, null = cancelled.
  Future<bool?> _askViewOnceMode() async {
    return showAppSheet<bool>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Column(children: [
            Text(t('conversationChat.viewOnce'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.colors.textPrimary)),
            const SizedBox(height: 6),
            Text(
              t('conversationChat.viewOnceHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ctx.colors.textSecondary, height: 1.35),
            ),
          ]),
        ),
        SheetAction(icon: LucideIcons.eye, label: t('conversationChat.viewOnceSend'), onTap: () => Navigator.pop(ctx, true)),
        SheetAction(icon: LucideIcons.send, label: t('conversationChat.viewOnceSendNormal'), onTap: () => Navigator.pop(ctx, false)),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('common.cancel'))),
        const SizedBox(height: 8),
      ]),
    );
  }

  Future<void> _attachImage({bool fromCamera = false}) async {
    if (!_requireOnline(send: true)) return;
    XFile? f;
    if (fromCamera) {
      if (!await ensureCameraPermission()) {
        if (mounted) showToast(context, t('conversationChat.cameraPermissionDenied'), error: true);
        return;
      }
      f = await pickImage(source: ImageSource.camera);
    } else {
      f = await pickImage();
    }
    if (f == null) return;
    final mode = await _askViewOnceMode();
    if (mode == null || !mounted) return;
    setState(() => _uploadingImage = true);
    try {
      final url = await uploadFile('/media/upload', f.path, viewOnce: mode);
      await _sendUploaded(url, 'image', viewOnce: mode);
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('conversationChat.imageUploadFailed')), error: true);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _attachVideo({bool fromCamera = false}) async {
    if (!_requireOnline(send: true)) return;
    XFile? f;
    if (fromCamera) {
      if (!await ensureCameraPermission(microphone: true)) {
        if (mounted) showToast(context, t('conversationChat.cameraPermissionDenied'), error: true);
        return;
      }
      f = await pickVideo(source: ImageSource.camera);
    } else {
      f = await pickVideo();
    }
    if (f == null) return;
    final mode = await _askViewOnceMode();
    if (mode == null || !mounted) return;
    setState(() => _uploadingVideo = true);
    try {
      final url = await uploadFile('/media/upload-chat-video', f.path, viewOnce: mode, timeout: const Duration(seconds: 120));
      await _sendUploaded(url, 'video', viewOnce: mode);
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

  Future<void> _shareLocation() async {
    if (!_requireOnline(send: true)) return;
    // Let the attach sheet finish dismissing before permission / GPS (avoids ANR).
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    try {
      await ensureLocationReady();
      if (!mounted) return;
      setState(() => _sharingLocation = true);
      final pos = await getShareablePosition();
      final payload = buildLocationPayload(
        lat: pos.latitude,
        lng: pos.longitude,
        name: t('conversationChat.currentLocation'),
      );
      await _sendUploaded(payload, 'location');
    } on StateError catch (e) {
      if (!mounted) return;
      final key = switch (e.message) {
        'location_disabled' => 'conversationChat.locationDisabled',
        'location_denied_forever' || 'location_denied' => 'conversationChat.locationPermissionDenied',
        'location_timeout' => 'conversationChat.locationFailed',
        'plugin_missing' => 'conversationChat.pluginRestartRequired',
        _ => 'conversationChat.locationPermissionDenied',
      };
      showToast(context, t(key), error: true);
    } catch (_) {
      if (mounted) showToast(context, t('conversationChat.locationFailed'), error: true);
    } finally {
      if (mounted) setState(() => _sharingLocation = false);
    }
  }

  Future<void> _attachDocument() async {
    if (!_requireOnline(send: true)) return;
    try {
      final picked = await pickChatDocument();
      if (picked == null || picked.path == null) return;
      final pickedSize = await picked.length() ?? picked.lengthSync() ?? 0;
      if (pickedSize > 25 * 1024 * 1024) {
        if (mounted) showToast(context, t('conversationChat.fileTooLarge'), error: true);
        return;
      }
      setState(() => _uploadingFile = true);
      final uploaded = await uploadChatDocument(picked.path!, filename: picked.name);
      await _sendUploaded(
        buildFilePayload(url: uploaded.url, name: uploaded.name, size: uploaded.size ?? pickedSize, contentType: uploaded.contentType),
        'file',
      );
    } on StateError catch (e) {
      if (mounted) {
        showToast(
          context,
          e.message == 'plugin_missing' ? t('conversationChat.pluginRestartRequired') : t('conversationChat.fileUploadFailed'),
          error: true,
        );
      }
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('conversationChat.fileUploadFailed')), error: true);
    } finally {
      if (mounted) setState(() => _uploadingFile = false);
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
    final tempId = newClientMessageId();
    _pendingAudio[tempId] = path;
    _store.addMessage({
      'tempId': tempId,
      'clientMessageId': tempId,
      'conversationId': _cid,
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
          final pending = ref.read(activeConversationProvider).messages.where((x) => x['tempId'] == tempId).firstOrNull;
          await _hubSendMessage(url, 'audio', '${pending?['replyToMessageId'] ?? ''}', clientId: tempId);
          sent = true;
          _markSendResult(tempId, ok: true);
        } catch (_) {
          if (attempt == 1) _markSendResult(tempId, ok: false);
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
    final newTemp = clientMessageId(msg);
    _store.updateByTempId(oldTemp, {'tempId': newTemp, 'status': 'pending'});
    final localAudio = _pendingAudio.remove(oldTemp);
    if (localAudio != null) {
      _pendingAudio[newTemp] = localAudio;
      await _uploadVoice(newTemp, localAudio);
      return;
    }
    // If the first attempt already got a server id, don't send a duplicate.
    final existing = ref.read(activeConversationProvider).messages.where((x) => x['tempId'] == newTemp).firstOrNull;
    if ((existing?.s('id') ?? '').isNotEmpty) {
      _markSendResult(newTemp, ok: true);
      return;
    }
    try {
      await _hubSendMessage(
        msg.str('content'),
        msg.s('type') ?? 'text',
        msg.s('replyToMessageId') ?? '',
        clientId: newTemp,
        viewOnce: msg.b('isViewOnce'),
      );
      _markSendResult(newTemp, ok: true);
    } catch (_) {
      _markSendResult(newTemp, ok: false);
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
      preview = msg.b('isViewOnce') ? t('conversationChat.viewOnceVideo') : t('conversationChat.replyPreviewVideo');
    } else if (type == 'album' || album != null) {
      preview = t('conversationChat.replyPreviewAlbum');
    } else if (type == 'story_share') {
      preview = parseStoryShareMessage(type, msg.str('content'))?.listPreview ?? t('share.storySharePreview');
    } else if (type == 'story_reply') {
      preview = parseStoryReplyMessage(type, msg.str('content'))?.listPreview ?? t('stories.storyReplyPreview');
    } else if (type == 'text') {
      final s = msg.str('content');
      preview = s.length > 50 ? s.substring(0, 50) : s;
    } else if (type == 'image') {
      preview = msg.b('isViewOnce') ? t('conversationChat.viewOncePhoto') : t('conversationChat.replyPreviewImage');
    } else if (type == 'location') {
      preview = locationListPreview(msg.s('content'));
    } else if (type == 'file') {
      preview = fileListPreview(msg.s('content'));
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
    if (msg.b('isViewOnce') || msg.b('deletedForEveryone') || msg.b('restricted') || messageIsExpired(msg)) return;
    final type = msg.s('type') ?? 'text';
    final sf = parseShortFilmMessage(type, msg.str('content'));
    final story = parseStoryShareMessage(type, msg.str('content'));
    final Map<String, dynamic> share;
    if (sf != null) {
      share = {'type': 'short_film', 'content': buildShortFilmShareContent(sf.id, sf.title, sf.thumbnailUrl)};
    } else if (story != null) {
      share = {
        'type': 'story_share',
        'content': buildStoryShareContent(
          userId: story.userId,
          slideId: story.slideId,
          name: story.name,
          mediaUrl: story.mediaUrl,
          mediaType: story.mediaType,
          caption: story.caption,
          backgroundColor: story.backgroundColor,
        ),
      };
    } else if (type == 'story_reply') {
      final text = copyableMessageText(msg);
      if (text == null) return;
      share = {'type': 'text', 'content': text};
    } else {
      share = {'type': type, 'content': msg.str('content')};
    }
    context.push('/share-message', extra: {'shareMessage': share, 'sourceConversationId': _cid});
  }

  Future<void> _download(Json msg) async {
    if (msg.b('isViewOnce')) return;
    try {
      await downloadMessageMedia(msg);
      if (mounted) showToast(context, t('conversationChat.downloadSuccess'));
    } catch (_) {
      if (mounted) showToast(context, t('conversationChat.downloadFailed'), error: true);
    }
  }

  Future<void> _openViewOnce(Json msg) async {
    final mine = msg['senderId'] == _me;
    final type = msg.s('type') ?? 'image';
    final localContent = msg.str('content');
    final id = msg.s('id');
    final opened = msg.b('viewOnceOpened');
    if (!mine && opened) {
      if (mounted) showToast(context, t('conversationChat.viewOnceAlreadyOpened'));
      return;
    }
    // Sender (or pending optimistic): open local/server URL in fullscreen only — never inline.
    if (mine && localContent.isNotEmpty && (id == null || id.isEmpty || id.startsWith('temp'))) {
      if (!mounted) return;
      if (type == 'video') {
        await showVideoViewer(context, localContent, allowDownload: false);
      } else {
        await showImageViewer(context, [localContent], allowDownload: false);
      }
      return;
    }
    if (!_requireOnline()) return;
    if (id == null || id.isEmpty) return;
    try {
      await Hubs.conversation.ensureConnected(timeout: const Duration(seconds: 15));
      final raw = await Hubs.conversation.invoke('OpenViewOnce', [id]);
      if (raw is! Map) {
        if (mounted) showToast(context, t('conversationChat.viewOnceOpenFailed'), error: true);
        return;
      }
      final map = Map<dynamic, dynamic>.from(raw);
      final content = map.s('content') ?? '${map.v('content') ?? ''}';
      final mediaType = map.s('type') ?? type;
      final already = map.b('opened');
      if (content.isEmpty || already) {
        if (!mine) {
          _store.updateById(id, {'viewOnceOpened': true});
          _saveDebounced();
        }
        if (mounted) showToast(context, t('conversationChat.viewOnceAlreadyOpened'));
        return;
      }
      // Server burns on OpenViewOnce; show media first, then mark local + legacy Confirm ack.
      if (!mounted) return;
      void reportShot() {
        Hubs.conversation.invoke('ReportViewOnceScreenshot', [id]).catchError((_) => null);
      }
      try {
        if (mediaType == 'video') {
          await showVideoViewer(context, content, allowDownload: false, onScreenshot: mine ? null : reportShot);
        } else {
          await showImageViewer(context, [content], allowDownload: false, onScreenshot: mine ? null : reportShot);
        }
      } finally {
        if (!mine) {
          _store.updateById(id, {'viewOnceOpened': true});
          _saveDebounced();
          try {
            await Hubs.conversation.invoke('ConfirmViewOnceOpened', [id]);
          } catch (_) {}
        }
      }
    } catch (_) {
      if (mounted) showToast(context, t('conversationChat.viewOnceOpenFailed'), error: true);
    }
  }

  void _openMenu(Json msg) {
    final type = msg.s('type') ?? 'text';
    final label = switch (type) {
      'video' => t('conversationChat.downloadVideo'),
      'audio' => t('conversationChat.downloadAudio'),
      'album' => t('conversationChat.downloadAlbum'),
      'file' => t('conversationChat.downloadFile'),
      _ => t('conversationChat.downloadImage'),
    };
    final viewOnce = msg.b('isViewOnce');
    final isOfficial = ref.read(activeConversationProvider).isOfficial;
    final copyText = copyableMessageText(msg);
    if (msg.b('deletedForEveryone') || msg.b('restricted') || messageIsExpired(msg)) return;
    showAppSheet<void>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        if (copyText != null)
          MessageCopyAction(
            message: msg,
            onClose: () => Navigator.pop(ctx),
            onCopied: () { if (mounted) showToast(context, t('conversationChat.copied')); },
            onFailure: () { if (mounted) showToast(context, t('common.error'), error: true); },
          ),
        if (!isOfficial)
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
        if (!isOfficial)
          SheetAction(icon: LucideIcons.reply, label: t('conversationChat.reply'), onTap: () {
            Navigator.pop(ctx);
            _reply(msg);
          }),
        if (!viewOnce)
          SheetAction(icon: LucideIcons.forward, label: t('conversationChat.share'), onTap: () {
            Navigator.pop(ctx);
            _share(msg);
          }),
        if (!viewOnce && canDownloadMessage(msg))
          SheetAction(icon: LucideIcons.download, label: label, onTap: () {
            Navigator.pop(ctx);
            _download(msg);
          }),
        if (!isOfficial)
          SheetAction(icon: LucideIcons.trash2, label: t('conversationChat.deleteForMe'), onTap: () {
            Navigator.pop(ctx);
            if (!_requireOnline()) return;
            Hubs.conversation.invoke('DeleteMessageForMe', [_cid, msg.str('id')]).catchError((_) => null);
          }),
        if (!isOfficial && msg['senderId'] == _me)
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
    if (ref.read(activeConversationProvider).isOfficial) return;
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
      openVideoRoute(GoRouter.of(context), _cid, {'voiceOnly': active.voiceOnly || voiceOnly, 'fromConversation': true, 'callId': active.callId});
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
    _outgoingCallId = newCallId();
    final partner = ref.read(activeConversationProvider).partner;
    ref.read(activeCallProvider.notifier).syncMeta(
          sessionId: _cid,
          callId: _outgoingCallId,
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
      await Hubs.conversation.invoke('RequestVideoCallV2', [_cid, voiceOnly, _outgoingCallId ?? '']);
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
    final callId = _outgoingCallId;
    _stopOutgoingRingUi();
    setState(() => _callingOut = false);
    if (ref.read(activeCallProvider).sessionId == _cid) ref.read(activeCallProvider.notifier).clear();
    final outcome = noAnswer ? 'missed' : 'cancelled';
    Hubs.conversation
        .ensureConnected()
        .then((_) => Hubs.conversation.invoke('DeclineVideoCallV2', [_cid, false, outcome, callId ?? '']))
        .catchError((_) => null);
  }

  Future<void> _deleteConversation() async {
    if (!_requireOnline()) return;
    final active = ref.read(activeConversationProvider);
    if (active.isSupport || active.isOfficial) {
      if (mounted) {
        showToast(
          context,
          active.isOfficial ? t('conversations.officialReadOnly') : t('settings.supportDesc'),
          error: true,
        );
      }
      return;
    }
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
    if (s.isSupport || s.isOfficial) return;
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
      builder: (ctx) => _ChatAttachSheet(
        onCapturePhoto: () {
          Navigator.pop(ctx);
          _attachImage(fromCamera: true);
        },
        onCaptureVideo: () {
          Navigator.pop(ctx);
          _attachVideo(fromCamera: true);
        },
        onAttachImage: () {
          Navigator.pop(ctx);
          _attachImage();
        },
        onAttachAlbum: () {
          Navigator.pop(ctx);
          _attachAlbum();
        },
        onAttachVideo: () {
          Navigator.pop(ctx);
          _attachVideo();
        },
        onVoice: () {
          Navigator.pop(ctx);
          _startRecording();
        },
        onLocation: () {
          Navigator.pop(ctx);
          _shareLocation();
        },
        onFile: () {
          Navigator.pop(ctx);
          _attachDocument();
        },
      ),
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
    final partner = ref.watch(activeConversationProvider.select((s) => s.partner));
    final isGroup = ref.watch(activeConversationProvider.select((s) => s.isGroup));
    final isSupport = ref.watch(activeConversationProvider.select((s) => s.isSupport));
    final isOfficial = ref.watch(activeConversationProvider.select((s) => s.isOfficial));
    final locked = isSupport || isOfficial;
    final partnerTyping = ref.watch(activeConversationProvider.select((s) => s.partnerTyping));
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pad = MediaQuery.paddingOf(context);
    final online = partner?.b('isOnline') ?? false;
    final displayName = isOfficial
        ? t('conversations.officialName')
        : (partner?.s('name') ?? (isGroup ? t('groupInfo.title') : '—'));

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
                            UserAvatar(url: partner?.s('avatar'), name: displayName, size: 44),
                            if (!isGroup && !isOfficial)
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
                              Row(children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: c.textPrimary,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                if (isOfficial || isSupport) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.verified, size: 16, color: c.primary),
                                ],
                              ]),
                              const SizedBox(height: 3),
                              if (partnerTyping)
                                Text(
                                  t('conversationChat.typing'),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.primary),
                                )
                              else if (isOfficial)
                                Text(t('conversations.officialSubtitle'), style: TextStyle(fontSize: 12, color: c.textMuted))
                              else if (isGroup)
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
              if (!isGroup && !locked) ...[
                _HeaderAction(icon: LucideIcons.video, onTap: () => _startCall(voiceOnly: false)),
                const SizedBox(width: 6),
                _HeaderAction(icon: LucideIcons.phone, onTap: () => _startCall(voiceOnly: true)),
                const SizedBox(width: 6),
              ],
              if (!locked)
                _HeaderAction(icon: LucideIcons.trash2, onTap: _deleteConversation, danger: true),
            ]),
          ),
          if (_disappearMode != 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: c.primary.withValues(alpha: 0.12),
              child: Row(children: [
                Icon(LucideIcons.timer, size: 14, color: c.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    switch (_disappearMode) {
                      1 => t('conversations.disappearAfterRead'),
                      2 => t('conversations.disappear1h'),
                      3 => t('conversations.disappear24h'),
                      4 => t('conversations.disappear1w'),
                      _ => t('conversations.disappearTitle'),
                    },
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.primary),
                  ),
                ),
              ]),
            ),
          ActiveCallBar(embeddedFor: _cid),
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          if (_refreshError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(child: Text(t('conversationChat.refreshFailed'), style: TextStyle(color: c.textMuted))),
                TextButton(onPressed: () => unawaited(_refresh.refresh()), child: Text(t('common.retry'))),
              ]),
            ),
          Expanded(
            child: ColoredBox(
              color: c.bgPrimary,
              child: Consumer(
                builder: (context, ref, _) {
                  final messages = ref.watch(activeConversationProvider.select((s) => s.messages));
                  final typing = ref.watch(activeConversationProvider.select((s) => s.partnerTyping));
                  final lastRead = ref.watch(activeConversationProvider.select((s) => s.partnerLastReadAt));
                  final group = ref.watch(activeConversationProvider.select((s) => s.isGroup));
                  if (messages.isEmpty && !typing) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      children: [
                        _ChatDateChip(label: formatChatDayLabel(iraqNow())),
                        const _ChatEncryptionBanner(),
                        const SizedBox(height: 24),
                        Center(child: Text(t('conversationChat.empty'), style: TextStyle(color: c.textMuted, fontSize: 13))),
                      ],
                    );
                  }
                  return Stack(
                    children: [
                      ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: messages.length + (typing ? 1 : 0) + (_loadingOlder ? 1 : 0),
                        itemBuilder: (context, i) {
                          final typingPad = typing ? 1 : 0;
                          if (i < typingPad) return const TypingBubble();
                          final msgIndexFromEnd = i - typingPad;
                          if (_loadingOlder && msgIndexFromEnd == messages.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: Text(t('conversationChat.loadingOlder'), style: TextStyle(fontSize: 12, color: c.textMuted)),
                              ),
                            );
                          }
                          final ci = messages.length - 1 - msgIndexFromEnd;
                          final msg = messages[ci];
                          final prev = ci > 0 ? messages[ci - 1] : null;
                          final showDate = prev == null || !isSameChatDay(msg.date('sentAt'), prev.date('sentAt'));
                          final showEncryption = ci == 0;
                          final key = _keys.putIfAbsent(msgKey(msg), GlobalKey.new);
                          return KeyedSubtree(
                            key: key,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // WhatsApp order: day chip → encryption notice → messages
                                if (showDate) _ChatDateChip(label: formatChatDayLabel(msg.date('sentAt'))),
                                if (showEncryption) const _ChatEncryptionBanner(),
                                MessageItem(
                                  msg: msg,
                                  mine: msg['senderId'] == _me,
                                  me: _me,
                                  isGroup: group,
                                  sender: _groupSenders[msg.str('senderId')],
                                  highlighted: _highlighted == msgKey(msg),
                                  read: _isRead(msg, lastRead, isGroup: group),
                                  onMenu: () => _openMenu(msg),
                                  onLongPress: () => _openReactionPicker(msg),
                                  onReaction: (e) => _pickReaction(msg, e),
                                  onRetry: () => _retry(msg),
                                  onReplyTap: () => _scrollToReplied(msg.s('replyToMessageId')),
                                  onSenderTap: () => context.push('/profile/${msg.str('senderId')}', extra: {'conversationId': _cid}),
                                  onViewOnceOpen: () => _openViewOnce(msg),
                                ),
                              ],
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
                  );
                },
              ),
            ),
          ),
          isOfficial
              ? _buildOfficialReadOnlyBar(context)
              : _buildInput(context),
        ]),
        LoaderOverlay(
          show: _loading || _uploadingVideo || _uploadingAlbum || _uploadingFile || _sharingLocation,
          text: _uploadingVideo
              ? t('conversationChat.uploadingVideo')
              : _uploadingAlbum
                  ? t('conversationChat.uploadingAlbum')
                  : _uploadingFile
                      ? t('conversationChat.uploadingFile')
                      : _sharingLocation
                          ? t('conversationChat.sharingLocation')
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

  Widget _buildOfficialReadOnlyBar(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.megaphone, size: 18, color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t('conversations.officialReadOnly'),
              style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
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
    this.onViewOnceOpen,
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
  final VoidCallback? onViewOnceOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final type = msg.s('type') ?? 'text';
    final content = msg.str('content');
    final deleted = msg.b('deletedForEveryone');
    final viewOnce = msg.b('isViewOnce');
    final viewOnceOpened = msg.b('viewOnceOpened');
    final album = type == 'album' ? parseAlbumMessage(content) : null;
    final sf = parseShortFilmMessage(type, content);
    final storyShare = parseStoryShareMessage(type, content);
    final storyReply = parseStoryReplyMessage(type, content);
    final location = parseLocationMessage(type, content);
    final fileShare = parseFileMessage(type, content);
    final fg = mine ? Colors.white : c.msgTheirsColor;
    final reactions = (msg['reactions'] as List? ?? const []).whereType<Map>().toList();
    String? myReaction;
    for (final r in reactions) {
      final ids = (r.v('userIds') as List? ?? const []).map((e) => '$e');
      if (ids.contains(me)) myReaction = r.s('emoji');
    }
    myReaction ??= msg.s('myReaction');

    final isMediaBubble = type == 'image' ||
        album != null ||
        type == 'video' ||
        sf != null ||
        storyShare != null ||
        storyReply != null ||
        location != null ||
        fileShare != null ||
        viewOnce;

    Widget body;
    if (deleted) {
      body = Text(t('conversationChat.messageDeleted'), style: TextStyle(fontStyle: FontStyle.italic, color: fg.withValues(alpha: 0.7), fontSize: 14));
    } else if (type == 'call') {
      return _CallHistoryRow(msg: msg, mine: mine, me: me);
    } else if (storyShare != null) {
      body = _StoryShareBubble(
        share: storyShare,
        mine: mine,
        fg: fg,
        onOpen: () {
          final slide = storyShare.slideId;
          final path = (slide != null && slide.isNotEmpty)
              ? '/stories/view/${storyShare.userId}?slideId=${Uri.encodeQueryComponent(slide)}'
              : '/stories/view/${storyShare.userId}';
          context.push(path);
        },
      );
    } else if (storyReply != null) {
      body = _StoryReplyBubble(reply: storyReply, mine: mine, fg: fg);
    } else if (viewOnce && (type == 'image' || type == 'video')) {
      // Never show thumbnail/player inline — only after tap (fullscreen).
      final lockedForRecipient = !mine && viewOnceOpened;
      body = _ViewOncePlaceholder(
        type: type,
        opened: lockedForRecipient,
        fg: fg,
        onTap: lockedForRecipient ? null : onViewOnceOpen,
        senderOpenedHint: mine && viewOnceOpened,
      );
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
    } else if (location != null) {
      body = _LocationBubble(location: location, mine: mine, fg: fg);
    } else if (fileShare != null) {
      body = _FileBubble(file: fileShare, mine: mine, fg: fg);
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

class _ChatAttachSheet extends StatelessWidget {
  const _ChatAttachSheet({
    required this.onCapturePhoto,
    required this.onCaptureVideo,
    required this.onAttachImage,
    required this.onAttachAlbum,
    required this.onAttachVideo,
    required this.onVoice,
    required this.onLocation,
    required this.onFile,
  });

  final VoidCallback onCapturePhoto;
  final VoidCallback onCaptureVideo;
  final VoidCallback onAttachImage;
  final VoidCallback onAttachAlbum;
  final VoidCallback onAttachVideo;
  final VoidCallback onVoice;
  final VoidCallback onLocation;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = <_AttachTileData>[
      _AttachTileData(LucideIcons.camera, t('conversationChat.capturePhotoShort'), const Color(0xFFE91E8C), onCapturePhoto),
      _AttachTileData(LucideIcons.video, t('conversationChat.captureVideoShort'), const Color(0xFFFF5722), onCaptureVideo),
      _AttachTileData(LucideIcons.image, t('conversationChat.attachImageShort'), const Color(0xFF9C27B0), onAttachImage),
      _AttachTileData(LucideIcons.images, t('conversationChat.attachAlbumShort'), const Color(0xFF7C4DFF), onAttachAlbum),
      _AttachTileData(LucideIcons.clapperboard, t('conversationChat.attachVideoShort'), const Color(0xFFFF9800), onAttachVideo),
      _AttachTileData(LucideIcons.mic, t('conversationChat.voiceShort'), const Color(0xFFF44336), onVoice),
      _AttachTileData(LucideIcons.mapPin, t('conversationChat.locationShort'), const Color(0xFF43A047), onLocation),
      _AttachTileData(LucideIcons.fileText, t('conversationChat.fileShort'), const Color(0xFF5C6BC0), onFile),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('conversationChat.attachSheetTitle'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            t('conversationChat.attachSheetSubtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.textMuted, height: 1.35),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (_, i) => _AttachTile(data: items[i]),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _AttachTileData {
  const _AttachTileData(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _AttachTile extends StatelessWidget {
  const _AttachTile({required this.data});
  final _AttachTileData data;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(data.color, Colors.white, 0.12)!,
                    data.color,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: data.color.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(data.icon, size: 24, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              data.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationBubble extends StatelessWidget {
  const _LocationBubble({required this.location, required this.mine, required this.fg});
  final LocationShare location;
  final bool mine;
  final Color fg;

  Future<void> _openMaps() async {
    final uri = Uri.parse(location.mapsUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(location.lat, location.lng);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openMaps,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 248,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: SizedBox(
                  height: 140,
                  child: IgnorePointer(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: point,
                        initialZoom: 15.2,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                        backgroundColor: mine ? const Color(0xFF1F5C4F) : const Color(0xFFE8EEF7),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'site.nexchat.nexchat',
                          maxZoom: 19,
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: point,
                              width: 44,
                              height: 44,
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 8, offset: const Offset(0, 2)),
                                  ],
                                ),
                                padding: const EdgeInsets.all(7),
                                child: const Icon(LucideIcons.mapPin, size: 22, color: Color(0xFFE53935)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w700, height: 1.25),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t('conversationChat.openInMaps'),
                      style: TextStyle(color: fg.withValues(alpha: 0.75), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileBubble extends StatelessWidget {
  const _FileBubble({required this.file, required this.mine, required this.fg});
  final FileShare file;
  final bool mine;
  final Color fg;

  Color get _accent {
    return switch (file.ext) {
      'pdf' => const Color(0xFFE53935),
      'doc' || 'docx' || 'rtf' || 'odt' => const Color(0xFF1E88E5),
      'zip' || 'rar' || '7z' => const Color(0xFFF9A825),
      'txt' => const Color(0xFF43A047),
      _ => const Color(0xFF6C63FF),
    };
  }

  IconData get _icon {
    return switch (file.ext) {
      'pdf' => LucideIcons.fileText,
      'doc' || 'docx' || 'rtf' || 'odt' => LucideIcons.fileType,
      'zip' || 'rar' || '7z' => LucideIcons.folderArchive,
      'txt' => LucideIcons.file,
      _ => LucideIcons.file,
    };
  }

  Future<void> _open() async {
    final absolute = Api.absoluteUrl(file.url) ?? file.url;
    await launchUrl(Uri.parse(absolute), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final sizeLabel = formatFileSize(file.size);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 248,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: mine ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(_icon, size: 24, color: mine ? Colors.white : _accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w700, height: 1.25),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (file.ext.isNotEmpty) file.ext.toUpperCase(),
                        if (sizeLabel.isNotEmpty) sizeLabel,
                      ].join(' · '),
                      style: TextStyle(color: fg.withValues(alpha: 0.72), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.download, size: 18, color: fg.withValues(alpha: 0.75)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewOncePlaceholder extends StatelessWidget {
  const _ViewOncePlaceholder({
    required this.type,
    required this.opened,
    required this.fg,
    this.onTap,
    this.senderOpenedHint = false,
  });

  final String type;
  final bool opened;
  final Color fg;
  final VoidCallback? onTap;
  /// Sender sees that the recipient opened it, but media stays hidden in the bubble.
  final bool senderOpenedHint;

  @override
  Widget build(BuildContext context) {
    final isVideo = type == 'video';
    final String title;
    final String? subtitle;
    if (opened) {
      title = t('conversationChat.viewOnceOpened');
      subtitle = null;
    } else if (senderOpenedHint) {
      title = isVideo ? t('conversationChat.viewOnceVideo') : t('conversationChat.viewOncePhoto');
      subtitle = t('conversationChat.viewOnceOpened');
    } else {
      title = isVideo ? t('conversationChat.viewOnceVideo') : t('conversationChat.viewOncePhoto');
      subtitle = t('conversationChat.viewOnceTapToOpen');
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fg.withValues(alpha: 0.15),
              ),
              child: Icon(
                opened ? LucideIcons.eyeOff : (isVideo ? LucideIcons.video : LucideIcons.eye),
                size: 20,
                color: fg,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryShareBubble extends StatelessWidget {
  const _StoryShareBubble({required this.share, required this.mine, required this.fg, required this.onOpen});

  final StoryShareRef share;
  final bool mine;
  final Color fg;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 72,
        height: 96,
        child: share.isText
            ? DecoratedBox(
                decoration: storyBackgroundDecoration(share.backgroundColor),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      (share.caption ?? '').trim().isEmpty ? t('stories.allStory') : share.caption!,
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
                    image: mediaImage(share.mediaUrl!, cacheWidth: bubbleImageCacheWidth),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: Colors.black26,
                      child: Icon(share.isVideo ? LucideIcons.video : LucideIcons.image, color: Colors.white70, size: 22),
                    ),
                  ),
                  if (share.isVideo) const Center(child: Icon(LucideIcons.play, color: Colors.white, size: 22)),
                ],
              ),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
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
                      t('share.storyShareOf', {'name': share.name}),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('share.storyShareHint'),
                      style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
            ],
          ),
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

/// WhatsApp-style day separator pill between message groups.
class _ChatDateChip extends StatelessWidget {
  const _ChatDateChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.border),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textSecondary, height: 1.2),
          ),
        ),
      ),
    );
  }
}

/// End-to-end encryption notice shown at the start of every conversation.
class _ChatEncryptionBanner extends StatelessWidget {
  const _ChatEncryptionBanner();

  Future<void> _openSheet(BuildContext context) {
    final c = context.colors;
    return showAppSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Spacer(),
                GlassIconButton(
                  icon: LucideIcons.x,
                  color: c.textMuted,
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brandGradient,
                boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              alignment: Alignment.center,
              child: const Icon(LucideIcons.lockKeyhole, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Text(
              t('conversationChat.encryptionSheetTitle'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.textPrimary, height: 1.35),
            ),
            const SizedBox(height: 10),
            Text(
              t('conversationChat.encryptionSheetBody'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: c.textSecondary, height: 1.55, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.bgElevated,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  _EncryptionFeature(icon: LucideIcons.messageCircle, label: t('conversationChat.encryptionFeatureMessages')),
                  _EncryptionFeature(icon: LucideIcons.phone, label: t('conversationChat.encryptionFeatureCalls')),
                  _EncryptionFeature(icon: LucideIcons.paperclip, label: t('conversationChat.encryptionFeatureMedia')),
                  _EncryptionFeature(icon: LucideIcons.mapPin, label: t('conversationChat.encryptionFeatureLocation')),
                  _EncryptionFeature(icon: LucideIcons.circleDashed, label: t('conversationChat.encryptionFeatureStatus')),
                ],
              ),
            ),
            const SizedBox(height: 18),
            GradientButton(
              label: t('conversationChat.encryptionLearnMore'),
              icon: LucideIcons.shield,
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/privacy');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Color.alphaBlend(c.primary.withValues(alpha: 0.18), c.bgCard) : const Color(0xFFEFF6FF);
    final fg = isDark ? c.textPrimary : const Color(0xFF1E3A5F);
    final border = c.primary.withValues(alpha: isDark ? 0.28 : 0.18);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: () => _openSheet(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.primary.withValues(alpha: 0.14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(LucideIcons.lock, size: 13, color: c.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 12.5, height: 1.45, color: fg, fontWeight: FontWeight.w500),
                      children: [
                        TextSpan(text: '${t('conversationChat.encryptionBanner')} '),
                        TextSpan(
                          text: t('conversationChat.encryptionLearnMore'),
                          style: TextStyle(color: c.primary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EncryptionFeature extends StatelessWidget {
  const _EncryptionFeature({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: c.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textPrimary, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
