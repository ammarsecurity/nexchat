import { Capacitor } from '@capacitor/core'

function vibrate(ms = 8) {
  if (typeof navigator !== 'undefined' && navigator.vibrate) {
    navigator.vibrate(ms)
  }
}

export async function hapticLight() {
  if (!Capacitor.isNativePlatform()) return
  vibrate(8)
}

export async function hapticSuccess() {
  if (!Capacitor.isNativePlatform()) return
  vibrate(16)
}
