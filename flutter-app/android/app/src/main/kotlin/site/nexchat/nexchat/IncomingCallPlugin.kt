package site.nexchat.nexchat

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Bridges incoming-call events to the Flutter engine once Dart is ready. */
object IncomingCallPlugin {
    var channel: MethodChannel? = null
    var flutterReady: Boolean = false
        private set

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    fun detach() {
        channel = null
        flutterReady = false
    }

    fun markReady(context: Context) {
        flutterReady = true
        notifyFlutterIfReady(context)
    }

    fun notifyFlutterIfReady(context: Context) {
        if (!flutterReady) return
        val data = IncomingCallStore.take(context) ?: return
        Handler(Looper.getMainLooper()).post {
            channel?.invokeMethod("incomingEvent", data)
        }
    }
}
