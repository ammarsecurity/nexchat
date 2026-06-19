import api from '../services/api'
import { resolveDefaultAppRoute, getCodeConnectFeaturesEnabled } from '../services/siteContentFlags'
import { normalizeInviteCode } from './shareLinks'

/**
 * Post-login / post-register navigation respecting feature flags.
 */
export async function navigateAfterAuth(router, { inviteCode, needsProfile } = {}) {
  if (needsProfile) {
    router.replace('/complete-profile')
    return
  }
  const code = normalizeInviteCode(inviteCode)
  if (code && await getCodeConnectFeaturesEnabled(api)) {
    router.replace({ path: '/home', query: { invite: code } })
    return
  }
  sessionStorage.removeItem('nexchat_pending_invite')
  router.replace(await resolveDefaultAppRoute(api))
}

/** Splash / onboarding exit for logged-in users. */
export async function navigateDefaultForSession(router, isLoggedIn) {
  if (!isLoggedIn) {
    router.replace('/login')
    return
  }
  router.replace(await resolveDefaultAppRoute(api))
}
