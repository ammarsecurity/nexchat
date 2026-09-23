package site.nexchat.nexchat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.roundToInt

/** Lock-screen incoming-call UI shown via the full-screen intent. */
class IncomingCallActivity : Activity() {
    private var conversationId: String? = null
    private var sessionId: String? = null
    private var voiceOnly = false
    private var callerName = ""
    private var callerAvatar: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private val expire = Runnable { decline() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        IncomingCallUi.activity = this
        applyLockScreenFlags()
        readExtras(intent)
        IncomingCallStore.save(this, conversationId, sessionId, voiceOnly, callerName, callerAvatar, IncomingCallStore.ACTION_RING)
        IncomingCallRinger.start(this)
        setContentView(buildUi())
        handler.postDelayed(expire, 60_000)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readExtras(intent)
    }

    override fun onDestroy() {
        handler.removeCallbacks(expire)
        if (IncomingCallUi.activity === this) IncomingCallUi.activity = null
        IncomingCallRinger.stop()
        super.onDestroy()
    }

    private fun readExtras(intent: Intent) {
        conversationId = intent.getStringExtra(IncomingCallStore.EXTRA_CONVERSATION_ID)?.ifBlank { null }
        sessionId = intent.getStringExtra(IncomingCallStore.EXTRA_SESSION_ID)?.ifBlank { null }
        voiceOnly = intent.getBooleanExtra(IncomingCallStore.EXTRA_VOICE_ONLY, false)
        callerName = intent.getStringExtra(IncomingCallStore.EXTRA_CALLER_NAME)?.ifBlank { "…" } ?: "…"
        callerAvatar = intent.getStringExtra(IncomingCallStore.EXTRA_CALLER_AVATAR)?.ifBlank { null }
    }

    private fun applyLockScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(KeyguardManager::class.java)
            km?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = Color.parseColor("#0B141A")
        window.navigationBarColor = Color.parseColor("#0A1014")
        window.decorView.layoutDirection = View.LAYOUT_DIRECTION_RTL
    }

    private fun buildUi(): View {
        val bg = GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(Color.parseColor("#0B141A"), Color.parseColor("#111B21"), Color.parseColor("#0A1014")),
        )
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = bg
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(72), dp(24), dp(48))
            layoutDirection = View.LAYOUT_DIRECTION_RTL
        }

        val status = TextView(this).apply {
            text = if (voiceOnly) "مكالمة صوتية واردة" else "مكالمة فيديو واردة"
            setTextColor(Color.argb(184, 255, 255, 255))
            textSize = 16f
            gravity = Gravity.CENTER
        }

        val avatar = TextView(this).apply {
            text = callerName.trim().firstOrNull()?.toString() ?: "?"
            setTextColor(Color.WHITE)
            textSize = 44f
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            background = circle(Color.parseColor("#00A884"))
            val size = dp(132)
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dp(48)
            }
        }

        val name = TextView(this).apply {
            text = callerName
            setTextColor(Color.WHITE)
            textSize = 28f
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(28), 0, 0)
        }

        val spacer = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
        }

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }
        actions.addView(circleButton("رفض", Color.parseColor("#E54B4B")) { decline() })
        actions.addView(View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(72), 1)
        })
        actions.addView(circleButton(if (voiceOnly) "قبول" else "قبول", Color.parseColor("#25D366")) { accept() })

        root.addView(status)
        root.addView(avatar)
        root.addView(name)
        root.addView(spacer)
        root.addView(actions)
        return root
    }

    private fun circleButton(label: String, color: Int, onClick: () -> Unit): LinearLayout {
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        val btn = TextView(this).apply {
            text = if (label == "رفض") "✕" else "☎"
            setTextColor(Color.WHITE)
            textSize = 28f
            gravity = Gravity.CENTER
            background = circle(color)
            val size = dp(68)
            layoutParams = LinearLayout.LayoutParams(size, size)
            setOnClickListener { onClick() }
        }
        val text = TextView(this).apply {
            text = label
            setTextColor(Color.argb(200, 255, 255, 255))
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, 0)
        }
        col.addView(btn)
        col.addView(text)
        return col
    }

    private fun accept() {
        IncomingCallStore.save(this, conversationId, sessionId, voiceOnly, callerName, callerAvatar, IncomingCallStore.ACTION_ACCEPT)
        IncomingCallNotifier.cancel(this, finishActivity = false)
        IncomingCallPlugin.notifyFlutterIfReady(this)
        startActivity(
            IncomingCallStore.putOn(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                conversationId,
                sessionId,
                voiceOnly,
                callerName,
                callerAvatar,
                IncomingCallStore.ACTION_ACCEPT,
            ),
        )
        finish()
    }

    private fun decline() {
        IncomingCallStore.save(this, conversationId, sessionId, voiceOnly, callerName, callerAvatar, IncomingCallStore.ACTION_DECLINE)
        IncomingCallNotifier.cancel(this, finishActivity = false)
        IncomingCallPlugin.notifyFlutterIfReady(this)
        if (!IncomingCallPlugin.flutterReady) IncomingCallStore.clear(this)
        finish()
    }

    private fun circle(color: Int) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).roundToInt()
}

object IncomingCallUi {
    var activity: IncomingCallActivity? = null
    fun finish() {
        activity?.finish()
        activity = null
    }
}
