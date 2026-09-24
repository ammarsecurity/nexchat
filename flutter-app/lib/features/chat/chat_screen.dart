import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/feature_flags.dart';
import '../../core/format.dart';
import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hubs.dart';
import '../../core/network/network_status.dart';
import '../../core/theme/app_colors.dart';
import '../../services/media.dart';
import '../../shared/media_widgets.dart';
import '../../shared/widgets.dart';
import '../auth/auth_controller.dart';
import '../calls/active_call_bar.dart';
import '../calls/call_state.dart';
import '../calls/video_call_screen.dart';
import '../conversations/conversation_chat_screen.dart' show TypingBubble;
import '../matching/matching_controller.dart';
import 'chat_session.dart';

const _emojiCategories = [
  ('😀', ['😀','😃','😄','😁','😆','😅','😂','🤣','😊','😇','🥰','😍','🤩','😘','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒','🙄','😬','😌','😔','😪','😴','😷','🤒','🤕','🤢','🤮','🤧','🥵','🥶','😵','🤯','🥳','😎','🤓','🧐','😕','🙁','😮','😯','😲','😳','🥺','😦','😧','😨','😢','😭','😱','😖','😞','😓','😩','😫','😤','😡','😠','🤬','😈','💀','👻','💩','🤡','👹','👺','👽','👾','🤖']),
  ('👋', ['👋','🤚','🖐','✋','👌','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️','👍','👎','✊','👊','👏','🙌','🙏','💪','🤝','🫶','💅','🤳']),
  ('❤️', ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖','💘','💝','💯','✨','🌟','⭐','🔥','🎉','🎊','🎈','🎁','🏆','🥇','🎯','🎮','🎲','🎭','🎪','🎨','🎵','🎶','🎤','🎸','🎹','🎺','🥁']),
  ('🐶', ['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🐔','🐧','🐦','🐤','🦆','🦅','🦉','🦇','🐝','🦋','🐌','🐞','🐢','🐍','🦎','🐙','🦑','🐟','🐬','🐳','🦈','🐊','🐘','🦒','🦓','🦍','🦧','🦬','🐕','🐈','🐓','🦃','🦚','🦜','🦩','🌵','🌲','🌳','🌴','🌱','🌿','☘️','🍀','🍁','🌾','🍄','🌸','🌺','🌻','🌹','🌷','💐','🌊','🌙','⭐','☀️','🌈','⛄','🌍']),
  ('🍕', ['🍕','🍔','🍟','🌭','🌮','🌯','🥙','🍳','🥗','🍲','🍜','🍝','🍣','🍱','🍛','🍚','🍿','🍩','🍪','🎂','🍰','🧁','🍫','🍬','🍭','☕','🍵','🧋','🥤','🧃','🍺','🍷','🥂','🍸','🍹','🥃','🍾','🍎','🍊','🍋','🍇','🍓','🫐','🍒','🍑','🥭','🍍','🥥','🍌','🍉','🍈','🍏']),
];

const _partnerPalette = [Color(0xFF6C63FF), Color(0xFFFF6584), Color(0xFF00D4FF), Color(0xFFFF8C42)];

/// views/ChatView.vue — random / code-connect / support chat session over /hubs/chat.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.sessionId,
    this.initialPartner,
    this.incomingVideoCall = false,
    this.autoAcceptCall = false,
    this.supportChat = false,
  });
  final String sessionId;
  final Json? initialPartner;
  final bool incomingVideoCall;
  final bool autoAcceptCall;
  final bool supportChat;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  static final _sessionTimers = <String, int>{};

  final _text = TextEditingController();
  final _input = FocusNode();
  final List<void Function()> _offs = [];
  StreamSubscription<void>? _reconnectSub;
  late final ChatSessionController _chat = ref.read(chatSessionProvider.notifier);
  late final MatchingController _matching = ref.read(matchingProvider.notifier);
  late final GoRouter _router = ref.read(routerProvider);

  bool _sessionEnded = false;
  int _timerSeconds = 0;
  Timer? _timer;
  Timer? _partnerWaitTimer;
  Timer? _typingTimeout;
  bool _mounted = true;
  bool _leavingProgrammatically = false;
  bool _goToNextInProgress = false;
  bool _routeCurrent = true;
  bool _partnerWaitPaused = false;
  void Function()? _deferredNav;
  bool _loading = false;
  bool _codeConnectEnabled = true;

  bool _showReport = false;
  String? _reportSnippet;
  final _reportReason = TextEditingController();
  bool _showReportSuccess = false;
  bool _showBlockConfirm = false;
  String _blockError = '';
  bool _showShareModal = false;
  bool _shareCodeCopied = false;
  bool _incomingCall = false;
  bool _callDeclined = false;
  bool _showVideoConfirm = false;
  bool _callingOut = false;
  Timer? _outgoingRing;
  bool _showEmojiPicker = false;
  int _emojiTab = 0;
  bool _uploadingImage = false;

  String get _sid => widget.sessionId;
  String? get _myId => ref.read(authProvider).user?.id;
  Json? get _partner => ref.read(chatSessionProvider).partner;
  bool get _isSupportChat => widget.supportChat || _partner?.s('name') == 'دعم';
  bool get _partnerIsFeatured => _partner?.b('isFeatured') ?? false;
  String? get _partnerUserId {
    final p = _partner;
    if (p == null) return null;
    final id = p.s('id') ?? p.s('userId');
    return id != null && id.isNotEmpty ? id : null;
  }

  @override
  void initState() {
    super.initState();
    (_router, _chat, _matching);
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(() {
      if (_input.hasFocus && _showEmojiPicker) setState(() => _showEmojiPicker = false);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _mount());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cur = ModalRoute.isCurrentOf(context) ?? true;
    if (cur == _routeCurrent) return;
    _routeCurrent = cur;
    if (!cur) {
      if (_partnerWaitTimer != null) {
        _clearPartnerWait();
        _partnerWaitPaused = true;
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_mounted || !_isCurrent) return;
      if (!_goToNextInProgress) _leavingProgrammatically = false;
      final nav = _deferredNav;
      _deferredNav = null;
      if (nav != null) {
        nav();
        return;
      }
      if (_partnerWaitPaused) {
        _partnerWaitPaused = false;
        _startPartnerWait();
      }
    });
  }

  bool get _isCurrent => mounted && (ModalRoute.isCurrentOf(context) ?? true);

  /// Navigation side-effects must not fire while another route (e.g. /video) covers this chat.
  void _whenCurrent(void Function() nav) {
    if (_isCurrent) {
      nav();
    } else {
      _deferredNav = nav;
    }
  }

  Json _normalize(Json m) => {
        'id': m.v('id'),
        'senderId': m.v('senderId'),
        'content': m.v('content'),
        'type': m.s('type') ?? 'text',
        'sentAt': m.v('sentAt'),
      };

  Json? _first(List<Object?> a) => a.isNotEmpty && a[0] is Map ? Json.from(a[0] as Map) : null;

  Future<void> _mount() async {
    if (widget.initialPartner != null && ref.read(chatSessionProvider).sessionId != _sid) {
      _chat.setSession(_sid, widget.initialPartner);
    }
    setState(() => _loading = true);
    _codeConnectEnabled = (await ref.read(featureFlagsProvider.future)).codeConnect;
    if (!_mounted) return;
    if (_isSupportChat && !_codeConnectEnabled) {
      setState(() => _loading = false);
      _router.go('/conversations');
      return;
    }
    try {
      await Hubs.chat.start();
    } catch (_) {}
    final h = Hubs.chat;
    _offs.addAll([
      h.on('ReceiveMessage', (a) {
        final msg = _first(a);
        if (msg == null) return;
        if (_myId != null && msg.str('senderId') == _myId) {
          _chat.updatePendingMessage(_normalize(msg));
        } else {
          _chat.addMessage({..._normalize(msg), 'status': 'sent'});
        }
      }),
      h.on('UserTyping', (_) => _chat.setTyping(true)),
      h.on('UserStoppedTyping', (_) => _chat.setTyping(false)),
      h.on('SessionEnded', (_) {
        _timer?.cancel();
        if (!_isSupportChat) {
          _clearPartnerWait();
          _partnerWaitPaused = false;
          _whenCurrent(_goToNextMatch);
          return;
        }
        if (mounted) setState(() => _sessionEnded = true);
        _chat.addMessage({'id': DateTime.now().millisecondsSinceEpoch, 'type': 'system', 'content': '🔴 انتهت المحادثة', 'sentAt': DateTime.now()});
      }),
      h.on('Error', (_) {
        if (!_mounted || _sessionEnded) return;
        if (!_isSupportChat) _whenCurrent(_goToNextMatch);
      }),
      h.on('SessionJoined', (a) {
        final data = _first(a);
        if (data == null) return;
        final p = data.v('partner') is Map ? Json.from(data.v('partner') as Map) : null;
        final msgs = asJsonList(data.v('messages'));
        if (p != null) {
          final existing = _partner;
          if (existing == null) {
            _chat.setPartner(p);
          } else if (p.s('id') != null && (existing.s('id') ?? existing.s('userId')) == null) {
            _chat.setPartner({...existing, ...p});
          }
          if ((p.s('name') ?? '').isNotEmpty) _clearPartnerWait();
        }
        final cur = ref.read(chatSessionProvider);
        final joinedId = data.s('id');
        if (cur.sessionId == null && joinedId != null) _chat.setSessionId(joinedId);
        if (msgs.isNotEmpty && ref.read(chatSessionProvider).messages.isEmpty) {
          _chat.setMessages([for (final m in msgs) {..._normalize(m), 'status': 'sent'}]);
        }
      }),
      h.on('ReportSent', (_) {
        if (!mounted) return;
        setState(() {
          _showReport = false;
          _showReportSuccess = true;
        });
        Future.delayed(const Duration(milliseconds: 3500), () {
          if (mounted) setState(() => _showReportSuccess = false);
        });
      }),
      h.on('IncomingVideoCall', (_) {
        if (!_isSupportChat && mounted) {
          final active = ref.read(activeCallProvider).sessionId;
          if (active != null && active != _sid) {
            Hubs.chat.invoke('DeclineVideoCall', [_sid]).catchError((_) => null);
            return;
          }
          setState(() => _incomingCall = true);
        }
      }),
      h.on('VideoCallAccepted', (_) {
        _outgoingRing?.cancel();
        if (mounted) setState(() => _callingOut = false);
        _leavingProgrammatically = true;
        _router.push('/video/$_sid', extra: {'initiator': true});
      }),
      h.on('VideoCallDeclined', (_) {
        if (!mounted) return;
        _outgoingRing?.cancel();
        setState(() {
          _callingOut = false;
          _callDeclined = true;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _callDeclined = false);
        });
      }),
    ]);

    if (!ref.read(networkProvider)) {
      if (mounted) setState(() => _loading = false);
    } else {
      try {
        await Hubs.chat.invoke('JoinSession', [_sid]);
      } catch (_) {
        if (_isSupportChat) {
          _leavingProgrammatically = true;
          _chat.clear();
          _router.go('/settings');
        } else {
          await _goToNextMatch();
        }
      } finally {
        if (!_goToNextInProgress && mounted) setState(() => _loading = false);
      }
    }

    if (!_goToNextInProgress && _mounted && widget.incomingVideoCall) {
      if (!_isSupportChat) {
        setState(() => _incomingCall = true);
        if (widget.autoAcceptCall) unawaited(_acceptCall());
      }
      _router.replace('/chat/$_sid');
    }

    if (!_goToNextInProgress && _mounted && (_partner?.s('name') ?? '').isEmpty && ref.read(networkProvider)) {
      if (_isCurrent) {
        _startPartnerWait();
      } else {
        _partnerWaitPaused = true;
      }
    }

    _reconnectSub = Hubs.chat.onReconnected.listen((_) async {
      if (!_mounted || _sessionEnded) return;
      try {
        await Hubs.chat.invoke('JoinSession', [_sid]);
      } catch (_) {
        if (!_isSupportChat) {
          _whenCurrent(_goToNextMatch);
        } else {
          _whenCurrent(() {
            _leavingProgrammatically = true;
            _chat.clear();
            _router.go('/settings');
          });
        }
      }
    });

    if (ref.read(chatSessionProvider).sessionId == _sid) _timerSeconds = _sessionTimers[_sid] ?? 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sessionEnded || !mounted) return;
      setState(() => _timerSeconds++);
      _sessionTimers[_sid] = _timerSeconds;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_sessionEnded && NetworkStatus.online.value) {
      Hubs.chat.invoke('JoinSession', [_sid]).catchError((_) => null);
    }
  }

  @override
  void dispose() {
    _mounted = false;
    WidgetsBinding.instance.removeObserver(this);
    _clearPartnerWait();
    _timer?.cancel();
    _outgoingRing?.cancel();
    _typingTimeout?.cancel();
    _reconnectSub?.cancel();
    for (final off in _offs) {
      off();
    }
    if (!_sessionEnded && !_leavingProgrammatically) {
      final to = _router.routerDelegate.currentConfiguration.uri.path;
      if (to != '/video/$_sid' && NetworkStatus.online.value) {
        Hubs.chat.invoke('LeaveSession', [_sid]).catchError((_) => null);
      }
    }
    _text.dispose();
    _input.dispose();
    _reportReason.dispose();
    super.dispose();
  }

  void _clearPartnerWait() {
    _partnerWaitTimer?.cancel();
    _partnerWaitTimer = null;
  }

  void _startPartnerWait() {
    _clearPartnerWait();
    if (!_mounted || _goToNextInProgress || _sessionEnded) return;
    if (_isSupportChat || (_partner?.s('name') ?? '').isNotEmpty) return;
    _partnerWaitTimer = Timer(const Duration(seconds: 20), () {
      _partnerWaitTimer = null;
      if (!_mounted || _goToNextInProgress || _sessionEnded) return;
      if (_isSupportChat || (_partner?.s('name') ?? '').isNotEmpty) return;
      _whenCurrent(_goToNextMatch);
    });
  }

  Future<void> _goToNextMatch() async {
    if (_goToNextInProgress || !_mounted || _isSupportChat) return;
    if (!NetworkStatus.online.value) {
      _leavingProgrammatically = true;
      _chat.clear();
      _matching.setIdle();
      _router.go('/home');
      return;
    }
    _goToNextInProgress = true;
    _leavingProgrammatically = true;
    if (mounted) setState(() => _loading = true);
    _timer?.cancel();
    _clearPartnerWait();
    try {
      await Hubs.chat.invoke('LeaveSession', [_sid]);
    } catch (_) {}
    _chat.clear();
    _matching
      ..setSearching()
      ..setResumeSearchAfterNav(true);
    _router.pushReplacement('/matching');
  }

  bool _requireOnline({bool send = false}) {
    if (ref.read(networkProvider)) return true;
    if (mounted) showToast(context, t(send ? 'noConnection.sendFailed' : 'noConnection.actionFailed'), error: true);
    return false;
  }

  String _tempId() => 'temp-${DateTime.now().millisecondsSinceEpoch}-${UniqueKey().hashCode.toRadixString(36)}';

  Future<void> _sendRaw(String content, String type) async {
    if (!_requireOnline(send: true)) return;
    final tempId = _tempId();
    _chat.addMessage({'tempId': tempId, 'senderId': _myId, 'content': content, 'type': type, 'sentAt': DateTime.now(), 'status': 'pending'});
    try {
      await Hubs.chat.invoke('SendMessage', [_sid, content, type]);
    } catch (_) {
      _chat.updateMessage(tempId, {'status': 'failed'});
    }
  }

  void _onInput(String _) {
    setState(() {});
    if (!ref.read(networkProvider)) return;
    if (_typingTimeout == null) Hubs.chat.invoke('StartTyping', [_sid]).catchError((_) => null);
    _typingTimeout?.cancel();
    _typingTimeout = Timer(const Duration(milliseconds: 1500), () {
      Hubs.chat.invoke('StopTyping', [_sid]).catchError((_) => null);
      _typingTimeout = null;
    });
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sessionEnded) return;
    _text.clear();
    setState(() {});
    if (_typingTimeout != null) {
      _typingTimeout!.cancel();
      _typingTimeout = null;
      Hubs.chat.invoke('StopTyping', [_sid]).catchError((_) => null);
    }
    await _sendRaw(text, 'text');
  }

  Future<void> _retry(Json msg) async {
    if (msg['status'] != 'failed') return;
    if (!_requireOnline(send: true)) return;
    final tempId = _tempId();
    _chat.updateMessage('${msg['tempId']}', {'tempId': tempId, 'status': 'pending'});
    try {
      await Hubs.chat.invoke('SendMessage', [_sid, msg.str('content'), msg.s('type') ?? 'text']);
    } catch (_) {
      _chat.updateMessage(tempId, {'status': 'failed'});
    }
  }

  Future<void> _pickAndSendImage() async {
    if (!_requireOnline(send: true)) return;
    final file = await pickImage();
    if (file == null) return;
    setState(() => _uploadingImage = true);
    try {
      final url = await uploadFile('media/upload', file.path, filename: file.name);
      await _sendRaw(url, 'image');
    } catch (e) {
      if (mounted) showToast(context, Api.errorMessage(e, t('common.error')), error: true);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _leaveSession() async {
    _leavingProgrammatically = true;
    setState(() => _loading = true);
    _timer?.cancel();
    final support = _isSupportChat;
    try {
      if (NetworkStatus.online.value) await Hubs.chat.invoke('LeaveSession', [_sid]);
      _chat.clear();
      _matching.setIdle();
      _router.go(support ? '/settings' : '/home');
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitReport() async {
    if (!_requireOnline()) return;
    var reason = _reportReason.text.trim();
    final snap = _reportSnippet?.trim();
    if (reason.isEmpty && (snap?.isNotEmpty ?? false)) reason = t('randomChat.reportContentDefault');
    if (reason.isEmpty) return;
    setState(() => _loading = true);
    try {
      await Hubs.chat.invoke('ReportUser', [_sid, reason, snap ?? '']);
      _reportReason.clear();
      if (mounted) {
        setState(() {
          _reportSnippet = null;
          _showReport = false;
        });
      }
    } catch (_) {
      if (mounted) showToast(context, t('common.error'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openReport([Json? msg]) {
    setState(() {
      _reportSnippet = msg == null ? null : (msg.s('type') == 'image' ? '[image]' : _truncate(msg.str('content').trim(), 400));
      _reportReason.clear();
      _showReport = true;
    });
  }

  String _truncate(String s, int n) => s.length > n ? s.substring(0, n) : s;

  Future<void> _confirmBlock() async {
    final pid = _partnerUserId;
    if (pid == null) return;
    setState(() {
      _blockError = '';
      _loading = true;
    });
    try {
      await Api.post('/blocks/$pid');
    } catch (e) {
      final m = Api.errorMessage(e);
      setState(() {
        _blockError = m.isNotEmpty ? m : t('randomChat.blockError');
        _loading = false;
      });
      return;
    }
    _leavingProgrammatically = true;
    _timer?.cancel();
    try {
      await Hubs.chat.invoke('LeaveSession', [_sid]);
    } catch (_) {}
    _chat.clear();
    _matching.setIdle();
    _router.go('/home');
  }

  Future<void> _confirmStartVideo() async {
    if (!_requireOnline()) {
      if (mounted) setState(() => _showVideoConfirm = false);
      return;
    }
    final active = ref.read(activeCallProvider);
    if (active.sessionId != null) {
      if (mounted) setState(() => _showVideoConfirm = false);
      if (active.sessionId == _sid) {
        ref.read(activeCallProvider.notifier).expand();
        _router.push('/video/$_sid', extra: {'initiator': true});
      } else {
        showToast(context, t('videoCall.alreadyInCall'), error: true);
      }
      return;
    }
    setState(() {
      _showVideoConfirm = false;
      _callingOut = true;
    });
    _outgoingRing?.cancel();
    _outgoingRing = Timer(kIncomingCallRingTimeout, () {
      if (!mounted || !_callingOut) return;
      _cancelOutgoingCall();
    });
    try {
      await Hubs.chat.invoke('RequestVideoCall', [_sid]);
    } catch (_) {
      _outgoingRing?.cancel();
      if (mounted) setState(() => _callingOut = false);
    }
  }

  Future<void> _acceptCall() async {
    if (!_requireOnline()) return;
    final active = ref.read(activeCallProvider);
    if (active.sessionId != null && active.sessionId != _sid) {
      _declineCall();
      if (mounted) showToast(context, t('videoCall.alreadyInCall'), error: true);
      return;
    }
    setState(() => _incomingCall = false);
    try {
      await Hubs.chat.invoke('AcceptVideoCall', [_sid]);
    } catch (_) {
      if (mounted) {
        setState(() => _incomingCall = true);
        showToast(context, t('common.error'), error: true);
      }
      return;
    }
    if (!mounted) return;
    _leavingProgrammatically = true;
    openVideoRoute(_router, _sid, {'initiator': false, 'voiceOnly': false});
  }

  void _declineCall() {
    setState(() => _incomingCall = false);
    Hubs.chat.invoke('DeclineVideoCall', [_sid]).catchError((_) => null);
  }

  void _cancelOutgoingCall() {
    _outgoingRing?.cancel();
    setState(() => _callingOut = false);
    Hubs.chat.invoke('DeclineVideoCall', [_sid]).catchError((_) => null);
  }

  Future<void> _copyShareCode() async {
    final code = ref.read(authProvider).user?.uniqueCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    setState(() => _shareCodeCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _shareCodeCopied = false);
    });
  }

  void _shareCodeInChat() {
    final code = ref.read(authProvider).user?.uniqueCode;
    if (code == null || _sessionEnded) return;
    setState(() => _showShareModal = false);
    _sendRaw('كودي للاتصال: $code', 'text');
  }

  DateTime? _dt(Object? v) => v is DateTime ? v : {'x': v}.date('x');

  String _fmtTimer(int sec) => '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

  Widget _partnerAvatar(Json? p, double size, {double fontSize = 16}) {
    final name = p?.str('name') ?? '';
    final a = p?.s('avatar')?.trim() ?? '';
    final isImage = a.startsWith('http') || a.startsWith('/');
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final color = name.isEmpty ? _partnerPalette.first : _partnerPalette[name.codeUnitAt(0) % _partnerPalette.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: isImage ? null : color),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: isImage
          ? CachedNetworkImage(imageUrl: Api.absoluteUrl(a)!, width: size, height: size, fit: BoxFit.cover)
          : Text(a.isNotEmpty ? a : letter, style: TextStyle(fontSize: a.isNotEmpty ? fontSize * 1.6 : fontSize, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(networkProvider, (prev, next) {
      if (prev == false && next == true && !_sessionEnded) {
        Hubs.chat.start().then((_) => Hubs.chat.invoke('JoinSession', [_sid])).catchError((_) => null);
      }
    });
    final c = context.colors;
    final session = ref.watch(chatSessionProvider);
    final partner = session.partner;
    final messages = session.messages;
    final me = ref.watch(authProvider.select((s) => s.user?.id));
    final support = _isSupportChat;
    final featured = _partnerIsFeatured;
    final pad = MediaQuery.paddingOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final partnerName = partner?.s('name') ?? '';

    PopupMenuItem<String> menuItem(String value, IconData icon, String label, {bool danger = false}) => PopupMenuItem(
          value: value,
          height: 44,
          child: Row(children: [
            Icon(icon, size: 18, color: danger ? c.danger : c.textPrimary),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: danger ? c.danger : c.textPrimary)),
          ]),
        );

    final header = Container(
      padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, 16),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.md)),
        border: Border(left: BorderSide(color: c.border), right: BorderSide(color: c.border), bottom: BorderSide(color: c.border)),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            padding: featured ? const EdgeInsets.all(2) : EdgeInsets.zero,
            decoration: featured
                ? const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)]))
                : null,
            child: _partnerAvatar(partner, 40),
          ),
          if (featured)
            const PositionedDirectional(
              top: -8,
              end: -4,
              child: Icon(LucideIcons.crown, size: 18, color: Color(0xFFFFD700), shadows: [Shadow(color: Color(0x55000000), blurRadius: 2)]),
            ),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(partnerName.isNotEmpty ? partnerName : t('common.loading'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
            Text(
              session.partnerTyping ? 'يكتب...' : (support ? 'دردشة الدعم' : _fmtTimer(_timerSeconds)),
              style: TextStyle(fontSize: 13, color: session.partnerTyping ? c.primary : c.textMuted),
            ),
          ]),
        ),
        if (!support) ...[
          PopupMenuButton<String>(
            tooltip: t('randomChat.moreMenu'),
            color: c.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: c.border)),
            position: PopupMenuPosition.under,
            onSelected: (v) {
              switch (v) {
                case 'video':
                  setState(() => _showVideoConfirm = true);
                case 'report':
                  _openReport();
                case 'block':
                  setState(() {
                    _blockError = '';
                    _showBlockConfirm = true;
                  });
                case 'leave':
                  _leaveSession();
              }
            },
            itemBuilder: (_) => [
              menuItem('video', LucideIcons.video, t('randomChat.videoCall')),
              if (featured && _partnerUserId != null)
                menuItem('block', LucideIcons.ban, t('randomChat.block'), danger: true)
              else ...[
                if (!featured) menuItem('report', LucideIcons.flag, t('randomChat.report')),
                if (_partnerUserId != null) menuItem('block', LucideIcons.ban, t('randomChat.block'), danger: true),
              ],
              const PopupMenuDivider(),
              menuItem('leave', LucideIcons.x, t('randomChat.endChat'), danger: true),
            ],
            child: SizedBox(width: 40, height: 40, child: Icon(LucideIcons.ellipsisVertical, size: 20, color: c.textPrimary)),
          ),
          IconButton(
            tooltip: t('randomChat.next'),
            onPressed: _goToNextMatch,
            icon: Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 20, color: c.primary),
          ),
        ] else
          IconButton(
            tooltip: t('common.back'),
            onPressed: _leaveSession,
            icon: Icon(rtl ? LucideIcons.chevronLeft : LucideIcons.chevronRight, size: 20, color: c.textPrimary),
          ),
      ]),
    );

    bool canReport(Json m) => !support && !featured && m.s('type') != 'system' && m.str('senderId') != (me ?? '');

    Widget messageRow(Json m) {
      final type = m.s('type') ?? 'text';
      if (type == 'system') {
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: c.systemMsgBg, borderRadius: BorderRadius.circular(20)),
            child: Text(m.str('content'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.textMuted)),
          ),
        );
      }
      final mine = m.str('senderId') == (me ?? '') && me != null;
      final content = m.str('content');
      final bubble = type == 'image'
          ? GestureDetector(
              onTap: () => showImageViewer(context, [content]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220, maxHeight: 280),
                  child: Image(image: mediaImage(content, cacheWidth: bubbleImageCacheWidth), fit: BoxFit.cover),
                ),
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? null : c.msgTheirsBg,
                gradient: mine ? AppColors.msgMineGradient : null,
                borderRadius: BorderRadiusDirectional.only(
                  topStart: const Radius.circular(16),
                  topEnd: const Radius.circular(16),
                  bottomStart: Radius.circular(mine ? 16 : 4),
                  bottomEnd: Radius.circular(mine ? 4 : 16),
                ),
              ),
              child: LinkifiedText(
                content,
                style: TextStyle(fontSize: 15, height: 1.5, color: mine ? Colors.white : c.msgTheirsColor),
                linkColor: mine ? Colors.white : c.primary,
              ),
            );
      final status = m['status'];
      final at = _dt(m['sentAt']);
      return Align(
        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            if (!mine && canReport(m))
              Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Flexible(child: bubble),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Material(
                    color: c.bgCard,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c.border)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _openReport(m),
                      child: SizedBox(width: 26, height: 26, child: Icon(LucideIcons.flag, size: 12, color: c.textSecondary)),
                    ),
                  ),
                ),
              ])
            else
              bubble,
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (at != null) Text(formatTime12(at), style: TextStyle(fontSize: 11, color: c.textMuted)),
                if (mine) ...[
                  const SizedBox(width: 4),
                  if (status == 'pending')
                    Icon(LucideIcons.clock, size: 14, color: c.textMuted)
                  else if (status == 'failed') ...[
                    Icon(LucideIcons.circleAlert, size: 14, color: c.danger),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _retry(m),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(LucideIcons.rotateCcw, size: 12, color: c.danger),
                        const SizedBox(width: 2),
                        Text('إعادة', style: TextStyle(fontSize: 11, color: c.danger, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ] else
                    Icon(LucideIcons.check, size: 14, color: c.primary),
                ],
              ]),
            ),
          ]),
        ),
      );
    }

    final showTyping = session.partnerTyping;
    final itemCount = messages.length + (showTyping ? 1 : 0);
    final list = messages.isEmpty && !showTyping
        ? Center(child: Text('ابدأ المحادثة بأول رسالة! 👋', style: TextStyle(fontSize: 14, color: c.textMuted)))
        : ListView.builder(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: itemCount,
            itemBuilder: (_, i) {
              if (showTyping && i == 0) return const TypingBubble();
              final m = messages[messages.length - 1 - (i - (showTyping ? 1 : 0))];
              return Padding(padding: const EdgeInsets.only(top: 8), child: messageRow(m));
            },
          );

    final canSend = _text.text.trim().isNotEmpty && !_sessionEnded;
    final inputArea = _sessionEnded && support
        ? Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + pad.bottom),
            decoration: BoxDecoration(color: c.bgCard, border: Border(top: BorderSide(color: c.border))),
            child: Row(children: [
              Expanded(child: Text('انتهت المحادثة', style: TextStyle(color: c.textSecondary))),
              TextButton.icon(
                onPressed: _leaveSession,
                icon: Icon(rtl ? LucideIcons.chevronRight : LucideIcons.chevronLeft, size: 18, color: c.primary),
                label: Text('رجوع', style: TextStyle(color: c.primary, fontWeight: FontWeight.w700)),
              ),
            ]),
          )
        : Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + pad.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!support && _codeConnectEnabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        _showShareModal = true;
                        _shareCodeCopied = false;
                      }),
                      child: Ink(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0x1F6C63FF), Color(0x0F6C63FF)]),
                          border: Border.all(color: const Color(0x406C63FF)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(LucideIcons.share2, size: 18, color: c.primary),
                          const SizedBox(width: 8),
                          Text('مشاركة كودك', style: TextStyle(color: c.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
              if (_showEmojiPicker)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  height: 240,
                  decoration: BoxDecoration(
                    color: c.bgCard,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: c.border),
                    boxShadow: [BoxShadow(color: c.shadow, blurRadius: 20, offset: const Offset(0, 6))],
                  ),
                  child: Column(children: [
                    Container(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
                      child: Row(children: [
                        for (final (i, cat) in _emojiCategories.indexed)
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _emojiTab = i),
                              child: Container(
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: _emojiTab == i ? c.primary : Colors.transparent, width: 2)),
                                ),
                                child: Text(cat.$1, style: const TextStyle(fontSize: 20)),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 8,
                        padding: const EdgeInsets.all(6),
                        children: [
                          for (final e in _emojiCategories[_emojiTab].$2)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() {
                                _text.text += e;
                                _showEmojiPicker = false;
                              }),
                              child: Center(child: Text(e, style: const TextStyle(fontSize: 24))),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                PopupMenuButton<String>(
                  tooltip: t('conversationChat.inputMenuTitle'),
                  enabled: !_uploadingImage,
                  color: c.bgCard,
                  position: PopupMenuPosition.over,
                  offset: const Offset(0, -110),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: c.border)),
                  onSelected: (v) {
                    if (v == 'emoji') {
                      _input.unfocus();
                      setState(() => _showEmojiPicker = !_showEmojiPicker);
                    } else {
                      _pickAndSendImage();
                    }
                  },
                  itemBuilder: (_) => [
                    menuItem('emoji', LucideIcons.smile, t('conversationChat.openEmoji')),
                    menuItem('image', LucideIcons.image, t('conversationChat.attachImage')),
                  ],
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _showEmojiPicker ? c.primarySoft : c.bgCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border),
                    ),
                    child: _uploadingImage
                        ? Padding(padding: const EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
                        : Icon(LucideIcons.ellipsisVertical, size: 20, color: _showEmojiPicker ? c.primary : c.textSecondary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    decoration: BoxDecoration(color: c.bgCard, borderRadius: BorderRadius.circular(24), border: Border.all(color: c.border)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _text,
                      focusNode: _input,
                      enabled: !_sessionEnded,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      onChanged: _onInput,
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                      decoration: InputDecoration(
                        hintText: t('conversationChat.messagePlaceholder'),
                        hintStyle: TextStyle(color: c.textMuted),
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Opacity(
                  opacity: canSend ? 1 : 0.5,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7C75FF), Color(0xFF6C63FF), Color(0xFF5B54E8)]),
                      boxShadow: [BoxShadow(color: Color(0x596C63FF), blurRadius: 12, offset: Offset(0, 4))],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: canSend ? _send : null,
                        child: Icon(rtl ? LucideIcons.sendHorizontal : LucideIcons.send, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ]),
            ]),
          );

    Widget dim({required Widget child, VoidCallback? onTap, Color color = const Color(0xB3000000)}) => Positioned.fill(
          child: GestureDetector(
            onTap: onTap,
            child: ColoredBox(color: color, child: Center(child: GestureDetector(onTap: () {}, child: child))),
          ),
        );

    Widget card({required List<Widget> children, double width = 300, EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 28)}) =>
        Container(
          width: width,
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
          padding: padding,
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: c.border),
            boxShadow: [BoxShadow(color: c.shadow, blurRadius: 20, offset: const Offset(0, 6))],
          ),
          child: Material(color: Colors.transparent, child: Column(mainAxisSize: MainAxisSize.min, children: children)),
        );

    Widget callBtn(IconData icon, String label, VoidCallback onTap, {required bool accept}) => Expanded(
          child: Material(
            color: accept ? c.success : const Color(0x33FF6584),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              side: accept ? BorderSide.none : const BorderSide(color: Color(0x4DFF6584)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: onTap,
              child: SizedBox(
                height: 46,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 18, color: accept ? Colors.white : c.danger),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(color: accept ? Colors.white : c.danger, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        );

    Widget callPopup({required String label, required Widget actions}) => dim(
          child: card(children: [
            _partnerAvatar(partner, 72, fontSize: 26),
            const SizedBox(height: 12),
            Text(partnerName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
            const SizedBox(height: 12),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textSecondary)),
            const SizedBox(height: 12),
            actions,
          ]),
        );

    final ghostBtn = TextButton.styleFrom(
      foregroundColor: c.textSecondary,
      minimumSize: const Size.fromHeight(44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm), side: BorderSide(color: c.border)),
    );

    return PopScope(
      canPop: !_loading,
      child: Scaffold(
        backgroundColor: c.bgPrimary,
        resizeToAvoidBottomInset: true,
        body: Stack(children: [
          Column(children: [
            header,
            ActiveCallBar(embeddedFor: _sid, conversation: false),
            Expanded(
              child: GestureDetector(onTap: () => FocusScope.of(context).unfocus(), child: list),
            ),
            inputArea,
          ]),
          if (_incomingCall)
            callPopup(
              label: 'يطلب مكالمة فيديو',
              actions: Row(children: [
                callBtn(LucideIcons.x, 'رفض', _declineCall, accept: false),
                const SizedBox(width: 10),
                callBtn(LucideIcons.check, 'قبول', _acceptCall, accept: true),
              ]),
            ),
          if (_showVideoConfirm)
            callPopup(
              label: 'طلب مكالمة فيديو مع $partnerName؟',
              actions: Row(children: [
                callBtn(LucideIcons.x, 'إلغاء', () => setState(() => _showVideoConfirm = false), accept: false),
                const SizedBox(width: 10),
                callBtn(LucideIcons.video, 'طلب', _confirmStartVideo, accept: true),
              ]),
            ),
          if (_callingOut)
            dim(
              child: card(children: [
                SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3, color: c.primary)),
                const SizedBox(height: 16),
                Text(partnerName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
                const SizedBox(height: 8),
                Text('جاري الاتصال...', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                const SizedBox(height: 24),
                Row(children: [callBtn(LucideIcons.x, 'إلغاء الطلب', _cancelOutgoingCall, accept: false)]),
              ]),
            ),
          if (_callDeclined)
            Positioned(
              top: pad.top + 70,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x26FF6584),
                    border: Border.all(color: const Color(0x4DFF6584)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('رفض $partnerName المكالمة',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFFF6584), fontSize: 13)),
                ),
              ),
            ),
          if (_showShareModal && _codeConnectEnabled)
            dim(
              color: const Color(0x99000000),
              onTap: () => setState(() => _showShareModal = false),
              child: card(width: 340, padding: const EdgeInsets.all(20), children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(LucideIcons.share2, size: 20, color: c.primary),
                  const SizedBox(width: 8),
                  Text('مشاركة كود الاتصال', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary)),
                ]),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
                  alignment: Alignment.center,
                  child: Text(ref.read(authProvider).user?.uniqueCode ?? '',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2, color: c.primary)),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: GradientButton(label: t('conversationChat.sendInChat'), icon: LucideIcons.send, height: 46, onPressed: _shareCodeInChat)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SoftButton(
                      label: _shareCodeCopied ? t('common.copied') : t('common.copy'),
                      icon: _shareCodeCopied ? LucideIcons.check : LucideIcons.copy,
                      height: 46,
                      onPressed: _copyShareCode,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _showShareModal = false),
                  child: Text('إلغاء', style: TextStyle(color: c.textSecondary)),
                ),
              ]),
            ),
          if (_showReportSuccess)
            dim(
              color: const Color(0x99000000),
              onTap: () => setState(() => _showReportSuccess = false),
              child: card(width: 320, children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(color: c.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(LucideIcons.circleCheck, size: 56, color: c.success),
                ),
                const SizedBox(height: 16),
                Text('تم إرسال البلاغ بنجاح', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
                const SizedBox(height: 8),
                Text('تم استلام البلاغ وسيتم مراجعته من قبل الفريق',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textSecondary)),
                const SizedBox(height: 20),
                PillButton(label: 'حسناً', onPressed: () => setState(() => _showReportSuccess = false)),
              ]),
            ),
          if (_showReport)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.viewInsetsOf(context).bottom + pad.bottom + 90,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.bgCard,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: c.border),
                    boxShadow: [BoxShadow(color: c.shadow, blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    if (_reportSnippet != null && _reportSnippet!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${t('randomChat.reportedSnippetLabel')}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: _reportSnippet!.length > 120 ? '${_reportSnippet!.substring(0, 120)}…' : _reportSnippet),
                          ]),
                          style: TextStyle(fontSize: 12, color: c.textSecondary),
                        ),
                      ),
                    Text('سبب البلاغ:', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reportReason,
                      autofocus: true,
                      style: TextStyle(color: c.textPrimary),
                      decoration: InputDecoration(hintText: t('randomChat.reportPlaceholder')),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      PillButton(label: 'إرسال', expand: false, onPressed: _submitReport),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton(
                          style: ghostBtn,
                          onPressed: () => setState(() {
                            _showReport = false;
                            _reportSnippet = null;
                          }),
                          child: const Text('إلغاء'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
          if (_showBlockConfirm)
            dim(
              color: const Color(0x99000000),
              onTap: () => setState(() => _showBlockConfirm = false),
              child: card(width: 340, padding: const EdgeInsets.all(20), children: [
                Text(t('randomChat.blockConfirmTitle'),
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
                const SizedBox(height: 8),
                Text(t('randomChat.blockConfirmDesc'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textMuted)),
                if (_blockError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_blockError, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.danger)),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: TextButton(style: ghostBtn, onPressed: () => setState(() => _showBlockConfirm = false), child: Text(t('common.cancel'))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: PillButton(label: t('randomChat.blockConfirm'), color: c.danger, onPressed: _confirmBlock)),
                ]),
              ]),
            ),
          LoaderOverlay(show: _loading, text: t('common.loading')),
        ]),
      ),
    );
  }
}
