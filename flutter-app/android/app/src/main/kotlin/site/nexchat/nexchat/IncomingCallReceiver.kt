package site.nexchat.nexchat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class IncomingCallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val conversationId = intent.getStringExtra(IncomingCallStore.EXTRA_CONVERSATION_ID)
        val sessionId = intent.getStringExtra(IncomingCallStore.EXTRA_SESSION_ID)
        val voiceOnly = intent.getBooleanExtra(IncomingCallStore.EXTRA_VOICE_ONLY, false)
        val callerName = intent.getStringExtra(IncomingCallStore.EXTRA_CALLER_NAME) ?: ""
        val callerAvatar = intent.getStringExtra(IncomingCallStore.EXTRA_CALLER_AVATAR)

        when (intent.action) {
            ACTION_ACCEPT -> {
                IncomingCallStore.save(context, conversationId, sessionId, voiceOnly, callerName, callerAvatar, IncomingCallStore.ACTION_ACCEPT)
                IncomingCallNotifier.cancel(context)
                IncomingCallPlugin.notifyFlutterIfReady(context)
                val launch = IncomingCallStore.putOn(
                    Intent(context, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                    conversationId,
                    sessionId,
                    voiceOnly,
                    callerName,
                    callerAvatar,
                    IncomingCallStore.ACTION_ACCEPT,
                )
                context.startActivity(launch)
            }
            ACTION_DECLINE, ACTION_DISMISS -> {
                IncomingCallStore.save(context, conversationId, sessionId, voiceOnly, callerName, callerAvatar, IncomingCallStore.ACTION_DECLINE)
                IncomingCallNotifier.cancel(context)
                IncomingCallPlugin.notifyFlutterIfReady(context)
                if (!IncomingCallPlugin.flutterReady) IncomingCallStore.clear(context)
            }
        }
    }

    companion object {
        const val ACTION_ACCEPT = "site.nexchat.nexchat.INCOMING_ACCEPT"
        const val ACTION_DECLINE = "site.nexchat.nexchat.INCOMING_DECLINE"
        const val ACTION_DISMISS = "site.nexchat.nexchat.INCOMING_DISMISS"
    }
}
