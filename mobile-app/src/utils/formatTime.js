/**
 * تنسيق الوقت بنظام 12 ساعة (AM/PM) — توقيت العراق UTC+3
 */
const IRAQ_TZ = 'Asia/Baghdad'

export function formatTime12(date, locale = 'ar') {
  const d = date instanceof Date ? date : new Date(date)
  return d.toLocaleTimeString(locale === 'ar' ? 'ar-IQ' : 'en-US', {
    timeZone: IRAQ_TZ,
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
  })
}

/**
 * تاريخ + وقت بالتقويم الميلادي — توقيت العراق UTC+3
 */
export function formatGregorianDateTime(date, locale = 'ar') {
  const d = date instanceof Date ? date : new Date(date)
  const tag = locale === 'ar' ? 'ar-IQ' : 'en-US'
  const dateOpts =
    locale === 'ar'
      ? { timeZone: IRAQ_TZ, calendar: 'gregory', year: 'numeric', month: 'numeric', day: 'numeric' }
      : { timeZone: IRAQ_TZ, year: 'numeric', month: 'numeric', day: 'numeric' }
  const timeOpts = { timeZone: IRAQ_TZ, hour: '2-digit', minute: '2-digit', hour12: true }
  const dateStr = new Intl.DateTimeFormat(tag, dateOpts).format(d)
  const timeStr = new Intl.DateTimeFormat(tag, timeOpts).format(d)
  return `${dateStr} ${timeStr}`
}
