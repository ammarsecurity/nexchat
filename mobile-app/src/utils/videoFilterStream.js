/**
 * ينشئ ستريم فيديو معدّل بالفلتر من مسار الكاميرا.
 * الفلتر يُطبّق على الستريم المرسل فيبصره الطرف الآخر.
 * @param {MediaStreamTrack} videoTrack - مسار الفيديو من الكاميرا
 * @param {() => string} getFilterCss - دالة تُرجع قيمة CSS للفلتر (مثل 'grayscale(100%)' أو 'none')
 * @returns {{ stream: MediaStream, stop: () => void }}
 */
export function createFilteredVideoStream(videoTrack, getFilterCss) {
  const video = document.createElement('video')
  video.autoplay = true
  video.playsInline = true
  video.muted = true
  video.srcObject = new MediaStream([videoTrack])

  const canvas = document.createElement('canvas')
  const ctx = canvas.getContext('2d')
  let rafId = null
  let stopped = false

  function draw() {
    if (stopped) return
    if (video.readyState >= 2 && video.videoWidth > 0) {
      if (canvas.width !== video.videoWidth || canvas.height !== video.videoHeight) {
        canvas.width = video.videoWidth
        canvas.height = video.videoHeight
      }
      ctx.filter = getFilterCss() || 'none'
      ctx.drawImage(video, 0, 0)
    }
    rafId = requestAnimationFrame(draw)
  }

  video.onloadedmetadata = () => {
    video.play().catch(() => {})
    draw()
  }

  const stream = canvas.captureStream(30)

  return {
    stream,
    stop() {
      stopped = true
      if (rafId) cancelAnimationFrame(rafId)
      video.srcObject = null
      stream.getTracks().forEach(t => t.stop())
    }
  }
}
