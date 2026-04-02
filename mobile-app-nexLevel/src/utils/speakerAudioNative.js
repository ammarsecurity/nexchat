import { Capacitor, registerPlugin } from '@capacitor/core'

/**
 * Android: SpeakerAudioPlugin.java — AudioManager.
 * iOS: CapApp-SPM/SpeakerAudioPlugin.swift — AVAudioSession.
 * بعد `cap sync ios` يُشغَّل `capacitor:sync:after` لدمج `CapApp_SPM.SpeakerAudioPlugin` في packageClassList.
 */
const SpeakerAudio = registerPlugin('SpeakerAudio', {
  web: () => ({
    setSpeakerOn: async () => ({ ok: true }),
    resetAudioMode: async () => {}
  })
})

/** مسار الصوت على مستوى النظام (مكبّر / أذن) — ضروري في WebView مع المكالمات */
export async function nativeSetSpeakerOn(speaker) {
  if (!Capacitor.isNativePlatform()) return
  try {
    await SpeakerAudio.setSpeakerOn({ speaker })
  } catch {
    /* تجاهل — الويب أو إصدار قديم */
  }
}

export async function nativeResetAudioMode() {
  if (!Capacitor.isNativePlatform()) return
  try {
    await SpeakerAudio.resetAudioMode()
  } catch {
    /* ignore */
  }
}
