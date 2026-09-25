package site.nexchat.nexchat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.Person

/** High-priority incoming-call notification with full-screen intent (WhatsApp-style). */
object IncomingCallNotifier {
    const val CHANNEL_ID = "nexchat_incoming_call_v2"
    const val NOTIFICATION_ID = 71001
    private val handler = Handler(Looper.getMainLooper())
    private var timeout: Runnable? = null

    fun show(
        context: Context,
        conversationId: String?,
        sessionId: String?,
        voiceOnly: Boolean,
        callerName: String,
        callerAvatar: String?,
    ) {
        val app = context.applicationContext
        val name = callerName.ifBlank { "NexChat" }
        val status = if (voiceOnly) "مكالمة صوتية واردة" else "مكالمة فيديو واردة"
        IncomingCallStore.save(app, conversationId, sessionId, voiceOnly, name, callerAvatar, IncomingCallStore.ACTION_RING)
        ensureChannel(app)

        val fullScreen = activityIntent(app, conversationId, sessionId, voiceOnly, name, callerAvatar, IncomingCallStore.ACTION_RING, 11)
        // CallStyle accept must be an Activity PendingIntent — BroadcastReceivers are unreliable from the shade.
        val accept = mainActivityIntent(app, conversationId, sessionId, voiceOnly, name, callerAvatar, IncomingCallStore.ACTION_ACCEPT, 12)
        val decline = actionIntent(app, IncomingCallReceiver.ACTION_DECLINE, conversationId, sessionId, voiceOnly, name, callerAvatar, 13)

        val person = Person.Builder().setName(name).setImportant(true).build()
        val builder = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_phone)
            .setContentTitle(name)
            .setContentText(status)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setTimeoutAfter(60_000)
            .setFullScreenIntent(fullScreen, true)
            .setContentIntent(fullScreen)
            .setDefaults(Notification.DEFAULT_VIBRATE)
            .addPerson(person)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setStyle(
                NotificationCompat.CallStyle.forIncomingCall(person, decline, accept)
            )
        } else {
            builder
                .addAction(R.drawable.ic_call_decline, "رفض", decline)
                .addAction(R.drawable.ic_call_accept, "قبول", accept)
        }

        val manager = app.getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, builder.build())
        // Ring even if the full-screen Activity is delayed / blocked by OEM policies.
        IncomingCallRinger.start(app)
        scheduleTimeout(app)
    }

    fun cancel(context: Context, finishActivity: Boolean = true) {
        cancelTimeout()
        IncomingCallRinger.stop()
        if (finishActivity) IncomingCallUi.finish()
        context.applicationContext.getSystemService(NotificationManager::class.java)
            .cancel(NOTIFICATION_ID)
    }

    private fun scheduleTimeout(context: Context) {
        cancelTimeout()
        val run = Runnable { IncomingCallReceiver.timeoutDecline(context) }
        timeout = run
        handler.postDelayed(run, 60_000)
    }

    private fun cancelTimeout() {
        timeout?.let { handler.removeCallbacks(it) }
        timeout = null
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val ringtone = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(CHANNEL_ID, "مكالمات واردة", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "مكالمات الفيديو والصوت الواردة"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(ringtone, attrs)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 400, 800, 400)
            setBypassDnd(false)
        }
        manager.createNotificationChannel(channel)
    }

    fun activityIntent(
        context: Context,
        conversationId: String?,
        sessionId: String?,
        voiceOnly: Boolean,
        callerName: String,
        callerAvatar: String?,
        action: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = IncomingCallStore.putOn(
            Intent(context, IncomingCallActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
            conversationId,
            sessionId,
            voiceOnly,
            callerName,
            callerAvatar,
            action,
        )
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** Opens Flutter MainActivity with accept/ring extras so Dart can navigate to the call UI. */
    fun mainActivityIntent(
        context: Context,
        conversationId: String?,
        sessionId: String?,
        voiceOnly: Boolean,
        callerName: String,
        callerAvatar: String?,
        action: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = IncomingCallStore.putOn(
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            conversationId,
            sessionId,
            voiceOnly,
            callerName,
            callerAvatar,
            action,
        )
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun actionIntent(
        context: Context,
        action: String,
        conversationId: String?,
        sessionId: String?,
        voiceOnly: Boolean,
        callerName: String,
        callerAvatar: String?,
        requestCode: Int,
    ): PendingIntent {
        val intent = IncomingCallStore.putOn(
            Intent(context, IncomingCallReceiver::class.java).setAction(action),
            conversationId,
            sessionId,
            voiceOnly,
            callerName,
            callerAvatar,
            if (action == IncomingCallReceiver.ACTION_ACCEPT) IncomingCallStore.ACTION_ACCEPT else IncomingCallStore.ACTION_DECLINE,
        )
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
