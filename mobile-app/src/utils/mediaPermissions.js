import { Capacitor } from '@capacitor/core'
import { Camera } from '@capacitor/camera'

/**
 * يطلب صلاحيات الكاميرا والميكروفون عند فتح التطبيق
 * حتى يعمل المكالمات الصوتية/المرئية بشكل طبيعي
 * على Android: يطلب الصلاحيات أصلياً أولاً ثم getUserMedia
 */
export async function requestMediaPermissions() {
  if (Capacitor.isNativePlatform()) {
    try {
      await Camera.requestPermissions({ permissions: ['camera'] })
    } catch {
      // تجاهل فشل طلب الصلاحيات
    }
  }
  if (!navigator.mediaDevices?.getUserMedia) return
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true })
    stream.getTracks().forEach((t) => t.stop())
  } catch {
    // المستخدم رفض أو الجهاز لا يدعم - نتجاهل
  }
}
