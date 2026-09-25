package site.nexchat.nexchat

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var proximityLock: PowerManager.WakeLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
        applyIncomingIntent(intent)
        applyLockScreen(intentHasIncoming(intent))
    }

    override fun onResume() {
        super.onResume()
        IncomingCallStore.setForeground(applicationContext, true)
    }

    override fun onPause() {
        IncomingCallStore.setForeground(applicationContext, false)
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyIncomingIntent(intent)
        if (intentHasIncoming(intent)) applyLockScreen(true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexchat/call")
        IncomingCallPlugin.attach(channel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    CallService.start(
                        applicationContext,
                        call.argument<Boolean>("video") == true,
                        call.argument<String>("title") ?: "NexChat",
                        call.argument<String>("text") ?: "",
                    )
                    result.success(null)
                }
                "stop" -> {
                    CallService.stop(applicationContext)
                    setProximity(false)
                    applyLockScreen(false)
                    result.success(null)
                }
                "clearLockScreen" -> {
                    applyLockScreen(false)
                    result.success(null)
                }
                "proximity" -> {
                    setProximity(call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                "showIncoming" -> {
                    IncomingCallNotifier.show(
                        applicationContext,
                        call.argument<String>("conversationId"),
                        call.argument<String>("sessionId"),
                        call.argument<Boolean>("voiceOnly") == true,
                        call.argument<String>("callerName") ?: "NexChat",
                        call.argument<String>("callerAvatar"),
                    )
                    result.success(null)
                }
                "dismissIncoming" -> {
                    IncomingCallNotifier.cancel(applicationContext)
                    IncomingCallStore.clear(applicationContext)
                    result.success(null)
                }
                "setForeground" -> {
                    IncomingCallStore.setForeground(applicationContext, call.argument<Boolean>("value") == true)
                    result.success(null)
                }
                "ready" -> {
                    IncomingCallPlugin.markReady(applicationContext)
                    result.success(null)
                }
                "consumePending" -> {
                    result.success(IncomingCallStore.take(applicationContext))
                }
                "canUseFullScreenIntent" -> {
                    val ok = if (Build.VERSION.SDK_INT >= 34) {
                        getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
                    } else {
                        true
                    }
                    result.success(ok)
                }
                "isEmulator" -> result.success(isEmulator())
                else -> result.notImplemented()
            }
        }
        applyIncomingIntent(intent)
    }

    override fun onDestroy() {
        IncomingCallStore.setForeground(applicationContext, false)
        IncomingCallPlugin.detach()
        setProximity(false)
        super.onDestroy()
    }

    private fun intentHasIncoming(intent: Intent?): Boolean {
        if (intent == null) return false
        return intent.getBooleanExtra(IncomingCallStore.EXTRA_INCOMING, false) ||
            !intent.getStringExtra(IncomingCallStore.EXTRA_CONVERSATION_ID).isNullOrBlank() ||
            !intent.getStringExtra(IncomingCallStore.EXTRA_SESSION_ID).isNullOrBlank()
    }

    private fun applyIncomingIntent(intent: Intent?) {
        if (intent == null || !intentHasIncoming(intent)) return
        val action = intent.getStringExtra(IncomingCallStore.EXTRA_ACTION) ?: IncomingCallStore.ACTION_RING
        IncomingCallStore.saveFromIntent(this, intent, action)
        if (action == IncomingCallStore.ACTION_ACCEPT || action == IncomingCallStore.ACTION_DECLINE) {
            IncomingCallNotifier.cancel(this)
        }
        IncomingCallPlugin.notifyFlutterIfReady(this)
    }

    private fun applyLockScreen(show: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(show)
            setTurnScreenOn(show)
            if (show) {
                val km = getSystemService(KeyguardManager::class.java)
                km?.requestDismissKeyguard(this, null)
            }
        } else {
            @Suppress("DEPRECATION")
            if (show) {
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                )
            } else {
                @Suppress("DEPRECATION")
                window.clearFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
                )
            }
        }
    }

    /** Turns the screen off when the phone is held to the ear during a voice call. */
    private fun setProximity(enabled: Boolean) {
        val lock = proximityLock
        if (enabled) {
            if (isEmulator()) return
            if (lock?.isHeld == true) return
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
            proximityLock = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "nexchat:call-proximity").apply {
                setReferenceCounted(false)
                acquire(4 * 60 * 60 * 1000L)
            }
        } else if (lock?.isHeld == true) {
            lock.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
        }
    }

    private fun isEmulator(): Boolean {
        val fp = Build.FINGERPRINT
        val model = Build.MODEL
        val hw = Build.HARDWARE
        val product = Build.PRODUCT
        val device = Build.DEVICE
        return fp.startsWith("generic") ||
            fp.contains("emulator") ||
            fp.contains("sdk_gphone", ignoreCase = true) ||
            model.contains("sdk_gphone", ignoreCase = true) ||
            model.contains("Emulator", ignoreCase = true) ||
            model.contains("Android SDK", ignoreCase = true) ||
            product.contains("sdk", ignoreCase = true) ||
            product.contains("emulator", ignoreCase = true) ||
            device.contains("generic", ignoreCase = true) ||
            device.contains("emu", ignoreCase = true) ||
            Build.MANUFACTURER.contains("Genymotion", ignoreCase = true) ||
            hw.contains("ranchu") ||
            hw.contains("goldfish") ||
            hw.contains("cutf") ||
            hw.contains("vsoc")
    }

    /** Many 90/120 Hz phones keep apps at 60 Hz unless the window asks for a faster mode. */
    private fun preferHighestRefreshRate() {
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        if (best.modeId == current.modeId) return
        window.attributes = window.attributes.apply { preferredDisplayModeId = best.modeId }
    }
}
