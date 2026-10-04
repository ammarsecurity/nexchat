# Message delivery and reconnect contract

## Sending

Apply migration `20261004172200_AddMessageClientIds` before using the new send methods.

- `ConversationHub.SendMessage` retains its five wire arguments: conversation ID, content, type, reply ID, view-once.
- `ConversationHub.SendMessageWithClientId` takes those five arguments plus a stable client message ID.
- `ChatHub.SendMessage` retains its three wire arguments: session ID, content, type.
- `ChatHub.SendMessageWithClientId` takes those three arguments plus a stable client message ID.
- All four methods return the accepted message payload. Only a durable server message ID is an acceptance acknowledgment. Invalid content, inaccessible/removed conversations, unavailable reply targets and bilateral blocks fail the invocation with `HubException`.
- A client ID is a nonempty, whitespace-free string of at most 80 characters. The server preserves it. The database enforces unique `(conversation/session, sender, client ID)` indexes with a case-sensitive collation. A retry returns the original message without inserting or broadcasting a second row. Legacy calls without a client ID cannot promise retry idempotency.
- Nullable keys preserve existing rows. The message/session content limit is consistently 5000 characters. Migration rollback intentionally keeps the widened content column to avoid truncating accepted data.
- An acknowledgment means persisted, not delivered to or read by another device. Per-recipient socket failures do not reject a saved message or suppress the remaining recipients. History is the recovery source after reconnect.

## Scoped events and account fan-out

SignalR JSON names follow the app's normal camel-case serializer.

- `ReceiveMessage` includes `conversationId` or `sessionId`, server `id`, and nullable `clientMessageId` on every producer/history projection.
- Conversation read, typing, reaction, expiry, deletion, membership and update objects carry `conversationId`.
- `PartnerReadUpTo` includes `readerId` and `lastReadAt`. Read watermark updates are an atomic database maximum, including REST read/read-all requests.
- `ConversationRead` contains `conversationId`, `lastReadAt`, and authoritative `unreadCount` for all of the reading account's devices.
- `MessageDeletedForMeV2` / `MessageDeletedForEveryoneV2` contain `conversationId`, `messageId`, and `replyToMessageId`. `ReplyPreviewsRedacted` contains `conversationId` and `messageIds` of source messages whose quotes must be cleared.
- `SessionEndedV2`, `UserTypingV2`, and `UserStoppedTypingV2` from the session hub carry `sessionId` and `userId`.
- `ConversationRemoved` contains `conversationId` and `userId`. Known local room subscriptions are removed on group removal/leave, and every subsequent send/join rechecks membership. Conversation messages, receipts, expiry, reactions, typing and deletions use current participant account addresses rather than trusting a prior room subscription.
- Group send delivers inbox updates with a separately calculated authoritative unread count and enqueues a notification for each non-hidden recipient, even when no group screen is open. Another message restores a recipient's hidden-by-deletion inbox entry while preserving that recipient's old personal message deletions.

Modern clients consume the scoped `V2` event names above, plus `ConversationDeletedForMeV2` (`conversationId`) and conversation-hub `UserTypingV2` / `UserStoppedTypingV2` (`conversationId`, `userId`). The original event names retain scalar GUID payloads for older clients. Legacy personal-message/conversation deletion stays caller-only; everyone-deletion and session-ended stay room-only; typing stays others-in-room. This avoids routing an ambiguous scalar into an unrelated old-client screen. Modern events remain account-addressed, including administrative and inactivity session termination.

## Quote visibility and history

Replies never expose content from a source that is deleted for everyone, expired, personally deleted, or in another conversation. Such projections carry `replyToUnavailable: true` with empty/null preview fields. A visible quoted source includes `replyToExpiresAt`; clients must clear the quote at that deadline even when the source itself is not in the loaded page. `MessagesExpiring` must update deadlines of both source messages and references to those sources.

History uses the strict lexicographic cursor `(SentAt < anchor.SentAt) OR (SentAt = anchor.SentAt AND Id < anchor.Id)`, with the same database ordering as `(SentAt DESC, Id DESC)`. The comparison is parameterized SQL to avoid provider-specific GUID comparison translations. The anchor must belong to the requested conversation.

## Immediate conversation snapshot

`GET /api/conversations/{id}/messages` is authenticated and returns `{ conversationId, messages, hasMore }`. It returns the latest 60 visible messages in oldest-to-newest order, using the same shared projection as `ConversationJoined` and `OlderMessages`. This allows a notification-opened conversation to show durable history while its SignalR connection is still joining. Clients merge by durable message ID and preserve their account/conversation generation guards; the socket remains the live update and older-page transport.

Only current private participants and group members can read a snapshot. Missing conversations, removed memberships and conversations deleted for the requester return 404; invalid/missing authentication returns 401. The response is marked non-cacheable. The snapshot is read-only: it does not mark messages read, consume view-once media, or restore deleted conversations. Existing join/read flows continue to handle those actions. Personal deletions, expiry, unavailable quotes, client IDs, reactions, group sender details and view-once URL redaction all follow the shared socket history implementation.

## Session retention policy

Transport disconnects do not immediately end random/code/support chat sessions. Explicit `LeaveSession` ends a non-support session; administrative closure also remains available. The existing registered `InactiveSessionCleanupService` checks every minute and closes sessions after more than one hour since the latest message, or session start when no messages exist. It includes support sessions, whose existing join/send flows permit reopening. Thus a transient disconnect is resumable until explicit/admin closure or that inactivity deadline. Opening/reading a screen or typing does not reset this message-based inactivity clock. Call lifecycle timeouts remain a separate concern.

Room connection tracking is in process. A multi-node deployment needs distributed membership tracking for physical ejection; the message event audience is still recomputed from current database membership. This patch does not introduce a distributed call-state store or a production event replay log.

## Verification

Run:

    dotnet test backend/NexChat.Messaging.Tests/NexChat.Messaging.Tests.csproj -m:1 /nr:false

The test suite uses an isolated in-memory **relational SQLite** database, real EF constraints/queries and real hub methods. Network access to notification providers is blocked in the fixture. It covers stable retry acknowledgment, database duplicate-key rejection/scoping, lost live acknowledgments, bilateral blocks, legacy wire arities, 125 equal-timestamp messages across multiple pages, personal/everyone deletion, quote deletion/expiry, all-member inbox counts and queued group pushes, removed-member rejection/ejection, scoped typing/reads, non-regressing read watermarks, session disconnect/explicit leave migration discovery, reel/story share payloads, and no-connection Pomelo SQL translation for MySQL 8.0/MariaDB 10.11.

These are not production MySQL migration runs, live multi-node concurrency tests, device SignalR tests, provider push delivery tests, or full Flutter end-to-end tests. Run the complete merged suite after integrating call/media work.

## Flutter storage and message actions

- Message caches, inbox filters, unsent text and hidden-chat PINs are namespaced by authenticated account. Unowned legacy cache keys are removed instead of assigning them to the next login. Drafts belonging to a known account survive logout only in that account's namespace.
- Pending text is restored independently from history and is delivered by the account-level outbox on login/network recovery/reconnect, even after its chat screen closes. Stable client IDs survive both automatic and manual retries. Only a scoped, durable own-message acknowledgment removes a queued item.
- Account transitions reset private providers. Queued hub invocations capture the initiating token and generation; old socket events and late inbox responses cannot update a new account's UI.
- Deletion tombstones are persisted and applied to subsequent stale cache writes. Quotes are redacted on deletion/expiry, including when the quoted original is outside the loaded page.
- The existing long-press sheet now has Copy for eligible visible text/story captions, with clipboard feedback and no copying of media URLs, serialized metadata, deleted, restricted or view-once content.
- Internal forwarding reuses the existing destination picker. It supports existing conversations/groups, direct contacts and explicit registered-number lookup through `/contacts/lookup`. The exact target is confirmed before opening/sending, cancellation does not create a conversation, failed retries reuse a stable identity, and unknown numbers never trigger SMS/invitations. Reel and story payloads use the corrected six-argument idempotent hub method. This adds no OS/external sharing UI.

Flutter verification:

    cd flutter-app
    flutter test --no-pub test/message_delivery_test.dart test/share_message_screen_test.dart

The 16 focused tests cover reducers, private account caches/outbox, tombstone/quote persistence, Clipboard action, forward argument contracts and real picker widgets with isolated HTTP responses. They do not prove real-device clipboard, native/background execution or live recipient delivery.
