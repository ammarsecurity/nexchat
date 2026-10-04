import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../auth/auth_controller.dart';
import 'message_contract.dart';

/// An event, rather than a route change: tapping the current chat must refresh too.
class ConversationRefreshIntent
    extends Notifier<({String conversation, int revision})> {
  @override
  ({String conversation, int revision}) build() {
    ref.watch(authProvider.select((s) => (s.user?.id, s.token)));
    return (conversation: '', revision: 0);
  }

  void request(String conversation) =>
      state = (conversation: conversation, revision: state.revision + 1);
}

final conversationRefreshIntentProvider =
    NotifierProvider<
      ConversationRefreshIntent,
      ({String conversation, int revision})
    >(ConversationRefreshIntent.new);

String _identity(Json m) => m.str('id').isNotEmpty
    ? 'id:${m.str('id')}'
    : 'client:${m.str('senderId')}:${clientMessageId(m)}';
String _clientIdentity(Json m) => clientMessageId(m).isEmpty
    ? ''
    : '${m.str('senderId').toLowerCase()}:${clientMessageId(m)}';

/// Reconcile only the snapshot's window. Arrivals, edits, acknowledgments and
/// removals since the request began win over its delayed response.
List<Json> mergeConversationSnapshot({
  required List<Json> baseline,
  required List<Json> current,
  required List<Json> server,
  required bool hasMore,
  Set<String> removedIds = const {},
  bool additive = false,
}) {
  final before = {for (final m in baseline) _identity(m): m};
  final now = {for (final m in current) _identity(m): m};
  final removed = {
    ...removedIds,
    for (final m in baseline)
      if (!now.containsKey(_identity(m)) && m.str('id').isNotEmpty) m.str('id'),
  };
  final result = <String, Json>{};
  DateTime? oldest;
  for (final m in server) {
    final at = m.date('sentAt');
    if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
    if (removed.contains(m.str('id'))) continue;
    final key = _identity(m);
    final local = now[key];
    final changed =
        local != null && (additive || !mapEquals(local, before[key]));
    var merged = changed ? local : m;
    // Redactions are monotonic even when a concurrent event changed another field.
    if (m.b('deletedForEveryone') ||
        (local?.b('deletedForEveryone') ?? false)) {
      merged = {...merged, 'deletedForEveryone': true, 'content': ''};
    }
    if (m.b('viewOnceOpened') || (local?.b('viewOnceOpened') ?? false)) {
      merged = {...merged, 'viewOnceOpened': true};
    }
    if (m.s('replyToType') == 'unavailable') {
      merged = {
        ...merged,
        'replyToContent': m['replyToContent'],
        'replyToType': 'unavailable',
        'replyToSenderName': null,
      };
    }
    result[key] = merged;
  }
  final acknowledged = {
    for (final m in server)
      if (_clientIdentity(m).isNotEmpty) _clientIdentity(m),
  };
  for (final m in current) {
    final key = _identity(m);
    if (result.containsKey(key) || removed.contains(m.str('id'))) continue;
    if ((m['status'] == 'pending' || m['status'] == 'failed') &&
        acknowledged.contains(_clientIdentity(m))) {
      continue;
    }
    final changed = !mapEquals(m, before[key]);
    final older =
        hasMore &&
        (oldest == null || (m.date('sentAt')?.isBefore(oldest) ?? false));
    if (additive ||
        changed ||
        older ||
        m['status'] == 'pending' ||
        m['status'] == 'failed') {
      result[key] = m;
    }
  }
  return withoutExpiredMessages([
    for (final m in result.values) redactReply(m, removed),
  ])..sort((a, b) {
    final time = (a.date('sentAt') ?? DateTime(0)).compareTo(
      b.date('sentAt') ?? DateTime(0),
    );
    return time != 0 ? time : _identity(a).compareTo(_identity(b));
  });
}

/// Latest request wins; disposal/account/navigation changes invalidate results.
class ConversationRefreshController {
  ConversationRefreshController({
    required this.conversation,
    required this.isCurrent,
    required this.load,
    required this.readMessages,
    required this.apply,
    required this.onState,
  });
  final String conversation;
  final bool Function() isCurrent;
  final Future<Json> Function() load;
  final List<Json> Function() readMessages;
  final void Function(List<Json>, bool) apply;
  final void Function(bool loading, Object? error) onState;
  final removedIds = <String>{};
  int _generation = 0;
  bool _disposed = false;

  Future<void> refresh() async {
    if (_disposed || !isCurrent()) return;
    final generation = ++_generation;
    final baseline = [
      for (final m in readMessages()) Map<String, dynamic>.of(m),
    ];
    bool valid() => !_disposed && generation == _generation && isCurrent();
    onState(true, null);
    try {
      final response = await load();
      if (!valid()) return;
      if (!belongsToConversation(response, conversation)) {
        throw StateError('Unexpected conversation');
      }
      final server = [
        for (final m in response.v('messages') as List? ?? const [])
          if (m is Map && belongsToConversation(m, conversation))
            {...normalizeMsg(m), 'status': 'sent'},
      ];
      final merged = mergeConversationSnapshot(
        baseline: baseline,
        current: readMessages(),
        server: server,
        hasMore: response.b('hasMore'),
        removedIds: removedIds,
      );
      final retained = {for (final m in merged) m.str('id')};
      removedIds.addAll(
        baseline
            .where(
              (m) =>
                  m.str('id').isNotEmpty &&
                  m['status'] != 'pending' &&
                  m['status'] != 'failed' &&
                  !retained.contains(m.str('id')),
            )
            .map((m) => m.str('id')),
      );
      apply(merged, response.b('hasMore'));
      onState(false, null);
    } catch (error) {
      if (valid()) onState(false, error);
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
  }
}
