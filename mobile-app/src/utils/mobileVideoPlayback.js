/**
 * Mobile WebViews (iOS WKWebView, Android WebView) block unmuted autoplay.
 * Play muted first, then unmute when the user has opted into sound.
 */

export function waitForVideoReady(video, timeoutMs = 5000) {
  if (!video) return Promise.resolve(false)
  if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) return Promise.resolve(true)
  return new Promise((resolve) => {
    const done = (ok) => {
      clearTimeout(timer)
      resolve(ok)
    }
    const timer = setTimeout(() => done(false), timeoutMs)
    video.addEventListener('loadeddata', () => done(true), { once: true })
    video.addEventListener('canplay', () => done(true), { once: true })
    video.addEventListener('error', () => done(false), { once: true })
  })
}

/** Start playback for MediaStream / file sources (WebRTC, cached blob, etc.). */
export async function ensureVideoPlaying(video) {
  if (!video) return false
  try {
    await video.play()
    return true
  } catch {
    return false
  }
}

export async function playVideoWithOptionalSound(video, wantSound) {
  if (!video) return { playing: false, muted: true }

  await waitForVideoReady(video)

  if (wantSound) {
    video.muted = true
    try {
      await video.play()
      video.muted = false
      return { playing: true, muted: false }
    } catch {
      video.muted = true
      try {
        await video.play()
        return { playing: true, muted: true }
      } catch {
        return { playing: false, muted: true }
      }
    }
  }

  video.muted = true
  try {
    await video.play()
    return { playing: true, muted: true }
  } catch {
    return { playing: false, muted: true }
  }
}

/** Unmute during a user gesture (tap) — required on mobile before sound can play. */
export async function unmuteVideoOnUserGesture(video) {
  if (!video) return false
  video.muted = false
  try {
    await video.play()
    return true
  } catch {
    video.muted = true
    return false
  }
}
