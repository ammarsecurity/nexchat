/** @typedef {{ color: string, size: number, points: { x: number, y: number }[] }} StoryStroke */
/** @typedef {{ text: string, x: number, y: number, color: string, fontSize: number, scale?: number }} StoryTextLayer */
/** @typedef {{ emoji: string, x: number, y: number, scale: number }} StorySticker */

export class StoryExportError extends Error {
  constructor(message = 'Story export failed', code = 'STORY_EXPORT_FAILED') {
    super(message)
    this.name = 'StoryExportError'
    this.code = code
  }
}

const BG_GRADIENTS = {
  'linear-gradient(135deg,#6c63ff 0%,#ff6584 100%)': ['#6c63ff', '#ff6584'],
  'linear-gradient(135deg,#0ea5e9 0%,#6c63ff 100%)': ['#0ea5e9', '#6c63ff'],
  'linear-gradient(135deg,#f97316 0%,#ec4899 100%)': ['#f97316', '#ec4899'],
  'linear-gradient(135deg,#22c55e 0%,#14b8a6 100%)': ['#22c55e', '#14b8a6']
}

const EXPORT_MAX_DIMS = [1080, 720, 540]
const EXPORT_QUALITIES = [0.85, 0.8, 0.72]
const TEXT_STORY_SIZE = { w: 720, h: 1280 }

export function fitExportSize(imgW, imgH, maxDim) {
  let w = imgW
  let h = imgH
  if (Math.max(w, h) > maxDim) {
    const s = maxDim / Math.max(w, h)
    w = Math.round(w * s)
    h = Math.round(h * s)
  }
  return { w: Math.max(1, w), h: Math.max(1, h) }
}

function isLocalImageSrc(src) {
  return src.startsWith('blob:') || src.startsWith('data:') || src.startsWith('capacitor://')
}

function loadImageElement(src, crossOrigin = false) {
  return new Promise((resolve, reject) => {
    const img = new Image()
    if (crossOrigin) img.crossOrigin = 'anonymous'
    img.onload = () => resolve(img)
    img.onerror = () => reject(new StoryExportError('Image decode failed'))
    img.src = src
  })
}

async function readSourceBlob(src) {
  if (isLocalImageSrc(src)) {
    const res = await fetch(src)
    if (!res.ok) throw new StoryExportError('Image fetch failed')
    return res.blob()
  }
  const res = await fetch(src, { credentials: 'include' })
  if (!res.ok) throw new StoryExportError('Image fetch failed')
  return res.blob()
}

function downscaleWithCanvas(source, maxDim) {
  const size = fitExportSize(source.width, source.height, maxDim)
  const canvas = document.createElement('canvas')
  canvas.width = size.w
  canvas.height = size.h
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new StoryExportError('Canvas unavailable')
  ctx.drawImage(source, 0, 0, size.w, size.h)
  source.close?.()
  return { bitmap: canvas, width: size.w, height: size.h, closeable: false }
}

async function decodeBitmapFromBlob(blob, maxDim) {
  if (typeof createImageBitmap !== 'function') {
    const objectUrl = URL.createObjectURL(blob)
    try {
      const img = await loadImageElement(objectUrl, false)
      return downscaleWithCanvas(img, maxDim)
    } finally {
      URL.revokeObjectURL(objectUrl)
    }
  }

  try {
    const probe = await createImageBitmap(blob)
    const size = fitExportSize(probe.width, probe.height, maxDim)
    probe.close?.()
    if (size.w === probe.width && size.h === probe.height) {
      return {
        bitmap: await createImageBitmap(blob),
        width: size.w,
        height: size.h,
        closeable: true
      }
    }
    try {
      return {
        bitmap: await createImageBitmap(blob, {
          resizeWidth: size.w,
          resizeHeight: size.h,
          resizeQuality: 'high'
        }),
        width: size.w,
        height: size.h,
        closeable: true
      }
    } catch {
      const objectUrl = URL.createObjectURL(blob)
      try {
        const img = await loadImageElement(objectUrl, false)
        return downscaleWithCanvas(img, maxDim)
      } finally {
        URL.revokeObjectURL(objectUrl)
      }
    }
  } catch {
    const objectUrl = URL.createObjectURL(blob)
    try {
      const img = await loadImageElement(objectUrl, false)
      return downscaleWithCanvas(img, maxDim)
    } finally {
      URL.revokeObjectURL(objectUrl)
    }
  }
}

async function loadImageForExport(src, maxDim) {
  if (!src) throw new StoryExportError('Missing image source')

  try {
    const blob = await readSourceBlob(src)
    return decodeBitmapFromBlob(blob, maxDim)
  } catch {
    const img = await loadImageElement(src, !isLocalImageSrc(src))
    return downscaleWithCanvas(img, maxDim)
  }
}

export function fillStoryBackground(ctx, w, h, backgroundColor) {
  const stops = BG_GRADIENTS[backgroundColor]
  if (stops) {
    const grd = ctx.createLinearGradient(0, 0, w, h)
    grd.addColorStop(0, stops[0])
    grd.addColorStop(1, stops[1])
    ctx.fillStyle = grd
  } else if (backgroundColor?.startsWith('#')) {
    ctx.fillStyle = backgroundColor
  } else {
    const grd = ctx.createLinearGradient(0, 0, w, h)
    grd.addColorStop(0, '#6c63ff')
    grd.addColorStop(1, '#ff6584')
    ctx.fillStyle = grd
  }
  ctx.fillRect(0, 0, w, h)
}

function drawOverlays(ctx, w, h, uiScale, strokes, textLayers, stickers, textFontSize) {
  for (const stroke of strokes) {
    if (!stroke.points?.length) continue
    ctx.strokeStyle = stroke.color
    ctx.lineWidth = Math.max(1, stroke.size * uiScale)
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.beginPath()
    stroke.points.forEach((p, i) => {
      const x = (p.x / 100) * w
      const y = (p.y / 100) * h
      if (i === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    })
    ctx.stroke()
  }

  for (const layer of textLayers) {
    if (!layer.text) continue
    ctx.fillStyle = layer.color
    ctx.font = `bold ${Math.max(12, textFontSize(layer) * uiScale)}px Cairo, sans-serif`
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(layer.text, (layer.x / 100) * w, (layer.y / 100) * h)
  }

  for (const s of stickers) {
    if (!s.emoji) continue
    ctx.font = `${Math.max(24, 48 * s.scale * uiScale)}px "Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", sans-serif`
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(s.emoji, (s.x / 100) * w, (s.y / 100) * h)
  }
}

function canvasToJpegBlob(canvas, quality) {
  return new Promise((resolve, reject) => {
    const finalize = (blob) => {
      if (blob && blob.size > 0) resolve(blob)
      else reject(new StoryExportError('Canvas blob empty'))
    }

    const fallbackDataUrl = () => {
      try {
        const dataUrl = canvas.toDataURL('image/jpeg', quality)
        const base64 = dataUrl.split(',')[1]
        if (!base64) throw new StoryExportError('Canvas data URL failed')
        const binary = atob(base64)
        const bytes = new Uint8Array(binary.length)
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
        finalize(new Blob([bytes], { type: 'image/jpeg' }))
      } catch (err) {
        reject(err instanceof StoryExportError ? err : new StoryExportError(err?.message || 'Canvas export failed'))
      }
    }

    try {
      if (typeof canvas.toBlob === 'function') {
        canvas.toBlob((blob) => {
          if (blob) finalize(blob)
          else fallbackDataUrl()
        }, 'image/jpeg', quality)
        return
      }
      fallbackDataUrl()
    } catch (err) {
      reject(err instanceof StoryExportError ? err : new StoryExportError(err?.message || 'Canvas export failed'))
    }
  })
}

async function composeStoryFrame(canvas, options, maxDim, quality) {
  const ctx = canvas.getContext('2d', { alpha: false })
  if (!ctx) throw new StoryExportError('Canvas unavailable')

  const {
    textOnly,
    imageSrc,
    videoSrc,
    backgroundColor,
    filterCss,
    strokes,
    textLayers,
    stickers,
    textFontSize,
    videoPreviewLabel
  } = options

  let w = TEXT_STORY_SIZE.w
  let h = TEXT_STORY_SIZE.h
  let source = null
  let closeSource = false

  if (textOnly) {
    w = TEXT_STORY_SIZE.w
    h = TEXT_STORY_SIZE.h
  } else if (imageSrc) {
    const loaded = await loadImageForExport(imageSrc, maxDim)
    source = loaded.bitmap
    w = loaded.width
    h = loaded.height
    closeSource = loaded.closeable
  } else if (videoSrc) {
    w = TEXT_STORY_SIZE.w
    h = TEXT_STORY_SIZE.h
  }

  canvas.width = w
  canvas.height = h
  ctx.clearRect(0, 0, w, h)

  if (textOnly) {
    fillStoryBackground(ctx, w, h, backgroundColor)
  } else if (imageSrc && source) {
    try {
      if (filterCss && filterCss !== 'none') {
        ctx.filter = filterCss
        ctx.drawImage(source, 0, 0, w, h)
        ctx.filter = 'none'
      } else {
        ctx.drawImage(source, 0, 0, w, h)
      }
    } finally {
      ctx.filter = 'none'
      if (closeSource) source.close?.()
    }
  } else if (videoSrc) {
    ctx.fillStyle = '#111'
    ctx.fillRect(0, 0, w, h)
    ctx.fillStyle = '#fff'
    ctx.font = '16px Cairo, sans-serif'
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(videoPreviewLabel || 'Video', w / 2, h / 2)
  }

  const uiScale = w / 360
  drawOverlays(ctx, w, h, uiScale, strokes, textLayers, stickers, textFontSize)

  return canvasToJpegBlob(canvas, quality)
}

export async function exportStoryImage(canvas, options) {
  if (!canvas) throw new StoryExportError('Canvas unavailable')

  if (typeof document !== 'undefined' && document.fonts?.ready) {
    try {
      await Promise.race([
        document.fonts.ready,
        new Promise((resolve) => setTimeout(resolve, 1500))
      ])
    } catch {
      /* ignore font load errors */
    }
  }

  let lastError = null
  for (let i = 0; i < EXPORT_MAX_DIMS.length; i++) {
    try {
      const blob = await composeStoryFrame(canvas, options, EXPORT_MAX_DIMS[i], EXPORT_QUALITIES[i])
      if (blob) return blob
    } catch (err) {
      lastError = err
      canvas.width = 1
      canvas.height = 1
    }
  }

  throw lastError instanceof StoryExportError
    ? lastError
    : new StoryExportError(lastError?.message || 'Story export failed')
}

export function isStoryExportError(err) {
  return err?.name === 'StoryExportError' || err?.code === 'STORY_EXPORT_FAILED'
}
