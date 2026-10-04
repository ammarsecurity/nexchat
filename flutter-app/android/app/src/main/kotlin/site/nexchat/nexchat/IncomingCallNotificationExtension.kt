package site.nexchat.nexchat

import androidx.annotation.Keep
import com.onesignal.notifications.INotificationReceivedEvent
import com.onesignal.notifications.INotificationServiceExtension
import org.json.JSONObject

/** Intercepts OneSignal video_call pushes and turns them into a full-screen incoming call. */
@Keep
class IncomingCallNotificationExtension : INotificationServiceExtension {
    override fun onNotificationReceived(event: INotificationReceivedEvent) {
        try {
            val context = event.context.applicationContext
            val data = event.notification.additionalData
            if (data == null || !IncomingCallStore.acceptsRecipient(context, null)) {
                event.preventDefault()
                return
            }
            val type = data.optString("type")

            val recipient = data.stringOrNull("recipientUserId")
            if (!IncomingCallStore.acceptsRecipient(context, recipient) ||
                (type != "broadcast" && recipient.isNullOrBlank())) {
                event.preventDefault()
                return
            }
            val callId = data.stringOrNull("callId")
            if (type == "call_cancel") {
                event.preventDefault()
                val alreadyAnsweredHere = data.optString("reason") == "answered" &&
                    IncomingCallStore.peek(context)?.get("action") == IncomingCallStore.ACTION_ACCEPT
                if (IncomingCallStore.matches(context, callId) && !alreadyAnsweredHere) {
                    IncomingCallNotifier.cancel(context)
                    IncomingCallStore.endFromPush(context, callId)
                }
                return
            }
            if (type != "video_call") return
            event.preventDefault()
            if (callId.isNullOrBlank()) return
            val ongoing = IncomingCallStore.ongoingCall(context)
            if (ongoing != null && ongoing != callId) return
            if (IncomingCallStore.matches(context, callId)) return

            val conversationId = data.stringOrNull("conversationId")
            val sessionId = data.stringOrNull("sessionId")
            if (conversationId.isNullOrBlank() && sessionId.isNullOrBlank()) return

            val voiceOnly = data.optString("voiceOnly") == "true" || data.optBoolean("voiceOnly", false)
            val callerName = data.optString("callerName").ifBlank { "NexChat" }
            val callerAvatar = data.stringOrNull("callerAvatar")

            IncomingCallStore.save(
                context,
                conversationId,
                sessionId,
                voiceOnly,
                callerName,
                callerAvatar,
                IncomingCallStore.ACTION_RING,
                callId,
            )
            event.preventDefault()

            // Never trust a sticky prefs flag alone — if Flutter isn't alive, always show FSI.
            // Stale app_foreground=true after process kill previously silenced ringing.
            val flutterAliveAndForeground =
                IncomingCallPlugin.flutterReady && IncomingCallStore.isForeground(context)
            if (flutterAliveAndForeground) {
                IncomingCallPlugin.notifyFlutterIfReady(context)
                return
            }

            IncomingCallNotifier.show(context, conversationId, sessionId, voiceOnly, callerName, callerAvatar, callId)
            IncomingCallPlugin.notifyFlutterIfReady(context)
        } catch (_: Exception) {
            // An unparseable payload cannot establish account ownership.
            event.preventDefault()
        }
    }

    private fun JSONObject.stringOrNull(key: String): String? {
        val v = optString(key, "")
        return v.ifBlank { null }
    }
}
