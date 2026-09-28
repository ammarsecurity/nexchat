package site.nexchat.nexchat

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Declines a conversation call via REST when Flutter is dead
 * (full-screen UI / notification action / ring timeout).
 */
object CallDeclineHttp {
    private val io = Executors.newSingleThreadExecutor()
    private const val TAG = "CallDeclineHttp"

    fun declineAsync(context: Context, conversationId: String?, outcome: String) {
        if (conversationId.isNullOrBlank()) return
        val app = context.applicationContext
        io.execute {
            try {
                decline(app, conversationId, outcome)
            } catch (e: Exception) {
                Log.w(TAG, "decline failed: ${e.message}")
            }
        }
    }

    private fun decline(context: Context, conversationId: String, outcome: String) {
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val token = flutterPrefs.getString("flutter.nexchat_native_token", null)?.trim().orEmpty()
        val apiBase = flutterPrefs.getString("flutter.nexchat_native_api", null)?.trim().orEmpty()
        if (token.isEmpty() || apiBase.isEmpty()) {
            Log.w(TAG, "missing native auth mirror")
            return
        }
        val base = apiBase.trimEnd('/')
        val url = URL("$base/calls/signaling/decline")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 12_000
            readTimeout = 12_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Authorization", "Bearer $token")
        }
        val body = JSONObject()
            .put("conversationId", conversationId)
            .put("busy", false)
            .put("outcome", outcome)
            .toString()
        OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(body) }
        val code = conn.responseCode
        conn.disconnect()
        if (code !in 200..299) {
            Log.w(TAG, "HTTP $code for decline $conversationId")
        }
    }
}
