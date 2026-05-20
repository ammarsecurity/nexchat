/**
 * Short films offline cache — IndexedDB blobs + background download queue.
 */

import { getDb } from './cache'
import { ensureAbsoluteUrl } from '../utils/imageUrl'

export const MAX_CACHE_BYTES = 300 * 1024 * 1024
export const MAX_CONCURRENT_DOWNLOADS = 2
export const PREFETCH_AHEAD = 3

const PRIORITY = { high: 0, normal: 1, low: 2 }

/** @type {Map<string, string>} filmId+kind -> blob object URL */
const objectUrlRegistry = new Map()

/** @type {Map<string, 'idle'|'downloading'|'done'|'failed'>} */
const downloadState = new Map()

const queue = []
let activeDownloads = 0
const cacheListeners = new Set()

export function onShortFilmCacheUpdate(listener) {
  cacheListeners.add(listener)
  return () => cacheListeners.delete(listener)
}

function notifyCacheUpdate(filmId, kind) {
  for (const fn of cacheListeners) {
    try {
      fn(filmId, kind)
    } catch {}
  }
}

function stateKey(filmId, kind) {
  return `${filmId}:${kind}`
}

function filmKey(film) {
  return String(film?.id ?? film?.Id ?? '')
}

function touchAccess(filmId) {
  const now = Date.now()
  return getDb()
    .shortFilmsMeta.update(filmId, { lastAccessAt: now })
    .catch(() => {})
}

export function revokeObjectUrl(url) {
  if (!url || !url.startsWith('blob:')) return
  try {
    URL.revokeObjectURL(url)
  } catch {}
  for (const [key, registered] of objectUrlRegistry.entries()) {
    if (registered === url) objectUrlRegistry.delete(key)
  }
}

export function revokeAllObjectUrls() {
  for (const url of objectUrlRegistry.values()) {
    try {
      URL.revokeObjectURL(url)
    } catch {}
  }
  objectUrlRegistry.clear()
}

async function getTotalCachedBytes() {
  try {
    const rows = await getDb().shortFilmBlobs.toArray()
    return rows.reduce((sum, r) => sum + (r.sizeBytes || 0), 0)
  } catch {
    return 0
  }
}

async function evictIfNeeded(requiredBytes = 0) {
  try {
    let total = await getTotalCachedBytes()
    if (total + requiredBytes <= MAX_CACHE_BYTES) return

    const blobs = await getDb().shortFilmBlobs.orderBy('lastAccessAt').toArray()
    for (const row of blobs) {
      if (total + requiredBytes <= MAX_CACHE_BYTES) break
      const sk = stateKey(row.filmId, row.kind)
      const regUrl = objectUrlRegistry.get(sk)
      if (regUrl) revokeObjectUrl(regUrl)
      await getDb().shortFilmBlobs.delete([row.filmId, row.kind])
      downloadState.set(sk, 'idle')
      total -= row.sizeBytes || 0
    }
  } catch {
    // IndexedDB disabled
  }
}

async function registerBlobUrl(filmId, kind, blob) {
  const sk = stateKey(filmId, kind)
  const prev = objectUrlRegistry.get(sk)
  if (prev) revokeObjectUrl(prev)
  const url = URL.createObjectURL(blob)
  objectUrlRegistry.set(sk, url)
  return url
}

async function readBlobUrl(filmId, kind) {
  const sk = stateKey(filmId, kind)
  const existing = objectUrlRegistry.get(sk)
  if (existing) {
    await touchAccess(filmId)
    return existing
  }
  try {
    const row = await getDb().shortFilmBlobs.get([filmId, kind])
    if (!row?.blob) return null
    return registerBlobUrl(filmId, kind, row.blob)
  } catch {
    return null
  }
}

export async function getCachedVideoUrl(filmId) {
  if (!filmId) return null
  return readBlobUrl(String(filmId), 'video')
}

export async function getCachedThumbUrl(filmId) {
  if (!filmId) return null
  return readBlobUrl(String(filmId), 'thumb')
}

export async function saveFilmsMetadata(films) {
  if (!Array.isArray(films) || !films.length) return
  const now = Date.now()
  try {
    const records = films
      .filter((f) => filmKey(f))
      .map((f) => ({
        filmId: filmKey(f),
        videoUrl: f.videoUrl ?? f.VideoUrl ?? null,
        thumbnailUrl: f.thumbnailUrl ?? f.ThumbnailUrl ?? null,
        title: f.title ?? f.Title ?? '',
        sizeBytes: 0,
        cachedAt: now,
        lastAccessAt: now
      }))
    await getDb().shortFilmsMeta.bulkPut(records)
  } catch {
    // IndexedDB disabled
  }
}

async function persistBlob(filmId, kind, blob) {
  const sizeBytes = blob.size || 0
  await evictIfNeeded(sizeBytes)
  const total = await getTotalCachedBytes()
  if (total + sizeBytes > MAX_CACHE_BYTES) return false

  const now = Date.now()
  await getDb().shortFilmBlobs.put({
    filmId,
    kind,
    blob,
    sizeBytes,
    cachedAt: now,
    lastAccessAt: now
  })
  await getDb().shortFilmsMeta.update(filmId, { lastAccessAt: now }).catch(() => {})
  notifyCacheUpdate(filmId, kind)
  return true
}

async function fetchBlob(url) {
  const absolute = ensureAbsoluteUrl(url)
  if (!absolute) throw new Error('missing url')
  const token = localStorage.getItem('nexchat_token')
  const headers = {}
  if (token) headers.Authorization = `Bearer ${token}`
  const res = await fetch(absolute, { headers })
  if (!res.ok) throw new Error(`fetch ${res.status}`)
  return res.blob()
}

async function downloadKind(film, kind) {
  const id = filmKey(film)
  if (!id) return

  const sk = stateKey(id, kind)
  const status = downloadState.get(sk)
  if (status === 'downloading' || status === 'done') return

  const url = kind === 'video' ? film.videoUrl : film.thumbnailUrl
  if (!url) return

  try {
    const existing = await getDb().shortFilmBlobs.get([id, kind])
    if (existing?.blob) {
      downloadState.set(sk, 'done')
      return
    }
  } catch {}

  downloadState.set(sk, 'downloading')
  try {
    const blob = await fetchBlob(url)
    const ok = await persistBlob(id, kind, blob)
    downloadState.set(sk, ok ? 'done' : 'failed')
  } catch {
    downloadState.set(sk, 'failed')
  }
}

function enqueueJob(film, kind, priority = 'normal') {
  const id = filmKey(film)
  if (!id) return
  const sk = stateKey(id, kind)
  if (downloadState.get(sk) === 'done' || downloadState.get(sk) === 'downloading') return

  const pri = PRIORITY[priority] ?? PRIORITY.normal
  const existingIdx = queue.findIndex((j) => j.filmId === id && j.kind === kind)
  if (existingIdx >= 0) {
    if (queue[existingIdx].priority > pri) queue[existingIdx].priority = pri
    return
  }
  queue.push({ film, filmId: id, kind, priority: pri })
  queue.sort((a, b) => a.priority - b.priority)
  pumpQueue()
}

function pumpQueue() {
  while (activeDownloads < MAX_CONCURRENT_DOWNLOADS && queue.length > 0) {
    const job = queue.shift()
    if (!job) break
    activeDownloads += 1
    downloadKind(job.film, job.kind).finally(() => {
      activeDownloads -= 1
      pumpQueue()
    })
  }
}

export function enqueueDownload(film, kind = 'video', priority = 'normal') {
  enqueueJob(film, kind, priority)
}

export function prefetchFilms(films, { priority = 'normal', video = true, thumb = true } = {}) {
  if (!Array.isArray(films)) return
  for (const film of films) {
    if (thumb && film.thumbnailUrl) enqueueJob(film, 'thumb', priority)
    if (video && film.videoUrl) enqueueJob(film, 'video', priority)
  }
}

export function prefetchAround(films, currentIndex) {
  if (!Array.isArray(films) || !films.length) return
  const i = Math.max(0, Math.min(currentIndex, films.length - 1))
  const slice = []
  for (let o = 0; o <= PREFETCH_AHEAD; o++) {
    const film = films[i + o]
    if (film) slice.push(film)
  }
  prefetchFilms(slice, { priority: 'high', video: true, thumb: true })
}

export async function clearShortFilmCache() {
  revokeAllObjectUrls()
  queue.length = 0
  downloadState.clear()
  activeDownloads = 0
  try {
    await getDb().transaction('rw', ['shortFilmsMeta', 'shortFilmBlobs'], async () => {
      await getDb().shortFilmsMeta.clear()
      await getDb().shortFilmBlobs.clear()
    })
  } catch {
    // IndexedDB disabled
  }
}

/**
 * Resolve playable video URL: cached blob first, else network + enqueue download.
 */
export async function resolveVideoPlaybackUrl(film) {
  if (!film?.videoUrl) return null
  const id = filmKey(film)
  const cached = await getCachedVideoUrl(id)
  if (cached) return cached
  enqueueDownload(film, 'video', 'high')
  return ensureAbsoluteUrl(film.videoUrl)
}

/**
 * Resolve thumbnail URL: cached blob first, else network + enqueue thumb download.
 */
export async function resolveThumbUrl(film) {
  if (!film?.thumbnailUrl) return null
  const id = filmKey(film)
  const cached = await getCachedThumbUrl(id)
  if (cached) return cached
  enqueueDownload(film, 'thumb', 'normal')
  return ensureAbsoluteUrl(film.thumbnailUrl)
}
