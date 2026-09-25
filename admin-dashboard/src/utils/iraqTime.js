/** Asia/Baghdad (UTC+3, no DST) — display-only; API stores UTC. */

export const IRAQ_TZ = 'Asia/Baghdad'

export function formatIraqDateTime(dt, opts = {}) {
  if (!dt) return '-'
  const d = dt instanceof Date ? dt : new Date(dt)
  if (Number.isNaN(d.getTime())) return '-'
  return d.toLocaleString('ar-IQ', {
    timeZone: IRAQ_TZ,
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    ...opts,
  })
}

export function formatIraqDate(dt) {
  if (!dt) return '-'
  const d = dt instanceof Date ? dt : new Date(dt)
  if (Number.isNaN(d.getTime())) return '-'
  return d.toLocaleDateString('ar-IQ', {
    timeZone: IRAQ_TZ,
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

export function formatIraqTime(dt) {
  return formatIraqDateTime(dt)
}
