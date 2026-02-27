const API_ORIGIN = (() => {
  const base = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'
  return base.replace(/\/api\/?$/, '')
})()

const BAD_HOSTS = /^(localhost|127\.0\.0\.1|0\.0\.0\.0|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)/i

/**
 * يحول الروابط النسبية إلى مطلقة ويصلح الروابط الخاطئة من السيرفر.
 * ضروري على Android (Capacitor) لأن:
 * 1. الصفحة تُحمّل من capacitor://localhost والروابط النسبية لا تعمل
 * 2. السيرفر خلف proxy قد يرجّع روابط مثل http://localhost:4567/uploads/xxx
 */
export function ensureAbsoluteUrl(url) {
  if (!url || typeof url !== 'string') return url
  let path = url
  if (url.startsWith('http://') || url.startsWith('https://')) {
    try {
      const u = new URL(url)
      if (BAD_HOSTS.test(u.hostname) || u.port === '4567' || u.port === '5000') {
        path = u.pathname + u.search
      } else {
        return url
      }
    } catch {
      return url
    }
  } else if (!url.startsWith('/')) {
    path = '/' + url
  }
  return `${API_ORIGIN}${path.startsWith('/') ? path : '/' + path}`
}
