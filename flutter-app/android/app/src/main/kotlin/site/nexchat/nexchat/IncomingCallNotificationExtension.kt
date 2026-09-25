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
            val data = event.notification.additionalData ?: return
            val type = data.optString("type")
            val context = event.context.applicationContext

            if (type == "call_cancel") {
                event.preventDefault()
                IncomingCallNotifier.cancel(context)
                IncomingCallStore.clear(context)
                return
            }
            if (type != "video_call") return

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

            IncomingCallNotifier.show(context, conversationId, sessionId, voiceOnly, callerName, callerAvatar)
            IncomingCallPlugin.notifyFlutterIfReady(context)
        } catch (_: Exception) {
            // Never swallow regular OneSignal notifications if call parsing fails.
        }
    }

    private fun JSONObject.stringOrNull(key: String): String? {
        val v = optString(key, "")
        return v.ifBlank { null }
    }
}
