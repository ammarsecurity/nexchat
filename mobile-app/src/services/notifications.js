/**
 * OneSignal Push Notifications Service
 * يعمل فقط على المنصة الأصلية (Capacitor)
 */
import { Capacitor } from '@capacitor/core'
import api from './api'

const ONESIGNAL_APP_ID = import.meta.env.VITE_ONESIGNAL_APP_ID || ''
const STORAGE_KEY = 'nexchat_notifications'

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
    OneSignal.initialize(ONESIGNAL_APP_ID)
    OneSignal.login(String(userId))

    const granted = await OneSignal.Notifications.requestPermission()
    if (granted) {
      optInNotifications()
      await registerWithBackend()
    }

    // عند الضغط على الإشعار
    OneSignal.Notifications.addEventListener('click', (event) => {
      const notif = event?.notification
      const payload = notif?.rawPayload || {}
      const data = notif?.additionalData || payload?.custom?.a || payload?.custom || {}
      addToStore({
        type: data.type || 'message',
        title: notif?.title || 'إشعار',
        body: notif?.body || '',
        sessionId: data.sessionId,
        timestamp: Date.now()
      })
      handleNotificationClick(data)
    })

    return granted
  } catch (e) {
    console.warn('OneSignal init error:', e)
    return false
  }
}

async function registerWithBackend() {
  if (!isNative()) return
  const OneSignal = getOneSignal()
  if (!OneSignal) return
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const id = await OneSignal.User.pushSubscription.getIdAsync()
      if (id) {
        await api.post('/notifications/register', { playerId: id, platform: Capacitor.getPlatform() })
        return
      }
    } catch (e) {
      console.warn('Register push error:', e)
    }
    await new Promise(r => setTimeout(r, 500 * (attempt + 1)))
  }
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
      OneSignal.logout()
    } catch {}
  }
}

function handleNotificationClick(data) {
  const router = window.__nexchat_router__
  if (!router) return

  if (data?.type === 'code_connected') {
    router.push('/home')
    return
  }

  if (!data?.sessionId) return

  if (data.type === 'video_call') {
    router.push(`/video/${data.sessionId}`)
  } else {
    router.push(`/chat/${data.sessionId}`)
  }
}

/**
 * إضافة إشعار للمخزن المحلي (لصفحة الإشعارات)
 */
export function addToStore(notification) {
  try {
    const list = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]')
    list.unshift({ ...notification, id: Date.now().toString() })
    if (list.length > 100) list.length = 100
    localStorage.setItem(STORAGE_KEY, JSON.stringify(list))
    window.dispatchEvent(new CustomEvent('nexchat:notification', { detail: notification }))
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
