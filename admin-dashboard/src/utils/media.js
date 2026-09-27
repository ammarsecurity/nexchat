const MEDIA_BASE = import.meta.env.VITE_MEDIA_URL || 'https://nexchat-cloud.xaronhost.com'

export function fullMediaUrl(url) {
  if (!url) return ''
  const u = String(url).trim()
  if (!u) return ''
  if (u.startsWith('http://') || u.startsWith('https://')) return u
  if (u.startsWith('//')) return `https:${u}`
  // Host without scheme, e.g. cloud.xaronhost.com/uploads/...
  if (/^[a-z0-9.-]+\.[a-z]{2,}\//i.test(u)) return `https://${u}`
  const base = MEDIA_BASE.replace(/\/$/, '')
  return `${base}${u.startsWith('/') ? '' : '/'}${u}`
}

export function hasAvatarImage(avatar) {
  if (!avatar || typeof avatar !== 'string') return false
  const a = avatar.trim()
  if (!a) return false
  if (a.startsWith('http://') || a.startsWith('https://') || a.startsWith('/')) return true
  if (a.includes('/') || a.includes('.')) return true
  return false
}

export function userInitial(name) {
  if (!name) return '?'
  return name.trim()[0].toUpperCase()
}
