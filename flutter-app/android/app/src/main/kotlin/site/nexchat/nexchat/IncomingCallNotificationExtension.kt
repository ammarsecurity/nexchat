package site.nexchat.nexchat

import androidx.annotation.Keep
import com.onesignal.notifications.INotificationReceivedEvent
import com.onesignal.notifications.INotificationServiceExtension
import org.json.JSONObject

/** Intercepts OneSignal video_call pushes and turns them into a full-screen incoming call. */
@Keep
class IncomingCallNotificationExtension : INotificationServiceExtension {
    override fun onNotificationReceived(event: INotificationReceivedEvent) {
        val data = event.notification.additionalData ?: return
        if (data.optString("type") != "video_call") return

        val context = event.context.applicationContext
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

        if (IncomingCallStore.isForeground(context)) {
            IncomingCallPlugin.notifyFlutterIfReady(context)
            return
        }

        IncomingCallNotifier.show(context, conversationId, sessionId, voiceOnly, callerName, callerAvatar)
        IncomingCallPlugin.notifyFlutterIfReady(context)
    }

    private fun JSONObject.stringOrNull(key: String): String? {
        val v = optString(key, "")
        return v.ifBlank { null }
    }
}
