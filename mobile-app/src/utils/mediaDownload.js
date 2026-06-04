import { ensureAbsoluteUrl } from './imageUrl'
import { parseAlbumMessage } from './conversationAlbum'

const CRC_TABLE = (() => {
  const table = new Uint32Array(256)
  for (let i = 0; i < 256; i++) {
    let c = i
    for (let j = 0; j < 8; j++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1)
    table[i] = c >>> 0
  }
  return table
})()

function crc32(bytes) {
  let c = 0xffffffff
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

function authHeaders() {
  const token = localStorage.getItem('nexchat_token')
  return token ? { Authorization: `Bearer ${token}` } : {}
}

function filenameFromUrl(url, fallback = 'download') {
  try {
    const path = new URL(url).pathname
    const base = path.split('/').pop() || fallback
    return base.includes('.') ? base : fallback
  } catch {
    return fallback
  }
}

function extForKind(kind, url) {
  const fromUrl = filenameFromUrl(url, '').split('.').pop()
  if (fromUrl && fromUrl.length <= 5) return fromUrl
  if (kind === 'video') return 'mp4'
  if (kind === 'audio') return 'webm'
  return 'jpg'
}

function sanitizeZipName(name) {
  return String(name).replace(/[^\w.\-]+/g, '_').slice(0, 80) || 'file'
}

export async function fetchMediaBlob(url) {
  const absolute = ensureAbsoluteUrl(url)
  const res = await fetch(absolute, {
    headers: authHeaders(),
    credentials: 'include'
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.blob()
}

async function saveBlob(blob, filename) {
  const name = filename || 'download'
  const type = blob.type || 'application/octet-stream'
  const file = blob instanceof File ? blob : new File([blob], name, { type })

  if (typeof navigator.share === 'function' && typeof navigator.canShare === 'function') {
    try {
      if (navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file], title: name })
        return
      }
    } catch (err) {
      if (err?.name === 'AbortError') return
    }
  }

  const objectUrl = URL.createObjectURL(blob)
  try {
    const anchor = document.createElement('a')
    anchor.href = objectUrl
    anchor.download = name
    anchor.rel = 'noopener'
    anchor.style.display = 'none'
    document.body.appendChild(anchor)
    anchor.click()
    anchor.remove()
  } finally {
    setTimeout(() => URL.revokeObjectURL(objectUrl), 3000)
  }
}

async function buildZipBlob(entries) {
  const enc = new TextEncoder()
  const chunks = []
  const central = []
  let offset = 0

  for (const { name, blob } of entries) {
    const nameBytes = enc.encode(sanitizeZipName(name))
    const data = new Uint8Array(await blob.arrayBuffer())
    const crc = crc32(data)
    const size = data.length

    const local = new Uint8Array(30 + nameBytes.length + size)
    const lv = new DataView(local.buffer)
    lv.setUint32(0, 0x04034b50, true)
    lv.setUint16(4, 20, true)
    lv.setUint16(8, 0, true)
    lv.setUint32(14, crc, true)
    lv.setUint32(18, size, true)
    lv.setUint32(22, size, true)
    lv.setUint16(26, nameBytes.length, true)
    local.set(nameBytes, 30)
    local.set(data, 30 + nameBytes.length)
    chunks.push(local)

    const cd = new Uint8Array(46 + nameBytes.length)
    const cv = new DataView(cd.buffer)
    cv.setUint32(0, 0x02014b50, true)
    cv.setUint16(4, 20, true)
    cv.setUint16(6, 20, true)
    cv.setUint32(16, crc, true)
    cv.setUint32(20, size, true)
    cv.setUint32(24, size, true)
    cv.setUint16(28, nameBytes.length, true)
    cv.setUint32(42, offset, true)
    cd.set(nameBytes, 46)
    central.push(cd)
    offset += local.length
  }

  const centralSize = central.reduce((s, c) => s + c.length, 0)
  const centralBuf = new Uint8Array(centralSize)
  let pos = 0
  for (const c of central) {
    centralBuf.set(c, pos)
    pos += c.length
  }
  chunks.push(centralBuf)

  const end = new Uint8Array(22)
  const ev = new DataView(end.buffer)
  ev.setUint32(0, 0x06054b50, true)
  ev.setUint16(8, entries.length, true)
  ev.setUint16(10, entries.length, true)
  ev.setUint32(12, centralSize, true)
  ev.setUint32(16, offset, true)
  chunks.push(end)

  return new Blob(chunks, { type: 'application/zip' })
}

async function saveAlbumEntries(entries, zipFilename = 'album.zip') {
  if (!entries.length) throw new Error('empty')

  if (entries.length === 1) {
    await saveBlob(entries[0].blob, entries[0].name)
    return
  }

  const files = entries.map(
    (e) => new File([e.blob], e.name, { type: e.blob.type || 'image/jpeg' })
  )

  if (typeof navigator.share === 'function' && typeof navigator.canShare === 'function') {
    try {
      if (navigator.canShare({ files })) {
        await navigator.share({ files, title: zipFilename.replace(/\.zip$/i, '') })
        return
      }
    } catch (err) {
      if (err?.name === 'AbortError') return
    }
  }

  const zipBlob = await buildZipBlob(entries)
  await saveBlob(zipBlob, zipFilename)
}

export async function downloadMediaUrl(url, options = {}) {
  const { filename, kind } = options
  const absolute = ensureAbsoluteUrl(url)
  const blob = await fetchMediaBlob(absolute)
  const name = filename || filenameFromUrl(absolute, kind ? `file.${extForKind(kind, absolute)}` : 'download')
  await saveBlob(blob, name)
}

/** Download multiple images as one ZIP (or multi-file share on supported devices). */
export async function downloadAlbumImages(urls, options = {}) {
  const list = (urls || []).filter(Boolean).map((u) => ensureAbsoluteUrl(String(u)))
  if (!list.length) throw new Error('empty')

  const entries = await Promise.all(
    list.map(async (url, i) => {
      const blob = await fetchMediaBlob(url)
      const ext = extForKind('image', url)
      const fromUrl = filenameFromUrl(url, '')
      const name = fromUrl.includes('.') ? fromUrl : `photo-${i + 1}.${ext}`
      return { name: sanitizeZipName(name), blob }
    })
  )

  const zipName = options.zipName || `album-${new Date().toISOString().slice(0, 10)}.zip`
  await saveAlbumEntries(entries, zipName)
}

/** @deprecated Use downloadAlbumImages */
export async function downloadMediaUrls(urls, options = {}) {
  return downloadAlbumImages(urls, options)
}

/** Returns download spec for conversation message types, or null. */
export function getMessageDownloadSpec(msg) {
  if (!msg || msg.deletedForEveryone) return null
  const type = msg.type ?? msg.Type ?? 'text'
  const content = msg.content ?? msg.Content ?? ''

  if (type === 'image' || type === 'video' || type === 'audio') {
    if (!content || content.startsWith('blob:')) return null
    return { kind: type, urls: [content] }
  }

  if (type === 'album') {
    const album = parseAlbumMessage(content)
    if (!album?.urls?.length) return null
    return { kind: 'album', urls: album.urls }
  }

  return null
}

export function canDownloadMessage(msg) {
  return getMessageDownloadSpec(msg) != null
}

export async function downloadMessageMedia(msg) {
  const spec = getMessageDownloadSpec(msg)
  if (!spec) throw new Error('not downloadable')
  if (spec.urls.length === 1) {
    await downloadMediaUrl(spec.urls[0], { kind: spec.kind })
    return
  }
  if (spec.kind === 'album') {
    await downloadAlbumImages(spec.urls)
    return
  }
  await downloadAlbumImages(spec.urls, { zipName: `${spec.kind}.zip` })
}
