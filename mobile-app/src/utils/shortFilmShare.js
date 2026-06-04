import { getAlbumListPreviewLabel, getAlbumPreviewLabel, parseAlbumMessage } from './conversationAlbum'

const SHORT_FILM_LINK_RE = /short-films\/watch\?start=([0-9a-f-]{36})/i

export function buildShortFilmShareMessage(film) {
  return {
    type: 'short_film',
    content: JSON.stringify({
      id: String(film.id),
      title: film.title || '',
      thumbnailUrl: film.thumbnailUrl || null
    })
  }
}

const MEDIA_PREVIEW_TYPES = new Set(['image', 'audio', 'video', 'album', 'short_film'])

function isVideoUrl(s) {
  const lower = s.toLowerCase()
  return /\.(mp4|mov|webm)(\?|$)/i.test(lower) || (lower.includes('/uploads/') && lower.includes('.mp4'))
}

function isImageUrl(s) {
  const lower = s.toLowerCase()
  return /\.(jpg|jpeg|png|gif|webp)(\?|$)/i.test(lower) || (lower.includes('/uploads/') && (lower.includes('jpg') || lower.includes('png') || lower.includes('webp')))
}

function isAudioUrl(s) {
  const lower = s.toLowerCase()
  return /\.(webm|m4a|ogg|opus|mp3|wav)(\?|$)/i.test(lower) || (lower.includes('/uploads/') && (lower.includes('webm') || lower.includes('m4a') || lower.includes('ogg')))
}

function previewFromType(type, preview, fallbackLabel, t) {
  if (!type || !MEDIA_PREVIEW_TYPES.has(type)) return null
  if (typeof t !== 'function') return null
  switch (type) {
    case 'video':
      return t('conversationChat.videoMessage')
    case 'image':
      return t('conversationChat.replyPreviewImage')
    case 'audio':
      return t('conversationChat.voiceMessage')
    case 'album':
      return getAlbumListPreviewLabel(preview, preview, t)
    case 'short_film': {
      if (!preview) return fallbackLabel ? `🎬 ${fallbackLabel}` : ''
      return formatConversationListPreview(preview, fallbackLabel, { t })
    }
    default:
      return null
  }
}

/** Conversation list last-message preview (API may return raw JSON for legacy rows). */
export function formatConversationListPreview(preview, fallbackLabel = '', opts = {}) {
  const { t, type } = opts
  const msgType = type || opts?.lastMessageType || opts?.LastMessageType
  const byType = previewFromType(msgType, preview, fallbackLabel, t)
  if (byType) return byType

  if (!preview) return ''
  const s = String(preview).trim()

  if (typeof t === 'function') {
    if (s === 'فيديو' || s === 'video' || s.toLowerCase() === 'video') return t('conversationChat.videoMessage')
    if (s === 'صورة' || s === 'image') return t('conversationChat.replyPreviewImage')
    if (s === 'رسالة صوتية') return t('conversationChat.voiceMessage')
    if (s === 'ألبوم صور' || /^\d+ صور$/.test(s)) return getAlbumListPreviewLabel(null, s, t)
    if (isVideoUrl(s)) return t('conversationChat.videoMessage')
    if (isAudioUrl(s)) return t('conversationChat.voiceMessage')
    if (isImageUrl(s) && msgType !== 'album') return t('conversationChat.replyPreviewImage')
  } else {
    if (s === 'فيديو' || s === 'video') return s
    if (/^\d+ صور$/.test(s) || s === 'ألبوم صور') return s
  }

  if (s.startsWith('🎬')) return s
  if (!s.startsWith('{')) return preview

  const album = parseAlbumMessage(s)
  if (album) {
    return typeof t === 'function'
      ? getAlbumListPreviewLabel(s, s, t)
      : getAlbumPreviewLabel(s, fallbackLabel || 'ألبوم صور')
  }
  try {
    const data = JSON.parse(s)
    const id = data?.id ?? data?.Id
    if (!id) return preview
    const title = String(data.title ?? data.Title ?? '').trim()
    const text = title || fallbackLabel
    const out = `🎬 ${text}`
    return out.length > 50 ? `${out.slice(0, 50)}…` : out
  } catch {
    return preview
  }
}

export function parseShortFilmMessage(msg) {
  if (!msg) return null
  const type = msg.type ?? msg.Type ?? 'text'
  const content = msg.content ?? msg.Content ?? ''

  if (type === 'short_film') {
    try {
      const data = typeof content === 'string' ? JSON.parse(content) : content
      const id = data?.id ?? data?.Id
      if (!id) return null
      return {
        id: String(id),
        title: data.title ?? data.Title ?? '',
        thumbnailUrl: data.thumbnailUrl ?? data.ThumbnailUrl ?? null
      }
    } catch {
      return null
    }
  }

  if (type !== 'text' || !content) return null
  const match = content.match(SHORT_FILM_LINK_RE)
  if (!match) return null
  const titleLine = content.split('\n').find((line) => line.trim() && !line.includes('short-films/watch'))
  const title = titleLine?.replace(/^🎬\s*/, '').trim() || ''
  return {
    id: match[1],
    title,
    thumbnailUrl: null
  }
}
