/**
 * OneSignal Push Notifications Service
 * يعمل على تطبيق Capacitor الأصلي، وعلى الويب فقط عند HTTPS أو localhost.
 */
import { Capacitor } from '@capacitor/core'
import { getActivePinia } from 'pinia'
import api from './api'
import { useIncomingConversationCallStore } from '../stores/incomingConversationCall'
import { useMatchingStore } from '../stores/matching'
import { startIncomingCallSound } from '../utils/sounds'

const ONESIGNAL_APP_ID = import.meta.env.VITE_ONESIGNAL_APP_ID || ''
const ONESIGNAL_WEB_APP_ID = import.meta.env.VITE_ONESIGNAL_WEB_APP_ID || ONESIGNAL_APP_ID
const ONESIGNAL_WEB_PUSH_ENABLED = import.meta.env.VITE_ONESIGNAL_WEB_PUSH_ENABLED === 'true'
const ONESIGNAL_SAFARI_WEB_ID = import.meta.env.VITE_ONESIGNAL_SAFARI_WEB_ID || ''
const ONESIGNAL_NOTIFY_BUTTON_ENABLED = import.meta.env.VITE_ONESIGNAL_NOTIFY_BUTTON_ENABLED === 'true'
const STORAGE_KEY = 'nexchat_notifications'
const WEB_PUSH_UNAVAILABLE_KEY = 'nexchat_web_push_unavailable'
let initializedUserId = null
let listenersBound = false
let webSdkLoadingPromise = null
let webInitPromise = null
let webInitialized = false
let webInitFailed = false
let userClearing = false

const notificationApiOpts = { skipUnauthorizedEvent: true, skipGlobalLoader: true }
const ONESIGNAL_LOGIN_TIMEOUT_MS = 8000

function isNative() {
  return Capacitor.isNativePlatform() && typeof window.cordova !== 'undefined'
}

function isLocalhost() {
  return ['localhost', '127.0.0.1', '[::1]'].includes(window.location.hostname)
}

function isSecureWebOrigin() {
  return window.location.protocol === 'https:' || isLocalhost()
}

function isWebPushSupported() {
  return !isNative() &&
    isSecureWebOrigin() &&
    'Notification' in window &&
    'serviceWorker' in navigator &&
    'PushManager' in window
}

function isWebPushUnavailable() {
  try {
    return sessionStorage.getItem(WEB_PUSH_UNAVAILABLE_KEY) === '1'
  } catch {
    return webInitFailed
  }
}

function markWebPushUnavailable() {
  webInitFailed = true
  webInitPromise = null
  try {
    sessionStorage.setItem(WEB_PUSH_UNAVAILABLE_KEY, '1')
  } catch {}
}

function isWebPushConfigurationError(err) {
  const msg = String(err?.message || err || '').toLowerCase()
  return (
    msg.includes('not configured for web push') ||
    msg.includes('web push is not configured') ||
    (msg.includes('web push') && msg.includes('not configured'))
  )
}

function hasWebPushConfig() {
  return ONESIGNAL_WEB_PUSH_ENABLED && !!ONESIGNAL_WEB_APP_ID && !isWebPushUnavailable()
}

export function canUseNotifications() {
  return isNative() || (isWebPushSupported() && hasWebPushConfig())
}

/** True when web push was explicitly enabled in env (even if currently unavailable). */
export function isWebPushEnabledInEnv() {
  return ONESIGNAL_WEB_PUSH_ENABLED && !!ONESIGNAL_WEB_APP_ID
}

function getOneSignal() {
  return window.plugins?.OneSignal || null
}

function getWebOneSignalInitOptions() {
  const options = {
    appId: ONESIGNAL_WEB_APP_ID,
    allowLocalhostAsSecureOrigin: true,
    serviceWorkerPath: 'OneSignalSDKWorker.js',
    serviceWorkerParam: { scope: '/' },
    welcomeNotification: { disable: true },
    notifyButton: {
      enable: ONESIGNAL_NOTIFY_BUTTON_ENABLED
    }
  }
  if (ONESIGNAL_SAFARI_WEB_ID) options.safari_web_id = ONESIGNAL_SAFARI_WEB_ID
  return options
}

async function loadWebSdk() {
  window.OneSignalDeferred = window.OneSignalDeferred || []
  if (!webSdkLoadingPromise) {
    webSdkLoadingPromise = new Promise((resolve, reject) => {
      const existing = document.querySelector('script[data-onesignal-web-sdk]')
      if (existing) {
        existing.addEventListener('load', resolve, { once: true })
        existing.addEventListener('error', reject, { once: true })
        return
      }
      const script = document.createElement('script')
      script.src = 'https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js'
      script.defer = true
      script.dataset.onesignalWebSdk = 'true'
      script.onload = resolve
      script.onerror = reject
      document.head.appendChild(script)
    })
  }
  await webSdkLoadingPromise
}

async function withWebOneSignal(callback) {
  if (!isWebPushSupported() || !hasWebPushConfig()) return null
  try {
    await loadWebSdk()
  } catch (e) {
    markWebPushUnavailable()
    if (import.meta.env.DEV) console.info('OneSignal web SDK load skipped:', e?.message || e)
    return null
  }
  window.OneSignalDeferred = window.OneSignalDeferred || []
  return new Promise((resolve) => {
    window.OneSignalDeferred.push(async (OneSignal) => {
      try {
        if (!webInitPromise && !webInitialized) {
          webInitPromise = OneSignal.init(getWebOneSignalInitOptions()).then(() => {
            bindWebOneSignalListeners(OneSignal)
            webInitialized = true
          })
        }
        if (webInitPromise) await webInitPromise
        resolve(await callback(OneSignal))
      } catch (e) {
        if (/already initialized/i.test(e?.message || '')) {
          webInitialized = true
          webInitPromise = null
          try {
            resolve(await callback(OneSignal))
            return
          } catch (callbackError) {
            if (import.meta.env.DEV) console.info('OneSignal web callback skipped:', callbackError?.message || callbackError)
            resolve(null)
            return
          }
        }
        if (isWebPushConfigurationError(e)) {
          markWebPushUnavailable()
          if (import.meta.env.DEV) {
            console.info(
              'OneSignal web push is disabled: configure Web Push in OneSignal dashboard ' +
                '(Settings → Platforms → Web) or set VITE_ONESIGNAL_WEB_PUSH_ENABLED=false'
            )
          }
          resolve(null)
          return
        }
        webInitFailed = true
        webInitPromise = null
        if (import.meta.env.DEV) console.warn('OneSignal web error:', e)
        resolve(null)
      }
    })
  })
}

/**
 * تهيئة OneSignal وربط المستخدم.
 * لا تُحجِب تسجيل الدخول — استخدم promptPermission: true فقط عند طلب صريح من المستخدم.
 * @param {string} userId
 * @param {{ promptPermission?: boolean }} [options]
 * @returns {Promise<boolean>} true إذا الإشعارات مفعّلة
 */
export async function initNotifications(userId, options = {}) {
  const { promptPermission = false } = options
  if (!isNative()) {
    if (!canUseNotifications() || !userId) return false
    const result = await initWebNotifications(userId, { promptPermission })
    return result === true
  }
  if (!ONESIGNAL_APP_ID || !userId) return false

  const OneSignal = getOneSignal()
  if (!OneSignal) return false

  try {
    if (!initializedUserId) {
      OneSignal.initialize(ONESIGNAL_APP_ID)
    }
    if (initializedUserId !== String(userId)) {
      OneSignal.login(String(userId))
      initializedUserId = String(userId)
    }

    const granted = await OneSignal.Notifications.requestPermission()
    if (granted) {
      optInNotifications()
      // تشغيل التسجيل في الخلفية - الـ subscription id قد لا يكون جاهزاً فوراً
      registerWithBackend()
    }

    bindOneSignalListeners(OneSignal)

    return granted
  } catch (e) {
    console.warn('OneSignal init error:', e)
    return false
  }
}

async function linkWebOneSignalUser(OneSignal, userId) {
  const nextUserId = String(userId)
  let currentExternalId = OneSignal.User?.externalId
  if (!currentExternalId && typeof OneSignal.User?.getExternalId === 'function') {
    try {
      currentExternalId = await OneSignal.User.getExternalId()
    } catch {}
  }

  if (currentExternalId === nextUserId) {
    initializedUserId = nextUserId
    return
  }

  if (currentExternalId && currentExternalId !== nextUserId) {
    await OneSignal.logout()
  }

  if (initializedUserId !== nextUserId || !currentExternalId) {
    // 409 in Network tab is expected when userId already exists in OneSignal — do not block login.
    await Promise.race([
      OneSignal.login(nextUserId),
      new Promise((resolve) => setTimeout(resolve, ONESIGNAL_LOGIN_TIMEOUT_MS))
    ])
    initializedUserId = nextUserId
  }
}

async function initWebNotifications(userId, { promptPermission = false } = {}) {
  if (!isWebPushSupported() || !hasWebPushConfig() || !userId) return false

  return await withWebOneSignal(async (OneSignal) => {
    await linkWebOneSignalUser(OneSignal, userId)

    const syncIfGranted = async () => {
      await OneSignal.User.PushSubscription.optIn()
      await registerWebWithBackend(OneSignal)
    }

    if (Notification.permission === 'granted') {
      await syncIfGranted()
      return true
    }

    if (!promptPermission) return false

    const granted = await OneSignal.Notifications.requestPermission()
    if (granted) await syncIfGranted()
    return granted
  }) === true
}

/**
 * انتظار جاهزية subscription id - قد لا يكون متاحاً فوراً بعد requestPermission.
 * يعيد المحاولة كل ثانية حتى يصبح الـ id جاهزاً (حد أقصى 15 ثانية).
 */
async function waitForSubscriptionId(OneSignal, maxWaitMs = 15000) {
  const start = Date.now()
  while (Date.now() - start < maxWaitMs) {
    try {
      const id = await OneSignal.User.pushSubscription.getIdAsync()
      if (id) return id
    } catch {}
    await new Promise(r => setTimeout(r, 1000))
  }
  return null
}

async function registerWithBackend() {
  if (!isNative()) return
  const OneSignal = getOneSignal()
  if (!OneSignal) return
  try {
    const id = await waitForSubscriptionId(OneSignal)
    if (id) {
      await api.post('/notifications/register', { playerId: id, platform: Capacitor.getPlatform() }, notificationApiOpts)
    }
  } catch (e) {
    console.warn('Register push error:', e)
  }
}

async function registerWebWithBackend(OneSignal) {
  if (!isWebPushSupported()) return
  try {
    const id = await waitForSubscriptionId(OneSignal, 15000)
    if (id) {
      await api.post('/notifications/register', { playerId: id, platform: 'web' }, notificationApiOpts)
    }
  } catch (e) {
    if (import.meta.env.DEV) console.warn('Register web push error:', e)
  }
}

async function unregisterWebWithBackend(OneSignal) {
  if (!isWebPushSupported()) return
  if (!localStorage.getItem('nexchat_token')) return
  try {
    const id = OneSignal.User?.PushSubscription?.id
      ?? await OneSignal.User.pushSubscription.getIdAsync().catch(() => null)
    if (id) {
      await api.post('/notifications/unregister', { playerId: id, platform: 'web' }, notificationApiOpts)
    }
  } catch {
    /* token may be invalid or already removed */
  }
}

async function unregisterWithBackend() {
  if (!isNative()) return
  const OneSignal = getOneSignal()
  if (!OneSignal) return
  try {
    const id = await waitForSubscriptionId(OneSignal, 3000)
    if (id) {
      await api.post('/notifications/unregister', { playerId: id, platform: Capacitor.getPlatform() }, notificationApiOpts)
    }
  } catch {
    /* ignore */
  }
}

/**
 * إعادة محاولة التسجيل في الـ backend (للمستخدمين الجدد - يعطى فرصة ثانية عند فتح الصفحة الرئيسية)
 */
export function scheduleRegistrationRetry() {
  if (!canUseNotifications()) return
  setTimeout(() => {
    if (isNative()) {
      const OneSignal = getOneSignal()
      if (OneSignal) registerWithBackend()
      return
    }
    withWebOneSignal((OneSignal) => registerWebWithBackend(OneSignal))
  }, 4000)
}

/**
 * طلب إذن الإشعارات والتسجيل في الـ backend (يُستدعى بعد الطلب المخصص)
 */
export async function requestPermissionAndRegister() {
  if (!canUseNotifications()) return false
  if (!isNative()) {
    return await withWebOneSignal(async (OneSignal) => {
      const granted = await OneSignal.Notifications.requestPermission()
      if (!granted) return false
      await OneSignal.User.PushSubscription.optIn()
      await registerWebWithBackend(OneSignal)
      localStorage.setItem(NOTIFICATIONS_ENABLED_KEY, '1')
      return true
    }) === true
  }
  if (!isNative()) return false
  const OneSignal = getOneSignal()
  if (!OneSignal) return false
  try {
    await OneSignal.Notifications.requestPermission()
    await registerWithBackend()
    optInNotifications()
    return true
  } catch (e) {
    console.warn('Request permission error:', e)
    return false
  }
}

/**
 * إلغاء ربط المستخدم عند تسجيل الخروج
 */
export async function clearUser() {
  if (userClearing) return
  userClearing = true
  try {
    if (!isNative()) {
      await withWebOneSignal(async (OneSignal) => {
        await unregisterWebWithBackend(OneSignal)
        await OneSignal.logout()
      })
      return
    }

    const OneSignal = getOneSignal()
    if (OneSignal) {
      try {
        await unregisterWithBackend()
        OneSignal.logout()
      } catch {}
    }
  } finally {
    initializedUserId = null
    userClearing = false
  }
}

function pickField(obj, ...keys) {
  if (!obj) return undefined
  for (const k of keys) {
    const v = obj[k]
    if (v != null && v !== '') return v
  }
  return undefined
}

/** استخراج حقول التنقّل من dataJson أو payload الـ push. */
export function parseNotificationData(raw) {
  let parsed = {}
  if (typeof raw?.dataJson === 'string') {
    try {
      parsed = JSON.parse(raw.dataJson)
    } catch {
      parsed = {}
    }
  } else if (raw?.dataJson && typeof raw.dataJson === 'object') {
    parsed = raw.dataJson
  }
  const src = { ...parsed, ...raw }
  const type = pickField(src, 'type', 'Type') || raw?.type || 'message'
  return {
    type,
    conversationId: pickField(src, 'conversationId', 'ConversationId'),
    sessionId: pickField(src, 'sessionId', 'SessionId'),
    userId: pickField(src, 'userId', 'UserId'),
    messageRequestId: pickField(src, 'messageRequestId', 'MessageRequestId'),
    slideId: pickField(src, 'slideId', 'SlideId'),
    voiceOnly: pickField(src, 'voiceOnly', 'VoiceOnly'),
    callerName: pickField(src, 'callerName', 'CallerName'),
    callerAvatar: pickField(src, 'callerAvatar', 'CallerAvatar'),
    requesterId: pickField(src, 'requesterId', 'RequesterId'),
    requesterName: pickField(src, 'requesterName', 'RequesterName'),
    requesterGender: pickField(src, 'requesterGender', 'RequesterGender'),
    requesterAvatar: pickField(src, 'requesterAvatar', 'RequesterAvatar'),
    requesterIsFeatured: pickField(src, 'requesterIsFeatured', 'RequesterIsFeatured')
  }
}

/** تطبيع صف إشعار من API مركز الإشعارات. */
export function normalizeServerNotification(x) {
  const nav = parseNotificationData({ ...x, type: x.type })
  return {
    id: `srv-${x.id}`,
    serverId: x.id,
    type: x.type || nav.type,
    title: x.title,
    body: x.body,
    timestamp: x.createdAt,
    isRead: x.isRead,
    ...nav
  }
}

function buildStoreItem(data, notifMeta, isRead) {
  const nav = parseNotificationData(data)
  return {
    ...nav,
    type: nav.type || data?.type || 'message',
    title: notifMeta?.title || data?.title || 'إشعار',
    body: notifMeta?.body || data?.body || '',
    timestamp: Date.now(),
    isRead: isRead === true
  }
}

/** فتح الشاشة المناسبة حسب نوع الإشعار (مركز الإشعارات أو push). */
export function navigateFromNotification(input) {
  const d = parseNotificationData(input)
  const type = d.type || input?.type
  const router = window.__nexchat_router__
  if (!router) return

  const pinia = typeof getActivePinia === 'function' ? getActivePinia() : null

  if (type === 'code_connected') {
    if (pinia && d.requesterId) {
      const matching = useMatchingStore(pinia)
      matching.setIncomingConnectionRequest({
        requesterId: String(d.requesterId),
        requesterName: d.requesterName ?? '…',
        requesterGender: d.requesterGender,
        requesterAvatar: d.requesterAvatar,
        requesterIsFeatured: d.requesterIsFeatured === 'true' || d.requesterIsFeatured === true
      })
      startIncomingCallSound()
    }
    router.push('/home')
    return
  }

  if (type === 'story_published' && d.userId) {
    router.push(`/stories/view/${d.userId}`)
    return
  }

  if (type === 'conversation_message' && d.conversationId) {
    router.push({ path: '/conversations', query: { open: d.conversationId } })
    return
  }

  if (type === 'message_request') {
    router.push({ path: '/conversations', query: { tab: 'requests' } })
    return
  }

  if (type === 'video_call') {
    if (d.conversationId && pinia) {
      const incomingConv = useIncomingConversationCallStore(pinia)
      incomingConv.setIncoming({
        conversationId: String(d.conversationId),
        voiceOnly: d.voiceOnly === 'true' || d.voiceOnly === true,
        callerName: d.callerName ?? '',
        callerAvatar: d.callerAvatar ?? null
      })
      startIncomingCallSound()
      router.push('/home')
      return
    }
    if (d.sessionId) {
      router.push({ path: `/chat/${d.sessionId}`, query: { incomingVideoCall: '1' } })
      return
    }
  }

  if (d.sessionId) {
    router.push(`/chat/${d.sessionId}`)
  }
}

/**
 * إضافة إشعار للمخزن المحلي (لصفحة الإشعارات)
 */
export function addToStore(notification) {
  try {
    const list = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]')
    list.unshift({
      ...notification,
      id: notification.id || Date.now().toString(),
      isRead: notification.isRead === true ? true : false
    })
    if (list.length > 100) list.length = 100
    localStorage.setItem(STORAGE_KEY, JSON.stringify(list))
    window.dispatchEvent(new CustomEvent('nexchat:notification', { detail: list[0] }))
  } catch {}
}

/**
 * جلب قائمة الإشعارات من المخزن المحلي
 */
export function getStoredNotifications() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]')
  } catch {
    return []
  }
}

/**
 * مسح الإشعارات المحفوظة
 */
export function clearStoredNotifications() {
  localStorage.removeItem(STORAGE_KEY)
}

export function markNotificationRead(id) {
  try {
    const list = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]')
    const idx = list.findIndex(x => String(x.id) === String(id))
    if (idx >= 0 && !list[idx].isRead) {
      list[idx].isRead = true
      localStorage.setItem(STORAGE_KEY, JSON.stringify(list))
    }
  } catch {}
}

export function markAllNotificationsRead() {
  try {
    const list = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]').map(x => ({ ...x, isRead: true }))
    localStorage.setItem(STORAGE_KEY, JSON.stringify(list))
  } catch {}
}

const NOTIFICATIONS_ENABLED_KEY = 'nexchat_notifications_enabled'

/**
 * تفعيل الإشعارات
 */
export function optInNotifications() {
  if (!isNative()) {
    withWebOneSignal(async (OneSignal) => {
      await OneSignal.User.PushSubscription.optIn()
      await registerWebWithBackend(OneSignal)
      localStorage.setItem(NOTIFICATIONS_ENABLED_KEY, '1')
    })
    return
  }
  if (!isNative()) return
  const OneSignal = getOneSignal()
  if (OneSignal) {
    try {
      OneSignal.User.pushSubscription.optIn()
      localStorage.setItem(NOTIFICATIONS_ENABLED_KEY, '1')
    } catch {}
  }
}

/**
 * إلغاء تفعيل الإشعارات
 */
export function optOutNotifications() {
  if (!isNative()) {
    withWebOneSignal(async (OneSignal) => {
      await unregisterWebWithBackend(OneSignal)
      await OneSignal.User.PushSubscription.optOut()
      localStorage.setItem(NOTIFICATIONS_ENABLED_KEY, '0')
    })
    return
  }
  if (!isNative()) return
  const OneSignal = getOneSignal()
  if (OneSignal) {
    try {
      OneSignal.User.pushSubscription.optOut()
      localStorage.setItem(NOTIFICATIONS_ENABLED_KEY, '0')
    } catch {}
  }
}

/**
 * التحقق من حالة تفعيل الإشعارات
 */
export async function getNotificationsEnabled() {
  if (!isNative()) {
    if (!canUseNotifications()) return false
    const enabled = await withWebOneSignal(async (OneSignal) => {
      return OneSignal.Notifications.permission &&
        OneSignal.User.PushSubscription.optedIn !== false
    })
    return enabled === true
  }
  if (!isNative()) return false
  const OneSignal = getOneSignal()
  if (!OneSignal) return false
  try {
    return await OneSignal.User.pushSubscription.getOptedInAsync()
  } catch {
    return localStorage.getItem(NOTIFICATIONS_ENABLED_KEY) !== '0'
  }
}

function bindWebOneSignalListeners(OneSignal) {
  if (listenersBound) return
  listenersBound = true

  OneSignal.Notifications.addEventListener('click', (event) => {
    const notif = event?.notification
    const data = notif?.additionalData || {}
    const item = buildStoreItem(data, { title: notif?.title, body: notif?.body }, true)
    addToStore(item)
    navigateFromNotification(item)
  })

  OneSignal.Notifications.addEventListener('foregroundWillDisplay', (event) => {
    const notif = event?.notification
    const data = notif?.additionalData || {}
    addToStore(buildStoreItem(data, { title: notif?.title, body: notif?.body }, false))
  })
}

function bindOneSignalListeners(OneSignal) {
  if (listenersBound) return
  listenersBound = true

  OneSignal.Notifications.addEventListener('click', (event) => {
    const notif = event?.notification
    const payload = notif?.rawPayload || {}
    const data = notif?.additionalData || payload?.custom?.a || payload?.custom || {}
    const item = buildStoreItem(data, { title: notif?.title, body: notif?.body }, true)
    addToStore(item)
    navigateFromNotification(item)
  })

  OneSignal.Notifications.addEventListener('foregroundWillDisplay', (event) => {
    const notif = event?.notification
    const payload = notif?.rawPayload || {}
    const data = notif?.additionalData || payload?.custom?.a || payload?.custom || {}
    addToStore(buildStoreItem(data, { title: notif?.title, body: notif?.body }, false))
    try { event?.preventDefault?.() } catch {}
  })
}
