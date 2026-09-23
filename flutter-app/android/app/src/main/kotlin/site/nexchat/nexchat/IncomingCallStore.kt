package site.nexchat.nexchat

import android.content.Context
import android.content.Intent

/** Persists an incoming call so Flutter can pick it up after a cold start. */
object IncomingCallStore {
    const val PREF = "nexchat_incoming_call"
    const val EXTRA_INCOMING = "nexchat_incoming"
    const val EXTRA_CONVERSATION_ID = "conversation_id"
    const val EXTRA_SESSION_ID = "session_id"
    const val EXTRA_VOICE_ONLY = "voice_only"
    const val EXTRA_CALLER_NAME = "caller_name"
    const val EXTRA_CALLER_AVATAR = "caller_avatar"
    const val EXTRA_ACTION = "incoming_action"

    const val ACTION_RING = "ring"
    const val ACTION_ACCEPT = "accept"
    const val ACTION_DECLINE = "decline"

    fun save(
        context: Context,
        conversationId: String?,
        sessionId: String?,
        voiceOnly: Boolean,
        callerName: String,
        callerAvatar: String?,
        action: String,
    ) {
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit()
            .putString(EXTRA_CONVERSATION_ID, conversationId ?: "")
            .putString(EXTRA_SESSION_ID, sessionId ?: "")
            .putBoolean(EXTRA_VOICE_ONLY, voiceOnly)
            .putString(EXTRA_CALLER_NAME, callerName)
            .putString(EXTRA_CALLER_AVATAR, callerAvatar ?: "")
            .putString(EXTRA_ACTION, action)
            .apply()
    }

    fun saveFromIntent(context: Context, intent: Intent, action: String = intent.actionValue()) {
        if (!intent.getBooleanExtra(EXTRA_INCOMING, false) &&
            intent.getStringExtra(EXTRA_CONVERSATION_ID).isNullOrBlank() &&
            intent.getStringExtra(EXTRA_SESSION_ID).isNullOrBlank()
        ) {
            return
        }
        save(
            context,
            intent.getStringExtra(EXTRA_CONVERSATION_ID),
            intent.getStringExtra(EXTRA_SESSION_ID),
            intent.getBooleanExtra(EXTRA_VOICE_ONLY, false),
            intent.getStringExtra(EXTRA_CALLER_NAME) ?: "",
            intent.getStringExtra(EXTRA_CALLER_AVATAR),
            action,
        )
    }

    fun peek(context: Context): HashMap<String, Any?>? {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val conversationId = prefs.getString(EXTRA_CONVERSATION_ID, "") ?: ""
        val sessionId = prefs.getString(EXTRA_SESSION_ID, "") ?: ""
        if (conversationId.isBlank() && sessionId.isBlank()) return null
        return hashMapOf(
            "conversationId" to conversationId.ifBlank { null },
            "sessionId" to sessionId.ifBlank { null },
            "voiceOnly" to prefs.getBoolean(EXTRA_VOICE_ONLY, false),
            "callerName" to (prefs.getString(EXTRA_CALLER_NAME, "") ?: ""),
            "callerAvatar" to prefs.getString(EXTRA_CALLER_AVATAR, "")?.ifBlank { null },
            "action" to (prefs.getString(EXTRA_ACTION, ACTION_RING) ?: ACTION_RING),
        )
    }

    fun take(context: Context): HashMap<String, Any?>? {
        val data = peek(context)
        if (data != null) clear(context)
        return data
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().clear().apply()
    }

    fun setForeground(context: Context, foreground: Boolean) {
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit()
            .putBoolean("app_foreground", foreground)
            .apply()
    }

    fun isForeground(context: Context): Boolean =
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE).getBoolean("app_foreground", false)

    fun putOn(intent: Intent, conversationId: String?, sessionId: String?, voiceOnly: Boolean, callerName: String, callerAvatar: String?, action: String): Intent {
        return intent
            .putExtra(EXTRA_INCOMING, true)
            .putExtra(EXTRA_CONVERSATION_ID, conversationId)
            .putExtra(EXTRA_SESSION_ID, sessionId)
            .putExtra(EXTRA_VOICE_ONLY, voiceOnly)
            .putExtra(EXTRA_CALLER_NAME, callerName)
            .putExtra(EXTRA_CALLER_AVATAR, callerAvatar)
            .putExtra(EXTRA_ACTION, action)
    }
}

private fun Intent.actionValue(): String =
    getStringExtra(IncomingCallStore.EXTRA_ACTION) ?: IncomingCallStore.ACTION_RING
