import { ensureAbsoluteUrl } from './imageUrl'

const API_ORIGIN = (() => {
  const base = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'
  return base.replace(/\/api\/?$/, '')
})()

/** SPA origin (hash routes) — e.g. https://web.nexchat.site */
export function getPublicAppOrigin() {
  const configured = import.meta.env.VITE_PUBLIC_APP_URL
  if (configured && typeof configured === 'string') {
    return configured.replace(/\/$/, '')
  }
  return API_ORIGIN
}

/** API host for OG share pages (/join, /share/film, …) */
export function getShareApiOrigin() {
  return API_ORIGIN
}

export function normalizeInviteCode(code) {
  if (!code) return ''
  const c = String(code).trim().toUpperCase()
  if (!c.startsWith('NX-')) return ''
  return c.length === 7 ? c : ''
}

export function buildInvitePath(code) {
  const normalized = normalizeInviteCode(code)
  if (!normalized) return '/home'
  return `/join/${encodeURIComponent(normalized)}`
}

export function buildInviteUrl(code) {
  return buildInviteWebUrl(code)
}

export function buildInviteWebUrl(code) {
  const normalized = normalizeInviteCode(code)
  if (!normalized) return getPublicAppOrigin()
  return `${getShareApiOrigin()}/join/${encodeURIComponent(normalized)}`
}

export function buildShortFilmSharePath(filmId) {
  if (!filmId) return '/short-films'
  return `/short-films/watch?start=${encodeURIComponent(String(filmId))}`
}

export function buildShortFilmShareUrl(filmId) {
  const id = String(filmId || '').trim()
  if (!id) return `${getPublicAppOrigin()}/#/short-films`
  return `${getShareApiOrigin()}/share/film/${encodeURIComponent(id)}`
}

export function buildStorySharePath(userId) {
  if (!userId) return '/conversations'
  return `/stories/view/${encodeURIComponent(String(userId))}`
}

export function buildStoryShareUrl(userId) {
  const id = String(userId || '').trim()
  if (!id) return `${getPublicAppOrigin()}/#/conversations`
  return `${getShareApiOrigin()}/share/story/${encodeURIComponent(id)}`
}

export function buildAppHashUrl(path, query = {}) {
  const origin = getPublicAppOrigin()
  const q = new URLSearchParams()
  for (const [k, v] of Object.entries(query)) {
    if (v != null && v !== '') q.set(k, String(v))
  }
  const qs = q.toString()
  const p = path.startsWith('/') ? path : `/${path}`
  return `${origin}/#${p}${qs ? `?${qs}` : ''}`
}

/** Parse invite / share URLs (https, custom scheme, or hash routes). */
export function parseShareTargetFromUrl(rawUrl) {
  if (!rawUrl || typeof rawUrl !== 'string') return null
  let url
  try {
    url = new URL(rawUrl.replace(/^nexchat:\/\//i, 'https://nexchat.app/'))
  } catch {
    return null
  }

  const hashPath = url.hash?.startsWith('#') ? url.hash.slice(1).split('?')[0] : ''
  const path = (url.pathname || '') + (hashPath || '')

  let joinMatch = path.match(/\/join\/([A-Za-z0-9-]+)/i)
  if (!joinMatch) {
    const code = url.searchParams.get('code') || url.searchParams.get('invite')
    if (code && normalizeInviteCode(code)) {
      return { type: 'invite', code: normalizeInviteCode(code) }
    }
  } else {
    const code = normalizeInviteCode(joinMatch[1])
    if (code) return { type: 'invite', code }
  }

  const filmShareMatch = path.match(/\/share\/film\/([0-9a-f-]{36})/i)
  if (filmShareMatch?.[1]) {
    return { type: 'short_film', filmId: String(filmShareMatch[1]) }
  }
  if (path.includes('/short-films/watch')) {
    const hashQs = url.hash?.includes('?') ? url.hash.slice(url.hash.indexOf('?') + 1) : ''
    const hashParams = new URLSearchParams(hashQs)
    const id = url.searchParams.get('start') || hashParams.get('start')
    if (id) return { type: 'short_film', filmId: String(id) }
  }

  const storyMatch = path.match(/\/share\/story\/([0-9a-f-]{36})/i)
    || path.match(/\/stories\/view\/([0-9a-f-]{36})/i)
  if (storyMatch) {
    return { type: 'story', userId: String(storyMatch[1]) }
  }

  return null
}

export function absoluteMediaUrl(url) {
  if (!url) return null
  return ensureAbsoluteUrl(url)
}
