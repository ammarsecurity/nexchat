import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_client.dart';
import '../../services/call_native.dart';
import '../../shared/widgets.dart';
import '../conversations/active_conversation.dart';
import 'call_partner.dart';
import 'call_state.dart';
import 'css_filter.dart';
import 'whatsapp_call_ui.dart';

/// Replaces the current route with [path], popping instead when it is already the route underneath (avoids a duplicate chat screen).
void returnToRoute(GoRouter router, String path) {
  final matches = router.routerDelegate.currentConfiguration.matches;
  final below = matches.length >= 2 ? matches[matches.length - 2].matchedLocation : null;
  if (below == path && router.canPop()) {
    router.pop();
  } else {
    router.pushReplacement(path);
  }
}

String? _openingVideoSid;
final _videoScreenMounts = <String, int>{};

int videoScreenMounts(String sessionId) => _videoScreenMounts[sessionId] ?? 0;

/// Shows the call screen for [sessionId], popping back to an existing one instead of stacking a second instance.
void openVideoRoute(GoRouter router, String sessionId, Map<String, Object?> extra) {
  final path = router.routerDelegate.currentConfiguration.uri.path;
  if (path == '/video/$sessionId' || _openingVideoSid == sessionId) return;
  final matches = router.routerDelegate.currentConfiguration.matches;
  final i = matches.lastIndexWhere((m) => m.matchedLocation == '/video/$sessionId');
  if (i >= 0) {
    var above = matches.length - 1 - i;
    if (above > 0) router.routerDelegate.navigatorKey.currentState?.popUntil((_) => above-- <= 0);
    return;
  }
  _openingVideoSid = sessionId;
  final loc = Uri(
    path: '/video/$sessionId',
    queryParameters: {
      if (extra['voiceOnly'] == true) 'voice': '1',
      if (extra['fromConversation'] == true) 'conv': '1',
    },
  ).toString();
  router.push(loc, extra: extra);
  Future<void>.delayed(const Duration(milliseconds: 800), () {
    if (_openingVideoSid == sessionId) _openingVideoSid = null;
  });
}

/// views/VideoCallView.vue
class VideoCallScreen extends ConsumerStatefulWidget {
  const VideoCallScreen({super.key, required this.sessionId, this.voiceOnly = false, this.fromConversation = false});
  final String sessionId;
  final bool voiceOnly;
  final bool fromConversation;

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _Filter {
  const _Filter(this.id, this.matrix);
  final String id;
  final List<double>? matrix;
}

final _filters = [
  const _Filter('none', null),
  _Filter('grayscale', CssFilter.grayscale(1).matrix),
  _Filter('sepia', CssFilter.sepia(0.8).matrix),
  _Filter('vintage', CssFilter.sepia(0.4).then(CssFilter.contrast(1.1)).then(CssFilter.saturate(0.9)).matrix),
  _Filter('warm', CssFilter.sepia(0.3).then(CssFilter.hueRotate(-10)).matrix),
  _Filter('cool', CssFilter.hueRotate(180).then(CssFilter.saturate(0.8)).matrix),
  _Filter('cinematic', CssFilter.contrast(1.2).then(CssFilter.saturate(0.7)).matrix),
];

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> {
  final _lk = LiveKitService.instance;
  late final ActiveCallController _activeCtrl;
  late final GoRouter _router;
  bool _muted = false;
  bool _speakerOn = true;
  bool _cameraOff = false;
  bool _flipping = false;
  bool _reconnecting = false;
  final _duration = ValueNotifier<int>(0);
  bool _connected = false;
  String _error = '';
  bool _initializing = true;
  String _filter = 'none';
  Timer? _timer;
  Timer? _peerWait;
  bool _suppressDisconnectNavigate = false;
  bool _failureReturnStarted = false;
  Room? _room;
  int _ownedGen = 0;

  String get _sid => widget.sessionId;
  bool get _voiceOnly => widget.voiceOnly || (_activeCtrl.current.sessionId == _sid && _activeCtrl.current.voiceOnly);

  @override
  void initState() {
    super.initState();
    _videoScreenMounts[_sid] = videoScreenMounts(_sid) + 1;
    if (_openingVideoSid == _sid) _openingVideoSid = null;
    _activeCtrl = ref.read(activeCallProvider.notifier);
    _router = GoRouter.of(context);
    Future.microtask(() {
      if (mounted) _syncMeta();
    });
    _start();
  }

  bool get _isConversationContext {
    final conv = ref.read(activeConversationProvider);
    return conv.conversationId == _sid || _activeCtrl.current.isConversation || widget.fromConversation;
  }

  CallPartner get _partner => resolveCallPartner(ref, _sid);

  void _syncMeta() {
    final p = _partner;
    final ac = _activeCtrl.current;
    _activeCtrl.syncMeta(
      sessionId: _sid,
      voiceOnly: widget.voiceOnly || ac.voiceOnly,
      isConversation: _isConversationContext,
      partnerName: p.name.isNotEmpty ? p.name : ac.partnerName,
      partnerAvatar: p.avatar ?? ac.partnerAvatar,
      partnerUserId: p.userId ?? ac.partnerUserId,
    );
  }

  void _onRoomChanged() {
    if (!mounted) return;
    if (_room?.remoteParticipants.isNotEmpty ?? false) {
      _setConnected(true);
    } else {
      setState(() {});
    }
  }

  void _setConnected(bool v) {
    if (!mounted) return;
    final became = v && !_connected;
    setState(() => _connected = v);
    if (became) {
      _peerWait?.cancel();
      _peerWait = null;
      unawaited(_applySpeaker());
    }
  }

  String _mediaErrorMessage(Object e) {
    final s = '$e'.toLowerCase();
    if (s.contains('notallowed') || s.contains('permission') || s.contains('denied')) return t('videoCall.permissionDenied');
    if (s.contains('notfound') || s.contains('not found') || s.contains('no device')) return t('videoCall.deviceNotFound');
    return t('videoCall.mediaError');
  }

  Future<void> _start() async {
    try {
      final statuses = await [Permission.microphone, if (!_voiceOnly) Permission.camera].request();
      if (!mounted) return;
      if (statuses.values.any((s) => !s.isGranted && !s.isLimited)) {
        _error = t('videoCall.permissionDenied');
        _exitAfterFailure();
        return;
      }
      final h = _lk.handlers;
      h.onRemoteTrack = (_) => _setConnected(true);
      h.onDisconnected = () {
        _setConnected(false);
        if (_suppressDisconnectNavigate) return;
        _exitAfterFailure();
      };
      h.onParticipantLeft = _goBackAfterCall;
      h.onLocalTrack = (_) {
        if (mounted) setState(() {});
      };
      h.onMediaError = (e) {
        if (mounted) setState(() => _error = _mediaErrorMessage(e));
        _exitAfterFailure();
      };
      h.onReconnecting = (v) {
        if (mounted) setState(() => _reconnecting = v);
      };
      h.onTracksChanged = () {
        if (mounted) setState(() {});
      };
      final p = _partner;
      final reused = await _lk.join(_sid,
          voiceOnly: _voiceOnly, partnerName: p.name.isNotEmpty ? p.name : _activeCtrl.current.partnerName);
      if (reused == null) {
        if (mounted &&
            videoScreenMounts(_sid) <= 1 &&
            !(_activeCtrl.current.minimized && _activeCtrl.current.sessionId == _sid)) {
          _exitAfterFailure();
        }
        return;
      }
      if (!mounted) {
        final ac = _activeCtrl.current;
        if (!(ac.minimized && ac.sessionId == _sid)) unawaited(_lk.leave());
        return;
      }
      _room = _lk.room;
      _ownedGen = _lk.generation;
      _room?.addListener(_onRoomChanged);
      if (reused) {
        final started = _activeCtrl.current.startedAt;
        _duration.value = started == null ? 0 : DateTime.now().difference(started).inSeconds;
      }
      if (reused || (_room?.remoteParticipants.isNotEmpty ?? false)) {
        _setConnected(true);
      } else {
        unawaited(_applySpeaker());
        _peerWait?.cancel();
        _peerWait = Timer(kCallPeerWaitTimeout, () {
          if (!mounted || _connected) return;
          _error = t('videoCall.peerDidNotJoin');
          _exitAfterFailure();
        });
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_connected && mounted) _duration.value++;
      });
    } catch (e) {
      if (!mounted) return;
      final m = Api.errorMessage(e);
      _error = m.isNotEmpty ? m : _mediaErrorMessage(e);
      _exitAfterFailure();
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _applySpeaker() async {
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(_speakerOn, force: _speakerOn);
    } catch (_) {}
    unawaited(CallNative.proximity(_connected && _voiceOnly && !_speakerOn));
  }

  void _exitAfterFailure() {
    if (_failureReturnStarted || videoScreenMounts(_sid) > 1) return;
    _failureReturnStarted = true;
    _suppressDisconnectNavigate = true;
    _timer?.cancel();
    _peerWait?.cancel();
    if (mounted) setState(() => _initializing = false);
    unawaited(_lk.leave());
    _goBackAfterCall();
  }

  void _goBackAfterCall() {
    final toConv = _isConversationContext;
    _activeCtrl.clear();
    if (!mounted) return;
    returnToRoute(_router, toConv ? '/conversation/$_sid' : '/chat/$_sid');
  }

  void _openChatDuringCall() {
    final toConv = _isConversationContext;
    final p = _partner;
    final ac = _activeCtrl.current;
    _activeCtrl.syncMeta(
      sessionId: _sid,
      voiceOnly: _voiceOnly,
      isConversation: toConv,
      partnerName: p.name.isNotEmpty ? p.name : ac.partnerName,
      partnerAvatar: p.avatar ?? ac.partnerAvatar,
      partnerUserId: p.userId ?? ac.partnerUserId,
    );
    _activeCtrl.minimize();
    returnToRoute(_router, toConv ? '/conversation/$_sid' : '/chat/$_sid');
  }

  @override
  void dispose() {
    _suppressDisconnectNavigate = true;
    _timer?.cancel();
    _peerWait?.cancel();
    _duration.dispose();
    unawaited(CallNative.proximity(false));
    _room?.removeListener(_onRoomChanged);
    final remaining = (_videoScreenMounts[_sid] ?? 1) - 1;
    if (remaining <= 0) {
      _videoScreenMounts.remove(_sid);
    } else {
      _videoScreenMounts[_sid] = remaining;
    }
    if (remaining > 0) {
      super.dispose();
      return;
    }
    final ac = _activeCtrl.current;
    final owns = _ownedGen != 0 && _lk.generation == _ownedGen && _lk.sessionId == _sid;
    if (ac.minimized && ac.sessionId == _sid && owns) {
      _lk.handlers
        ..onParticipantLeft = () {
          unawaited(_lk.leave());
          _activeCtrl.clear();
        }
        ..onDisconnected = () {
          unawaited(_lk.leave());
          _activeCtrl.clear();
        }
        ..onRemoteTrack = null
        ..onLocalTrack = null
        ..onMediaError = null
        ..onReconnecting = null
        ..onTracksChanged = null;
    } else if (owns) {
      unawaited(_lk.leave());
      if (ac.sessionId == _sid) Future.microtask(_activeCtrl.clear);
    }
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _room?.localParticipant?.setMicrophoneEnabled(!_muted);
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    _applySpeaker();
  }

  void _toggleCamera() {
    if (_voiceOnly) return;
    setState(() => _cameraOff = !_cameraOff);
    _room?.localParticipant?.setCameraEnabled(!_cameraOff);
  }

  Future<void> _flipCamera() async {
    if (_voiceOnly || _cameraOff || _flipping) return;
    setState(() => _flipping = true);
    try {
      await _lk.flipCamera();
    } catch (_) {
      if (mounted) showToast(context, t('videoCall.flipFailed'), error: true);
    }
    if (mounted) setState(() => _flipping = false);
  }

  void _endCall() {
    HapticFeedback.mediumImpact();
    _suppressDisconnectNavigate = true;
    _peerWait?.cancel();
    unawaited(_lk.leave());
    _goBackAfterCall();
  }

  Widget _timeText(TextStyle style, {String prefix = ''}) => ValueListenableBuilder<int>(
        valueListenable: _duration,
        builder: (_, sec, _) => Text('$prefix${formatCallTime(sec)}', style: style),
      );

  @override
  Widget build(BuildContext context) {
    ref.watch(activeConversationProvider.select((s) => s.partner));
    final active = ref.watch(activeCallProvider);
    final partner = _partner;
    final name = partner.name.isNotEmpty ? partner.name : active.partnerName;
    final avatar = partner.avatar ?? active.partnerAvatar;
    final pad = MediaQuery.paddingOf(context);
    final remote = _lk.remoteVideo;
    final local = _lk.localVideo;
    final vo = _voiceOnly;
    final filter = _filters.firstWhere((f) => f.id == _filter);
    final showRemote = !vo && _connected && remote != null;
    final showIdentity = vo || !showRemote;
    final status = _error.isNotEmpty
        ? _error
        : _reconnecting
            ? t('videoCall.reconnecting')
            : _connected
                ? ''
                : t('conversationChat.connectingCall');

    Widget controls() => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 28 + pad.bottom),
          child: Row(
            textDirection: TextDirection.ltr,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CallCircleButton(icon: _muted ? LucideIcons.micOff : LucideIcons.mic, onTap: _toggleMute, active: _muted, size: 58),
              CallCircleButton(
                icon: _speakerOn ? LucideIcons.volume2 : LucideIcons.volume,
                onTap: _toggleSpeaker,
                active: _speakerOn,
                size: 58,
              ),
              CallCircleButton(icon: LucideIcons.phoneOff, onTap: _endCall, background: WaCall.decline, size: 68, iconSize: 28),
              if (!vo) ...[
                CallCircleButton(
                  icon: _cameraOff ? LucideIcons.videoOff : LucideIcons.video,
                  onTap: _toggleCamera,
                  active: _cameraOff,
                  size: 58,
                ),
                CallCircleButton(icon: LucideIcons.switchCamera, onTap: _flipCamera, active: _flipping, size: 58),
              ],
            ],
          ),
        );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_connected) {
            _openChatDuringCall();
          } else {
            _goBackAfterCall();
          }
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: WaCall.bgTop,
          body: Stack(children: [
            if (showIdentity)
              Positioned.fill(
                child: WhatsAppRingingLayout(
                  avatarUrl: avatar,
                  name: name,
                  status: status,
                  pulse: !_connected,
                  statusExtra: _connected
                      ? _timeText(const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ))
                      : null,
                  actions: const [],
                  top: WhatsAppCallTopBar(
                    name: '',
                    onMinimize: _openChatDuringCall,
                    trailing: IconButton(
                      onPressed: _openChatDuringCall,
                      icon: const Icon(LucideIcons.messageSquare, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),
            if (showRemote)
              Positioned.fill(
                child: VideoTrackRenderer(
                  remote,
                  fit: VideoViewFit.cover,
                  renderMode: VideoRenderMode.texture,
                  placeholderBuilder: (_) => const ColoredBox(color: Color(0xFF0B141A)),
                ),
              ),
            if (showRemote)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Color(0x00000000)],
                    ),
                  ),
                  child: WhatsAppCallTopBar(
                    name: name,
                    subtitle: _reconnecting ? t('videoCall.reconnecting') : null,
                    onMinimize: _openChatDuringCall,
                    trailing: _connected
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _timeText(const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            )),
                          )
                        : null,
                  ),
                ),
              ),
            if (!vo && _connected)
              PositionedDirectional(
                top: 100 + pad.top,
                end: 16,
                child: Container(
                  width: 108,
                  height: 144,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.5),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _cameraOff || local == null
                      ? Center(child: Icon(LucideIcons.videoOff, size: 28, color: Colors.white.withValues(alpha: 0.55)))
                      : GestureDetector(
                          onDoubleTap: _flipCamera,
                          child: RepaintBoundary(
                            child: ColorFiltered(
                              colorFilter: filter.matrix == null
                                  ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                                  : ColorFilter.matrix(filter.matrix!),
                              child: VideoTrackRenderer(
                                local,
                                fit: VideoViewFit.cover,
                                mirrorMode: _lk.cameraPosition == CameraPosition.front
                                    ? VideoViewMirrorMode.mirror
                                    : VideoViewMirrorMode.off,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            if (!vo && _connected)
              Positioned(
                left: 12,
                right: 12,
                bottom: 118 + pad.bottom,
                child: SizedBox(
                  height: 72,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final f in _filters)
                        GestureDetector(
                          onTap: () => setState(() => _filter = f.id),
                          child: Container(
                            width: 52,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _filter == f.id ? Colors.white : Colors.white.withValues(alpha: 0.15),
                                width: _filter == f.id ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ColorFiltered(
                              colorFilter: f.matrix == null
                                  ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                                  : ColorFilter.matrix(f.matrix!),
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(Radius.circular(11)),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Color(0xFF667EEA), Color(0xFF764BA2), Color(0xFFF093FB)],
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
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: controls(),
              ),
            ),
            LoaderOverlay(show: _initializing, text: t('videoCall.preparing')),
          ]),
        ),
      ),
    );
  }
}


