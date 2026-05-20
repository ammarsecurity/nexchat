/** @type {Map<string, string>} */
const posterCache = new Map()

/** @type {Map<string, Promise<string|null>>} */
const inFlight = new Map()

const VIDEO_EXT = /\.(mp4|webm|mov)(\?|$)/i

/**
 * @param {string | null | undefined} url
 */
export function isVideoUrl(url) {
  if (!url || typeof url !== 'string') return false
  return VIDEO_EXT.test(url.split('#')[0])
}

/**
 * Extract first frame from a video URL as a JPEG data URL.
 * @param {string} videoUrl
 * @param {{ seekSeconds?: number, timeoutMs?: number, maxWidth?: number }} [options]
 * @returns {Promise<string|null>}
 */
export function captureVideoPoster(videoUrl, options = {}) {
  if (!videoUrl) return Promise.resolve(null)

  const normalized = videoUrl.split('#')[0]
  if (posterCache.has(normalized)) {
    return Promise.resolve(posterCache.get(normalized))
  }

  if (inFlight.has(normalized)) {
    return inFlight.get(normalized)
  }

  const {
    seekSeconds = 0.1,
    timeoutMs = 12000,
    maxWidth = 320
  } = options

  const promise = new Promise((resolve) => {
    const video = document.createElement('video')
    video.muted = true
    video.playsInline = true
    video.preload = 'auto'
    video.setAttribute('playsinline', '')
    video.crossOrigin = 'anonymous'

    let settled = false
    const finish = (dataUrl) => {
      if (settled) return
      settled = true
      cleanup()
      if (dataUrl) posterCache.set(normalized, dataUrl)
      resolve(dataUrl)
    }

    const cleanup = () => {
      clearTimeout(timer)
      video.removeAttribute('src')
      video.load()
      video.onloadeddata = null
      video.onseeked = null
      video.onerror = null
    }

    const timer = setTimeout(() => finish(null), timeoutMs)

    const drawFrame = () => {
      try {
        const w = video.videoWidth
        const h = video.videoHeight
        if (!w || !h) {
          finish(null)
          return
        }
        const scale = w > maxWidth ? maxWidth / w : 1
        const cw = Math.max(1, Math.round(w * scale))
        const ch = Math.max(1, Math.round(h * scale))
        const canvas = document.createElement('canvas')
        canvas.width = cw
        canvas.height = ch
        const ctx = canvas.getContext('2d')
        if (!ctx) {
          finish(null)
          return
        }
        ctx.drawImage(video, 0, 0, cw, ch)
        finish(canvas.toDataURL('image/jpeg', 0.85))
      } catch {
        finish(null)
      }
    }

    video.onloadeddata = () => {
      const target = Math.min(seekSeconds, Math.max(0, (video.duration || 1) - 0.05))
      video.onseeked = drawFrame
      try {
        video.currentTime = target
      } catch {
        drawFrame()
      }
    }

    video.onerror = () => finish(null)
    video.src = normalized
    video.load()
  }).finally(() => {
    inFlight.delete(normalized)
  })

  inFlight.set(normalized, promise)
  return promise
}

/**
 * @param {string} url
 */
export function getCachedVideoPoster(url) {
  if (!url) return null
  return posterCache.get(url.split('#')[0]) ?? null
}

export function clearVideoPosterCache() {
  posterCache.clear()
  inFlight.clear()
}
