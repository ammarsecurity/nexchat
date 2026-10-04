/** Helpers for admin chat message content (call / short_film / album / media URLs). */

export function parseJsonObject(content) {
  if (!content || typeof content !== 'string') return null
  const s = content.trim()
  if (!s.startsWith('{')) return null
  try {
    const data = JSON.parse(s)
    return data && typeof data === 'object' && !Array.isArray(data) ? data : null
  } catch {
    return null
  }
}

export function parseAlbumUrls(content) {
  const data = parseJsonObject(content)
  const raw = data?.urls ?? data?.Urls
  if (!Array.isArray(raw) || !raw.length) return null
  const urls = raw.map(String).filter(Boolean).slice(0, 10)
  return urls.length ? urls : null
}

export function parseShortFilm(content) {
  const data = parseJsonObject(content)
  if (!data) return null
  const id = data.id ?? data.Id
  if (id == null && !(data.title || data.Title || data.thumbnailUrl || data.ThumbnailUrl)) return null
  // Call payloads also look like JSON objects — exclude them.
  if (data.status != null && (data.voiceOnly != null || data.durationSec != null)) return null
  if (Array.isArray(data.urls || data.Urls)) return null
  // Story share uses userId, not film id/title.
  if (data.userId != null || data.UserId != null) return null
  return {
    id: id != null ? String(id) : '',
    title: String(data.title ?? data.Title ?? '').trim(),
    thumbnailUrl: data.thumbnailUrl ?? data.ThumbnailUrl ?? data.url ?? data.Url ?? null
  }
}

export function parseStoryShare(content) {
  const data = parseJsonObject(content)
  if (!data) return null
  const userId = data.userId ?? data.UserId
  if (!userId) return null
  return {
    userId: String(userId),
    name: String(data.name ?? data.Name ?? '').trim() || 'NexChat',
    mediaUrl: data.mediaUrl ?? data.MediaUrl ?? null,
    mediaType: String(data.mediaType ?? data.MediaType ?? 'image').toLowerCase(),
    caption: data.caption ?? data.Caption ?? null
  }
}

export function parseCall(content) {
  const data = parseJsonObject(content)
  if (!data || data.status == null) return null
  if (data.voiceOnly == null && data.durationSec == null && data.DurationSec == null) {
    // Still accept if status is a known call status
    const st = String(data.status).toLowerCase()
    if (!['ended', 'cancelled', 'declined', 'busy', 'missed'].includes(st)) return null
  }
  const durationSec = parseInt(String(data.durationSec ?? data.DurationSec ?? 0), 10) || 0
  return {
    status: String(data.status ?? 'missed').toLowerCase(),
    voiceOnly: data.voiceOnly === true || data.voiceOnly === 'true' || data.VoiceOnly === true,
    durationSec
  }
}

export function parseLocation(content) {
  const data = parseJsonObject(content)
  if (!data) return null
  const lat = Number(data.lat ?? data.latitude)
  const lng = Number(data.lng ?? data.lon ?? data.longitude)
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null
  return {
    lat,
    lng,
    name: String(data.name ?? data.Name ?? '').trim() || 'موقع',
    mapsUrl: `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`
  }
}

export function parseFile(content) {
  const data = parseJsonObject(content)
  if (!data) return null
  const url = String(data.url ?? data.Url ?? '').trim()
  const name = String(data.name ?? data.Name ?? data.fileName ?? '').trim()
  if (!url || !name) return null
  const size = Number(data.size ?? data.Size ?? 0) || 0
  return { url, name, size }
}

function fmtDuration(sec) {
  const m = String(Math.floor(sec / 60)).padStart(2, '0')
  const s = String(sec % 60).padStart(2, '0')
  return `${m}:${s}`
}

/** Arabic WhatsApp-style call label for admin. */
export function formatCallLabel(content) {
  const call = parseCall(content)
  if (!call) return 'مكالمة'
  const kind = call.voiceOnly ? 'صوتية' : 'فيديو'
  const dur = call.durationSec > 0 ? ` · ${fmtDuration(call.durationSec)}` : ''
  switch (call.status) {
    case 'ended':
      return `مكالمة ${kind} منتهية${dur}`
    case 'cancelled':
      return `مكالمة ${kind} ملغاة`
    case 'declined':
      return `مكالمة ${kind} مرفوضة`
    case 'busy':
      return `المستخدم مشغول (${kind})`
    case 'missed':
    default:
      return `مكالمة ${kind} فائتة`
  }
}

export function callIcon(content) {
  const call = parseCall(content)
  if (!call) return 'mdi-phone'
  if (call.voiceOnly) {
    return call.status === 'ended' ? 'mdi-phone' : 'mdi-phone-missed'
  }
  return call.status === 'ended' ? 'mdi-video' : 'mdi-video-off'
}

export function looksLikeMediaUrl(content, extHint) {
  if (!content || typeof content !== 'string') return false
  const s = content.trim().toLowerCase()
  if (s.startsWith('{')) return false
  if (extHint === 'image') {
    return /\.(jpe?g|png|gif|webp|bmp|heic)(\?|$)/i.test(s) || s.includes('/uploads/')
  }
  if (extHint === 'video') {
    return /\.(mp4|webm|mov|m4v)(\?|$)/i.test(s) || s.includes('/uploads/')
  }
  if (extHint === 'audio') {
    return /\.(m4a|mp3|aac|ogg|wav|opus)(\?|$)/i.test(s) || s.includes('/uploads/')
  }
  return false
}
