/**
 * فحص تحديث التطبيق - يقارن إصدار التطبيق الحالي مع الحد الأدنى المطلوب من السيرفر
 */

const API_BASE = import.meta.env.VITE_API_URL?.replace(/\/api\/?$/, '') || 'http://localhost:5000'

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
 * فحص إذا كان التحديث مطلوباً
 * @returns { Promise<{ required: boolean, downloadUrl?: string }> }
 */
export async function checkUpdateRequired() {
  try {
    const result = await fetchUpdateInfo()
    if (!result) return { required: false }
    const { currentVersion, minVersion, downloadUrl } = result
    if (!downloadUrl) return { required: false }
    const cmp = compareVersions(currentVersion, minVersion)
    return { required: cmp < 0, downloadUrl }
  } catch {
    return { required: false }
  }
}

/**
 * جلب معلومات التحديث (للإعدادات)
 * @returns { Promise<{ hasUpdate: boolean, required: boolean, downloadUrl?: string, currentVersion: string, latestVersion?: string } | null> }
 */
export async function fetchUpdateInfo() {
  try {
    let currentVersion = '1.0.2'
    const { Capacitor } = await import('@capacitor/core')
    const { App } = await import('@capacitor/app')

    if (Capacitor.isNativePlatform() && App?.getInfo) {
      const info = await App.getInfo()
      currentVersion = info.version || info.appVersion || '1.0.2'
    }

    const res = await fetch(`${API_BASE}/api/SiteContent/app_update`)
    if (!res.ok) return null

    const data = await res.json()
    const content = data.content || data.Content || ''
    if (!content) return null

    const config = JSON.parse(content)
    const minVersion = config.minVersion || config.min_version || '1.0'
    const latestVersion = config.latestVersion || config.latest_version || minVersion
    const downloadUrl = config.downloadUrl || config.download_url || ''

    const cmpMin = compareVersions(currentVersion, minVersion)
    const cmpLatest = compareVersions(currentVersion, latestVersion)
    const hasUpdate = cmpMin < 0 || cmpLatest < 0

    return {
      hasUpdate,
      required: cmpMin < 0,
      downloadUrl: downloadUrl || undefined,
      currentVersion,
      latestVersion
    }
  } catch {
    return null
  }
}
