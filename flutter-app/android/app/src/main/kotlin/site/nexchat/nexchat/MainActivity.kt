package site.nexchat.nexchat

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var proximityLock: PowerManager.WakeLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferHighestRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexchat/call").setMethodCallHandler { call, result ->
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
                    result.success(null)
                }
                "proximity" -> {
                    setProximity(call.argument<Boolean>("enabled") == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        setProximity(false)
        super.onDestroy()
    }

    /** Turns the screen off when the phone is held to the ear during a voice call. */
    private fun setProximity(enabled: Boolean) {
        val lock = proximityLock
        if (enabled) {
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
