/**
 * تنسيق الوقت بنظام 12 ساعة (AM/PM)
 * @param {Date|string|number} date - التاريخ أو الطابع الزمني
 * @param {string} locale - اللغة (ar أو en)
 * @returns {string}
 */
export function formatTime12(date, locale = 'ar') {
  const d = date instanceof Date ? date : new Date(date)
  return d.toLocaleTimeString(locale === 'ar' ? 'ar-SA' : 'en-US', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: true
  })
}

/**
 * تاريخ + وقت بالتقويم الميلادي (ar-SA الافتراضي يعرض هجرياً بدون calendar: 'gregory')
 */
export function formatGregorianDateTime(date, locale = 'ar') {
  const d = date instanceof Date ? date : new Date(date)
  const tag = locale === 'ar' ? 'ar-SA' : 'en-US'
  const dateOpts =
    locale === 'ar'
      ? { calendar: 'gregory', year: 'numeric', month: 'numeric', day: 'numeric' }
      : { year: 'numeric', month: 'numeric', day: 'numeric' }
  const timeOpts = { hour: '2-digit', minute: '2-digit', hour12: true }
  const dateStr = new Intl.DateTimeFormat(tag, dateOpts).format(d)
  const timeStr = new Intl.DateTimeFormat(tag, timeOpts).format(d)
  return `${dateStr} ${timeStr}`
}
