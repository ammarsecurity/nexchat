const MEDIA_BASE = import.meta.env.VITE_MEDIA_URL || 'https://nexchat-cloud.xaronhost.com'

export function fullMediaUrl(url) {
  if (!url) return ''
  if (url.startsWith('http://') || url.startsWith('https://')) return url
  const base = MEDIA_BASE.replace(/\/$/, '')
  return `${base}${url.startsWith('/') ? '' : '/'}${url}`
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
