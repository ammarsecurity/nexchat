/**
 * فحص تحديث التطبيق - يقارن إصدار التطبيق الحالي مع الحد الأدنى المطلوب من السيرفر
 */

const API_BASE = import.meta.env.VITE_API_URL?.replace(/\/api\/?$/, '') || 'http://localhost:5000'
const UPDATE_POLL_MS = 90_000

function isValidDownloadUrl(url) {
  if (!url || typeof url !== 'string') return false
  const trimmed = url.trim()
  return trimmed !== '#' && /^https?:\/\//i.test(trimmed)
}

/**
 * مقارنة إصدارين (مثل "1.0" و "1.1")
 * @returns -1 إذا current < required، 0 إذا متساويان، 1 إذا current > required
 */
function compareVersions(current, required) {
  const parse = (v) => (v || '0').split('.').map((n) => parseInt(n, 10) || 0)
  const a = parse(current)
  const b = parse(required)
  const len = Math.max(a.length, b.length)
  for (let i = 0; i < len; i++) {
    const x = a[i] || 0
    const y = b[i] || 0
    if (x < y) return -1
    if (x > y) return 1
  }
  return 0
}

/**
 * فحص إذا كان التحديث مطلوباً (إصدار التطبيق أقل من minVersion في لوحة الإدارة)
 * @returns { Promise<{ required: boolean, downloadUrl?: string, currentVersion?: string, minVersion?: string }> }
 */
export async function checkUpdateRequired() {
  try {
    const result = await fetchUpdateInfo()
    if (!result) return { required: false }
    const { currentVersion, minVersion, downloadUrl, required } = result
    return {
      required: required === true,
      downloadUrl: isValidDownloadUrl(downloadUrl) ? downloadUrl : undefined,
      currentVersion,
      minVersion
    }
  } catch {
    return { required: false }
  }
}

/**
 * جلب معلومات التحديث (للإعدادات)
 * @returns { Promise<{ hasUpdate: boolean, required: boolean, downloadUrl?: string, currentVersion: string, latestVersion?: string, minVersion?: string } | null> }
 */
export async function fetchUpdateInfo() {
  try {
    let currentVersion = typeof __APP_VERSION__ !== 'undefined' ? __APP_VERSION__ : '1.0.3'
    const { Capacitor } = await import('@capacitor/core')
    const { App } = await import('@capacitor/app')

    if (Capacitor.isNativePlatform() && App?.getInfo) {
      const info = await App.getInfo()
      currentVersion = info.version || info.appVersion || currentVersion
    }

    const res = await fetch(`${API_BASE}/api/SiteContent/app_update`, {
      cache: 'no-store',
      headers: { 'Cache-Control': 'no-cache' }
    })
    if (!res.ok) return null

    const data = await res.json()
    const content = data.content || data.Content || ''
    if (!content) return null

    const config = JSON.parse(content)
    const minVersion = config.minVersion || config.min_version || '1.0'
    const latestVersion = config.latestVersion || config.latest_version || minVersion

    let platform = 'web'
    if (Capacitor.isNativePlatform()) {
      platform = Capacitor.getPlatform() || 'web'
    }
    const androidUrl = (config.downloadUrl || config.download_url || '').trim()
    const iosUrl = (config.iosDownloadUrl || config.ios_download_url || '').trim()
    let downloadUrl = platform === 'ios' ? iosUrl : (platform === 'android' ? androidUrl : '')
    if (!isValidDownloadUrl(downloadUrl)) {
      downloadUrl = isValidDownloadUrl(androidUrl) ? androidUrl : (isValidDownloadUrl(iosUrl) ? iosUrl : '')
    }

    const cmpMin = compareVersions(currentVersion, minVersion)
    const cmpLatest = compareVersions(currentVersion, latestVersion)
    const hasUpdate = cmpMin < 0 || cmpLatest < 0

    return {
      hasUpdate,
      required: cmpMin < 0,
      downloadUrl: isValidDownloadUrl(downloadUrl) ? downloadUrl : undefined,
      currentVersion,
      latestVersion,
      minVersion
    }
  } catch {
    return null
  }
}

/**
 * فحص دوري + عند العودة للتطبيق (للتقاط تغيير minVersion من الإدارة أثناء الاستخدام)
 * @param {(result: Awaited<ReturnType<typeof checkUpdateRequired>>) => void} onResult
 */
export function startAppUpdateWatcher(onResult) {
  let timer = null
  let running = false

  async function tick() {
    if (running) return
    running = true
    try {
      onResult(await checkUpdateRequired())
    } finally {
      running = false
    }
  }

  function onVisibility() {
    if (typeof document !== 'undefined' && document.visibilityState === 'visible') {
      void tick()
    }
  }

  return {
    tick,
    start() {
      void tick()
      timer = setInterval(() => { void tick() }, UPDATE_POLL_MS)
      if (typeof document !== 'undefined') {
        document.addEventListener('visibilitychange', onVisibility)
      }
    },
    stop() {
      if (timer) {
        clearInterval(timer)
        timer = null
      }
      if (typeof document !== 'undefined') {
        document.removeEventListener('visibilitychange', onVisibility)
      }
    }
  }
}
