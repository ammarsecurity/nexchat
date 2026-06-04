import { Capacitor } from '@capacitor/core'
import { App } from '@capacitor/app'
import { parseShareTargetFromUrl, buildAppHashUrl } from '../utils/shareLinks'

/**
 * Navigate to invite / story / film from external URL.
 * @param {import('vue-router').Router} router
 * @param {{ type: string, code?: string, userId?: string, filmId?: string }} target
 */
export function navigateFromShareTarget(router, target) {
  if (!router || !target?.type) return false

  if (target.type === 'invite' && target.code) {
    if (localStorage.getItem('nexchat_token')) {
      router.push({ path: '/home', query: { invite: target.code } })
    } else {
      router.push({ path: `/join/${encodeURIComponent(target.code)}` })
    }
    return true
  }

  if (target.type === 'short_film' && target.filmId) {
    router.push({ path: '/short-films/watch', query: { start: target.filmId } })
    return true
  }

  if (target.type === 'story' && target.userId) {
    router.push(`/stories/view/${target.userId}`)
    return true
  }

  return false
}

export function handleShareUrl(router, url) {
  const target = parseShareTargetFromUrl(url)
  if (!target) return false
  return navigateFromShareTarget(router, target)
}

/** Call once after app mount (web hash + native launch URL). */
export async function initDeepLinks(router) {
  if (typeof window !== 'undefined' && window.location.hash) {
    const fake = `${window.location.origin}${window.location.pathname}${window.location.hash}`
    handleShareUrl(router, fake)
  }

  if (!Capacitor.isNativePlatform()) return

  try {
    const launch = await App.getLaunchUrl()
    if (launch?.url) handleShareUrl(router, launch.url)
  } catch {
    /* no cold-start URL */
  }

  App.addListener('appUrlOpen', (event) => {
    if (event?.url) handleShareUrl(router, event.url)
  })
}

export function redirectToAppHash(path, query) {
  const url = buildAppHashUrl(path, query)
  window.location.replace(url)
}
