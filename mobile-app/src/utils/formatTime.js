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
