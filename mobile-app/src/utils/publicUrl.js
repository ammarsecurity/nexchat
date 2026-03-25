/**
 * Public folder URLs for Vite dev, web deploy, and Electron (file:// with base ./).
 * Avoid hardcoded "/foo" — that resolves to the filesystem root under file://.
 */
export function publicUrl(path) {
  const base = import.meta.env.BASE_URL || '/'
  const p = path.startsWith('/') ? path.slice(1) : path
  return base.endsWith('/') ? `${base}${p}` : `${base}/${p}`
}
