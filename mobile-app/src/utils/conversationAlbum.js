const MAX_ALBUM_IMAGES = 10

export function buildAlbumPayload(urls) {
  const list = (urls || []).filter(Boolean).map(String)
  return JSON.stringify({ urls: list.slice(0, MAX_ALBUM_IMAGES) })
}

export function parseAlbumMessage(content) {
  if (!content || typeof content !== 'string') return null
  const s = content.trim()
  if (!s.startsWith('{')) return null
  try {
    const data = JSON.parse(s)
    const raw = data?.urls ?? data?.Urls
    if (!Array.isArray(raw) || !raw.length) return null
    const urls = raw.map(String).filter(Boolean).slice(0, MAX_ALBUM_IMAGES)
    if (!urls.length) return null
    return { urls }
  } catch {
    return null
  }
}

export function getAlbumPreviewLabel(content, fallback = 'ألبوم صور') {
  const album = parseAlbumMessage(content)
  if (!album) return fallback
  const n = album.urls.length
  if (n === 1) return 'صورة'
  return `${n} صور`
}

/** Localized album preview for conversation list (uses preview text or JSON). */
export function getAlbumListPreviewLabel(content, previewText, t) {
  if (typeof t === 'function') {
    const album = parseAlbumMessage(content || previewText || '')
    if (album) {
      const n = album.urls.length
      if (n === 1) return t('conversationChat.replyPreviewImage')
      return t('conversationChat.albumPhotoCount', { n })
    }
    const m = String(previewText || '').match(/^(\d+)\s*صور$/)
    if (m) return t('conversationChat.albumPhotoCount', { n: Number(m[1]) })
    if (previewText === 'ألبوم صور' || previewText === 'صورة') {
      return previewText === 'صورة'
        ? t('conversationChat.replyPreviewImage')
        : t('conversationChat.albumMessage')
    }
    return t('conversationChat.albumMessage')
  }
  return getAlbumPreviewLabel(content || previewText || '', 'ألبوم صور')
}

export { MAX_ALBUM_IMAGES }
