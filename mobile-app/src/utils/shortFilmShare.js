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

/** Conversation list last-message preview (API may return raw JSON for legacy rows). */
export function formatConversationListPreview(preview, fallbackLabel = '') {
  if (!preview) return ''
  const s = String(preview).trim()
  if (s.startsWith('🎬')) return s
  if (!s.startsWith('{')) return preview
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
