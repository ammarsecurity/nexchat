package chat.nexlevel.app;

import android.content.Context;
import android.media.AudioManager;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * توجيه الصوت بين مكبّر الصوت وسماعة الأذن أثناء مكالمات WebRTC/LiveKit في WebView.
 * setSinkId وحده غالباً لا يكفي على Android.
 */
@CapacitorPlugin(name = "SpeakerAudio")
public class SpeakerAudioPlugin extends Plugin {

    @SuppressWarnings("deprecation")
    @PluginMethod
    public void setSpeakerOn(PluginCall call) {
        Boolean speaker = call.getBoolean("speaker", false);
        Context ctx = getContext();
        if (ctx == null) {
            call.reject("No context");
            return;
        }
        AudioManager am = (AudioManager) ctx.getSystemService(Context.AUDIO_SERVICE);
        if (am == null) {
            call.reject("AudioManager unavailable");
            return;
        }
        try {
            am.setMode(AudioManager.MODE_IN_COMMUNICATION);
            am.setSpeakerphoneOn(Boolean.TRUE.equals(speaker));
            JSObject ret = new JSObject();
            ret.put("ok", true);
            call.resolve(ret);
        } catch (Exception e) {
            call.reject(e.getMessage() != null ? e.getMessage() : "setSpeakerOn failed");
        }
    }

    @SuppressWarnings("deprecation")
    @PluginMethod
    public void resetAudioMode(PluginCall call) {
        Context ctx = getContext();
        if (ctx == null) {
            call.resolve();
            return;
        }
        AudioManager am = (AudioManager) ctx.getSystemService(Context.AUDIO_SERVICE);
        if (am != null) {
            try {
                am.setSpeakerphoneOn(false);
                am.setMode(AudioManager.MODE_NORMAL);
            } catch (Exception ignored) {
            }
        }
        call.resolve();
    }
}
