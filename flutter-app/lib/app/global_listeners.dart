import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feature_flags.dart';
import '../core/format.dart';
import '../core/json.dart';
import '../core/network/api_client.dart';
import '../core/network/hubs.dart';
import '../core/network/network_status.dart';
import '../core/storage/prefs.dart';
import '../features/auth/auth_controller.dart';
import '../features/calls/call_state.dart';
import '../features/calls/incoming_call_dialog.dart';
import '../features/calls/video_call_screen.dart';
import '../features/chat/chat_session.dart';
import '../features/conversations/active_conversation.dart';
import '../features/conversations/avatar_overrides.dart';
import '../features/conversations/conversations_list_controller.dart';
import '../features/matching/matching_controller.dart';
import '../features/matching/matching_dialogs.dart';
import '../features/notifications/notifications_controller.dart';
import '../features/short_films/short_films_controller.dart';
import '../features/stories/stories_controller.dart';
import '../services/call_native.dart';
import '../services/deep_links.dart';
import '../services/notification_nav.dart';
import '../services/push_service.dart';
import '../services/ring_sound.dart';
import 'router.dart';

/// Keeps hubs connected for the logged-in user and hosts app-wide overlays (App.vue).
class GlobalListeners extends ConsumerStatefulWidget {
  const GlobalListeners({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<GlobalListeners> createState() => _GlobalListenersState();
}

class _GlobalListenersState extends ConsumerState<GlobalListeners> {
  final List<void Function()> _disposers = [];

  @override
  void initState() {
    super.initState();
    _bindConversationHub();
    _bindStoryHub();
    _disposers.addAll(bindMatchingHub(ref));
    _bindPush();
    _bindIncomingNative();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncHubs();
      _initExistingSession();
      DeepLinks.init(ref);
    });
  }

  @override
  void dispose() {
    for (final d in _disposers) {
      d();
    }
    super.dispose();
  }

  /// main.js — existing session: refresh profile-contact status and register for push.
  Future<void> _initExistingSession() async {
    final auth = ref.read(authProvider);
    final user = auth.user;
    if (!auth.isLoggedIn || user == null) return;
    if (!auth.needsProfileContactRedirect) await ref.read(authProvider.notifier).fetchProfileContactStatus();
    PushService.instance.init(user.id).then((granted) {
      if (!granted) PushService.promptNotifications.value = true;
    });
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (ref.read(authProvider).isLoggedIn) unawaited(PushService.instance.init(user.id, promptPermission: false));
    });
  }

  void _bindPush() {
    Json storeItem(Map<String, dynamic> data, String? title, String? body, bool isRead) {
      final nav = parseNotificationData(data);
      final serverId = data['notificationId'] ?? data['NotificationId'] ?? nav['notificationId'];
      final createdAt = data['createdAt'] ?? data['CreatedAt'] ?? nav['createdAt'];
      return {
        ...nav,
        'serverId': ?serverId,
        if (serverId != null) 'id': 'srv-$serverId',
        'type': nav['type'] ?? data['type'] ?? 'message',
        'title': (title?.isNotEmpty ?? false) ? title : (data['title'] ?? 'إشعار'),
        'body': (body?.isNotEmpty ?? false) ? body : (data['body'] ?? ''),
        'timestamp': createdAt ?? DateTime.now().toIso8601String(),
        'isRead': isRead,
        'avatar': nav['callerAvatar'] ?? nav['requesterAvatar'] ?? data['avatar'] ?? data['senderAvatar'] ?? data['publisherAvatar'],
        'actorName': nav['callerName'] ?? nav['requesterName'] ?? data['senderName'] ?? data['publisherName'] ?? title,
      };
    }

    PushService.instance
      ..onOpen = (data, title, body) {
        if ('${data['type'] ?? ''}' == 'call_cancel') return;
        final item = storeItem(data, title, body, true);
        ref.read(notificationsProvider.notifier).add(item);
        final d = parseNotificationData(data);
        if (d['type'] == 'message_request') {
          unawaited(ref.read(pendingRequestsProvider.notifier).fetch());
        }
        navigateFromNotification(ref, item);
      }
      ..onForeground = (data, title, body) {
        if ('${data['type'] ?? ''}' == 'call_cancel') return;
        ref.read(notificationsProvider.notifier).add(storeItem(data, title, body, false));
        final d = parseNotificationData(data);
        if (d['type'] == 'message_request') {
          // Show the tab badge immediately; refetch for the accurate count.
          final n = ref.read(pendingRequestsProvider);
          ref.read(pendingRequestsProvider.notifier).set(n + 1);
          unawaited(ref.read(pendingRequestsProvider.notifier).fetch());
        }
        // video_call: do not start ringing from a push payload here.
        // Live calls arrive via SignalR and/or the native full-screen call notification.
      };

    NotificationHooks.onConversationCall = (d) {
      final id = d['conversationId'];
      if (id == null || id.isEmpty) return;
      if (isInAnotherCall(ref, exceptId: id)) {
        declineBusyConversationCall(id);
        return;
      }
      ref.read(incomingConvCallProvider.notifier).setIncoming(IncomingConvCall(
            conversationId: id,
            voiceOnly: incomingCallAsBool(d['voiceOnly']),
            callerName: d['callerName'] ?? '',
            callerAvatar: d['callerAvatar'],
          ));
    };
    NotificationHooks.onConnectionRequest = (d) {
      ref.read(matchingProvider.notifier).setIncomingConnectionRequest(ConnectionRequest(
            requesterId: d['requesterId'] ?? '',
            requesterName: d['requesterName'] ?? '…',
            requesterGender: d['requesterGender'],
            requesterAvatar: d['requesterAvatar'],
            requesterIsFeatured: d['requesterIsFeatured'] == 'true',
          ));
      RingSound.start();
    };
  }

  void _bindIncomingNative() {
    CallNative.onIncomingEvent = (e) {
      queueOrApplyIncomingCall(ref, e);
    };
    CallNative.listen();
    unawaited(() async {
      await CallNative.ready();
      // Intent may land after markReady on a cold start — pick up leftovers.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final pending = await CallNative.consumePending();
      if (pending != null) queueOrApplyIncomingCall(ref, pending);
    }());
  }

  void _clearMatchingOverlays() {
    ref.read(matchingProvider.notifier)
      ..clearPendingRandomMatch()
      ..clearIncomingConnectionRequest();
    RingSound.stop();
  }

  void _bindConversationHub() {
    final h = Hubs.conversation;
    _disposers.add(h.on('ConversationListUpdated', (a) {
      final payload = a.isEmpty ? null : a.first;
      if (payload is! Map) return;
      final convId = payload.str('conversationId');
      if (convId.isEmpty) return;
      final type = payload.s('lastMessageType');
      final senderId = payload.str('senderId');
      final me = ref.read(authProvider).user?.id ?? '';
      final viewing = ref.read(activeConversationProvider).conversationId == convId;
      final fromMe = senderId.isNotEmpty && senderId == me;
      final updated = ref.read(conversationsListProvider.notifier).updateConversation(
        convId,
        {
          'lastMessagePreview': formatConversationListPreview(payload.s('lastMessagePreview'), type: type),
          'lastMessageAt': payload.v('lastMessageAt'),
          'lastMessageType': type,
        },
        incrementUnread: !fromMe && !viewing,
      );
      if (updated) {
        Prefs.instance.setString('nexchat_conversations_cache', jsonEncode(ref.read(conversationsListProvider)));
      } else {
        Api.get('/conversations', query: {'filter': 'all'}).then((data) {
          ref.read(conversationsListProvider.notifier).setList(asJsonList(data));
        }).catchError((_) => null);
      }
    }));
    _disposers.add(h.on('IncomingVideoCall', (a) {
      final parsed = parseIncomingConversationCallPayload(a);
      if (parsed == null) return;
      final cid = parsed.conversationId;
      if (cid == null) return;
      final path = ref.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
      if (path == '/video/$cid') return;
      if (isInAnotherCall(ref, exceptId: cid)) {
        declineBusyConversationCall(cid);
        return;
      }
      final prev = ref.read(incomingConvCallProvider);
      if (prev.visible && prev.conversationId != null && prev.conversationId != cid) {
        declineBusyConversationCall(cid);
        return;
      }
      ref.read(incomingConvCallProvider.notifier).setIncoming(parsed);
      notifyOutgoingCallRinging(cid);
    }));

    _disposers.add(h.on('VideoCallDeclined', (a) {
      unawaited(RingSound.stop());
      final cid = '${a.firstOrNull ?? ''}';
      final incoming = ref.read(incomingConvCallProvider);
      if (incoming.conversationId != null && (cid.isEmpty || cid == 'null' || cid == incoming.conversationId)) {
        ref.read(incomingConvCallProvider.notifier).clear();
        unawaited(CallNative.dismissIncoming());
      }
      final active = ref.read(activeCallProvider);
      if (active.sessionId != null &&
          (cid.isEmpty || cid == 'null' || cid == active.sessionId) &&
          videoScreenMounts(active.sessionId!) == 0 &&
          !LiveKitService.instance.isInSession(active.sessionId!)) {
        ref.read(activeCallProvider.notifier).clear();
      }
    }));

    _disposers.add(h.on('VideoCallEnded', (a) {
      unawaited(RingSound.stop());
      final cid = '${a.firstOrNull ?? ''}';
      final active = ref.read(activeCallProvider);
      if (active.sessionId != null && (cid.isEmpty || cid == 'null' || cid == active.sessionId)) {
        ref.read(activeCallProvider.notifier).clear();
        if (!LiveKitService.instance.isInSession(active.sessionId!)) {
          unawaited(LiveKitService.instance.leave());
        }
      }
      final incoming = ref.read(incomingConvCallProvider);
      if (incoming.conversationId != null && (cid.isEmpty || cid == 'null' || cid == incoming.conversationId)) {
        ref.read(incomingConvCallProvider.notifier).clear();
        unawaited(CallNative.dismissIncoming());
      }
    }));

    _disposers.add(h.on('VideoCallBusy', (a) {
      final cid = '${a.firstOrNull ?? ''}';
      final active = ref.read(activeCallProvider);
      final mine = active.sessionId != null &&
          active.sessionId!.isNotEmpty &&
          (cid.isEmpty || cid == 'null' || cid == active.sessionId);
      if (mine) {
        unawaited(RingSound.playBusy());
        ref.read(activeCallProvider.notifier).clear();
      }
      final incoming = ref.read(incomingConvCallProvider);
      if (incoming.conversationId != null && (cid.isEmpty || cid == 'null' || cid == incoming.conversationId)) {
        ref.read(incomingConvCallProvider.notifier).clear();
        unawaited(CallNative.dismissIncoming());
      }
    }));

    _disposers.add(h.on('VideoCallAccepted', (a) {
      unawaited(RingSound.stop());
      final parsed = parseVideoCallAcceptedPayload(a);
      if (parsed == null) return;
      final cid = parsed.conversationId;
      final existing = ref.read(activeCallProvider);
      final voiceOnly = parsed.voiceOnly || (existing.sessionId == cid && existing.voiceOnly);
      final item = ref.read(conversationsListProvider).where((c) => c.str('id') == cid).firstOrNull;
      ref.read(activeCallProvider.notifier).syncMeta(
            sessionId: cid,
            voiceOnly: voiceOnly,
            isConversation: true,
            partnerName: existing.partnerName.isNotEmpty ? existing.partnerName : (item?.s('partnerName') ?? ''),
            partnerAvatar: existing.partnerAvatar ?? item?.s('partnerAvatar'),
            partnerUserId: existing.partnerUserId ?? item?.s('partnerId'),
          );
      ref.read(activeCallProvider.notifier).expand();
      final path = ref.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
      if (path == '/video/$cid' || videoScreenMounts(cid) > 0) return;
      openAcceptedCall(ref.read(routerProvider), cid, voiceOnly);
    }));

    _disposers.add(h.on('UserAvatarUpdated', (a) {
      final p = a.isNotEmpty && a[0] is Map ? a[0] as Map : null;
      final userId = p?.s('userId');
      if (userId == null) return;
      final avatar = p!.s('avatar');
      final uniqueCode = p.s('uniqueCode');
      ref.read(avatarOverridesProvider.notifier).set(userId, avatar);
      ref.read(conversationsListProvider.notifier).updatePartnerAvatarByUserId(userId, avatar);
      ref.read(chatSessionProvider.notifier).patchPartnerFromBroadcast(userId, avatar, uniqueCode);
      ref.read(activeConversationProvider.notifier).patchPartnerAvatar(userId, avatar, uniqueCode);
      ref.read(activeCallProvider.notifier).patchPartnerAvatar(userId, avatar);
      ref.read(storiesProvider.notifier).patchAvatar(userId, avatar);
      ref.read(matchingProvider.notifier)
        ..patchIncomingRequesterAvatar(userId, avatar)
        ..patchPendingRandomPartnerAvatar(userId, avatar, uniqueCode);
    }));
    _disposers.add(h.on('UserPresenceChanged', (a) {
      final p = a.isNotEmpty && a[0] is Map ? a[0] as Map : null;
      final userId = p?.s('userId');
      if (userId == null || userId.isEmpty) return;
      final online = p!.b('isOnline');
      ref.read(conversationsListProvider.notifier).updatePartnerOnlineByUserId(userId, online);
      ref.read(activeConversationProvider.notifier).patchPartnerOnline(userId, online);
    }));
  }

  void _bindStoryHub() {
    Map? first(List<Object?> a) => a.isNotEmpty && a[0] is Map ? a[0] as Map : null;
    _disposers.add(Hubs.story.on('StoryPublished', (a) => ref.read(storiesProvider.notifier).applyStoryPublished(first(a))));
    _disposers.add(Hubs.story.on('StoryDeleted', (a) => ref.read(storiesProvider.notifier).applyStoryDeleted(first(a))));
  }

  Future<void> _syncHubs() async {
    final auth = ref.read(authProvider);
    if (!auth.isLoggedIn) {
      await Hubs.stopAll();
      ref.invalidate(storiesProvider);
      ref.invalidate(shortFilmsProvider);
      ref.read(incomingConvCallProvider.notifier).clear();
      unawaited(CallNative.dismissIncoming());
      ref.read(chatSessionProvider.notifier).clear();
      unawaited(LiveKitService.instance.leave());
      ref.read(activeCallProvider.notifier).clear();
      _clearMatchingOverlays();
      ref.invalidate(matchingProvider);
      return;
    }
    Hubs.conversation.start().catchError((_) {});
    Hubs.story.start().catchError((_) {});
    if (NetworkStatus.online.value) ref.read(storiesProvider.notifier).fetchFeed(force: true);
    final flags = await ref.read(featureFlagsProvider.future);
    if (flags.connectHub) {
      Hubs.matching.start().catchError((_) {});
    } else {
      await Hubs.matching.stop();
      _clearMatchingOverlays();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider.select((s) => s.isLoggedIn), (prev, next) {
      _syncHubs();
      if (next) flushPendingIncomingCall(ref);
    });
    ref.listen(featureFlagsProvider.select((a) => a.value?.connectHub), (_, _) => _syncHubs());
    final loggedIn = ref.watch(authProvider.select((s) => s.isLoggedIn));
    final flags = ref.watch(featureFlagsProvider).value ?? FeatureFlags.hiddenUntilLoaded;
    return Stack(children: [
      widget.child,
      if (loggedIn) const Positioned.fill(child: IncomingCallOverlay()),
      if (loggedIn && flags.codeConnect) const Positioned.fill(child: IncomingConnectionRequestOverlay()),
      if (loggedIn && flags.randomChat) const Positioned.fill(child: RandomMatchConsentOverlay()),
    ]);
  }
}
