/**
 * يطلب صلاحيات الكاميرا والميكروفون عند فتح التطبيق
 * حتى يعمل المكالمات الصوتية/المرئية بشكل طبيعي
 */
export async function requestMediaPermissions() {
  if (!navigator.mediaDevices?.getUserMedia) return
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true })
    stream.getTracks().forEach((t) => t.stop())
  } catch {
    // المستخدم رفض أو الجهاز لا يدعم - نتجاهل
  }
}
