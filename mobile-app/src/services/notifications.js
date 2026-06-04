/**
 * OneSignal Push Notifications Service
 * يعمل فقط على المنصة الأصلية (Capacitor)
 */
import { Capacitor } from '@capacitor/core'
import { getActivePinia } from 'pinia'
import api from './api'
import { useIncomingConversationCallStore } from '../stores/incomingConversationCall'
import { useMatchingStore } from '../stores/matching'
import { startIncomingCallSound } from '../utils/sounds'

const ONESIGNAL_APP_ID = import.meta.env.VITE_ONESIGNAL_APP_ID || ''
const STORAGE_KEY = 'nexchat_notifications'
let initializedUserId = null
let listenersBound = false

function isNative() {
  return Capacitor.isNativePlatform() && typeof window.cordova !== 'undefined'
}

function getOneSignal() {
  return window.plugins?.OneSignal || null
}

/**
 * تهيئة OneSignal وربط المستخدم
 * يطلب الإذن فوراً ويشترك تلقائياً لضمان وصول الإشعارات.
 * @param {string} userId
 * @returns {Promise<boolean>} true إذا تم منح الإذن
 */
export async function initNotifications(userId) {
  if (!isNative() || !ONESIGNAL_APP_ID || !userId) return false

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
      await api.post('/notifications/register', { playerId: id, platform: Capacitor.getPlatform() })
    }
  } catch (e) {
    console.warn('Register push error:', e)
  }
}

async function unregisterWithBackend() {
  if (!isNative()) return
  const OneSignal = getOneSignal()
  if (!OneSignal) return
  try {
    const id = await waitForSubscriptionId(OneSignal, 3000)
    if (id) await api.post('/notifications/unregister', { playerId: id, platform: Capacitor.getPlatform() })
  } catch (e) {
    console.warn('Unregister push error:', e)
  }
}

/**
 * إعادة محاولة التسجيل في الـ backend (للمستخدمين الجدد - يعطى فرصة ثانية عند فتح الصفحة الرئيسية)
 */
export function scheduleRegistrationRetry() {
  if (!isNative()) return
  setTimeout(() => {
    const OneSignal = getOneSignal()
    if (OneSignal) registerWithBackend()
  }, 4000)
}

/**
 * طلب إذن الإشعارات والتسجيل في الـ backend (يُستدعى بعد الطلب المخصص)
 */
export async function requestPermissionAndRegister() {
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
export function clearUser() {
  if (!isNative()) return

  const OneSignal = getOneSignal()
  if (OneSignal) {
    try {
      unregisterWithBackend()
      OneSignal.logout()
    } catch {}
  }
  initializedUserId = null
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
  if (!isNative()) return false
  const OneSignal = getOneSignal()
  if (!OneSignal) return false
  try {
    return await OneSignal.User.pushSubscription.getOptedInAsync()
  } catch {
    return localStorage.getItem(NOTIFICATIONS_ENABLED_KEY) !== '0'
  }
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
