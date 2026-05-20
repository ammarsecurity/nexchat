import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '../services/api'
import {
  saveFilmsMetadata,
  prefetchFilms,
  clearShortFilmCache
} from '../services/shortFilmCache'

const PAGE_SIZE = 12

function normalizeFilm(f) {
  return {
    id: f.id ?? f.Id,
    title: f.title ?? f.Title ?? '',
    description: f.description ?? f.Description,
    videoUrl: f.videoUrl ?? f.VideoUrl,
    thumbnailUrl: f.thumbnailUrl ?? f.ThumbnailUrl,
    durationSeconds: f.durationSeconds ?? f.DurationSeconds,
    sectionId: f.sectionId ?? f.SectionId ?? null,
    sectionName: f.sectionName ?? f.SectionName ?? null,
    sortOrder: f.sortOrder ?? f.SortOrder ?? 0,
    isFeatured: f.isFeatured ?? f.IsFeatured ?? false,
    viewCount: f.viewCount ?? f.ViewCount ?? 0,
    createdAt: f.createdAt ?? f.CreatedAt
  }
}

function normalizeSection(s) {
  return {
    id: s.id ?? s.Id,
    name: s.name ?? s.Name ?? '',
    imageUrl: s.imageUrl ?? s.ImageUrl ?? null,
    sortOrder: s.sortOrder ?? s.SortOrder ?? 0,
    filmCount: s.filmCount ?? s.FilmCount ?? 0
  }
}

function normalizeSectionBrowse(row) {
  return {
    id: row.id ?? row.Id,
    name: row.name ?? row.Name ?? '',
    imageUrl: row.imageUrl ?? row.ImageUrl ?? null,
    sortOrder: row.sortOrder ?? row.SortOrder ?? 0,
    films: (row.films ?? row.Films ?? []).map(normalizeFilm)
  }
}

export const useShortFilmsStore = defineStore('shortFilms', () => {
  const list = ref([])
  const featured = ref([])
  const sections = ref([])
  const sectionBrowse = ref([])
  const uncategorizedBrowse = ref([])

  const loading = ref(false)
  const loadingMore = ref(false)
  const loaded = ref(false)
  const page = ref(1)
  const total = ref(0)
  const hasMore = ref(true)
  const selectedSectionId = ref(null)
  const viewedFilmIds = ref(new Set())

  const filmCount = computed(() => total.value || list.value.length)

  const gridFilms = computed(() => {
    const featuredIds = new Set(featured.value.map(f => String(f.id)))
    return list.value.filter(f => !featuredIds.has(String(f.id)))
  })

  function mergeUniqueFilms(existing, incoming) {
    const ids = new Set(existing.map(f => String(f.id)))
    const merged = [...existing]
    for (const film of incoming) {
      const id = String(film.id)
      if (ids.has(id)) continue
      ids.add(id)
      merged.push(film)
    }
    return merged
  }

  async function fetchSections() {
    try {
      const res = await api.get('/short-films/sections', { skipGlobalLoader: true })
      sections.value = (res.data ?? []).map(normalizeSection)
    } catch {
      sections.value = []
    }
  }

  async function fetchBrowse(previewSize = 8) {
    try {
      const res = await api.get('/short-films/browse', {
        params: { previewSize },
        skipGlobalLoader: true
      })
      const data = res.data ?? {}
      sectionBrowse.value = (data.sections ?? data.Sections ?? []).map(normalizeSectionBrowse)
      uncategorizedBrowse.value = (data.uncategorizedFilms ?? data.UncategorizedFilms ?? []).map(normalizeFilm)
    } catch {
      sectionBrowse.value = []
      uncategorizedBrowse.value = []
    }
  }

  async function fetchPage({ reset = false } = {}) {
    if (loading.value || loadingMore.value) return
    if (!reset && !hasMore.value) return

    if (reset) {
      page.value = 1
      hasMore.value = true
      loading.value = true
    } else {
      loadingMore.value = true
    }

    try {
      const params = {
        page: page.value,
        pageSize: PAGE_SIZE,
        excludeFeatured: true
      }
      if (selectedSectionId.value) {
        params.sectionId = selectedSectionId.value
      }

      let pageRes
      if (reset) {
        const featParams = selectedSectionId.value ? { sectionId: selectedSectionId.value } : {}
        const [featRes] = await Promise.all([
          api.get('/short-films/featured', { params: featParams, skipGlobalLoader: true }),
          fetchSections()
        ])
        featured.value = (featRes.data ?? []).map(normalizeFilm)
        pageRes = await api.get('/short-films', { params, skipGlobalLoader: true })
      } else {
        pageRes = await api.get('/short-films', { params, skipGlobalLoader: true })
      }

      const data = pageRes.data ?? {}
      const items = (data.items ?? data.Items ?? []).map(normalizeFilm)
      list.value = reset ? items : mergeUniqueFilms(list.value, items)

      total.value = data.total ?? data.Total ?? list.value.length
      hasMore.value = data.hasMore ?? data.HasMore ?? page.value * PAGE_SIZE < total.value
      page.value += 1
      loaded.value = true

      const toCache = reset
        ? [...featured.value, ...list.value]
        : items
      void saveFilmsMetadata(toCache)
      if (reset) {
        prefetchFilms(featured.value, { priority: 'high', video: true, thumb: true })
        prefetchFilms(list.value.slice(0, PAGE_SIZE), {
          priority: 'normal',
          video: false,
          thumb: true
        })
      } else {
        prefetchFilms(items, { priority: 'low', video: false, thumb: true })
      }
    } catch {
      if (reset) {
        list.value = []
        featured.value = []
        total.value = 0
        hasMore.value = false
      }
    } finally {
      loading.value = false
      loadingMore.value = false
    }
  }

  async function fetchAll(force = false) {
    if (loading.value && !force) return
    if (loaded.value && !force) return
    await fetchSections()
    await fetchPage({ reset: true })
  }

  async function setSection(sectionId) {
    const next = sectionId ? String(sectionId) : null
    if (selectedSectionId.value === next) return
    selectedSectionId.value = next
    await fetchPage({ reset: true })
  }

  function loadMore() {
    return fetchPage({ reset: false })
  }

  function invalidate() {
    loaded.value = false
    page.value = 1
    hasMore.value = true
    list.value = []
    featured.value = []
    sectionBrowse.value = []
    uncategorizedBrowse.value = []
    viewedFilmIds.value = new Set()
    void clearShortFilmCache()
  }

  function patchFilmViewCount(filmId, viewCount) {
    const id = String(filmId)
    const patch = (film) => {
      if (String(film.id) === id) film.viewCount = viewCount
    }
    list.value.forEach(patch)
    featured.value.forEach(patch)
    uncategorizedBrowse.value.forEach(patch)
    sectionBrowse.value.forEach((row) => row.films.forEach(patch))
  }

  function bumpFilmViewCount(filmId) {
    const id = String(filmId)
    const bump = (film) => {
      if (String(film.id) === id) film.viewCount = (film.viewCount || 0) + 1
    }
    list.value.forEach(bump)
    featured.value.forEach(bump)
    uncategorizedBrowse.value.forEach(bump)
    sectionBrowse.value.forEach((row) => row.films.forEach(bump))
  }

  async function recordView(filmId) {
    const id = String(filmId)
    if (!id || viewedFilmIds.value.has(id)) return
    viewedFilmIds.value.add(id)
    try {
      const res = await api.post(`/short-films/${filmId}/view`, {}, { skipGlobalLoader: true })
      const count = res.data?.viewCount ?? res.data?.ViewCount
      if (count != null) patchFilmViewCount(filmId, count)
      else bumpFilmViewCount(filmId)
    } catch {
      viewedFilmIds.value.delete(id)
    }
  }

  function filmById(id) {
    const fromList = list.value.find(f => String(f.id) === String(id))
    if (fromList) return fromList
    const fromFeat = featured.value.find(f => String(f.id) === String(id))
    if (fromFeat) return fromFeat
    for (const row of sectionBrowse.value) {
      const hit = row.films.find(f => String(f.id) === String(id))
      if (hit) return hit
    }
    return uncategorizedBrowse.value.find(f => String(f.id) === String(id)) ?? null
  }

  function allFilmsForFeed() {
    const ids = new Set()
    const ordered = []
    const add = (film) => {
      const id = String(film.id)
      if (ids.has(id)) return
      ids.add(id)
      ordered.push(film)
    }
    for (const film of featured.value) add(film)
    for (const row of sectionBrowse.value) {
      for (const film of row.films) add(film)
    }
    for (const film of uncategorizedBrowse.value) add(film)
    for (const film of list.value) add(film)
    return ordered
  }

  async function loadAllPages() {
    let guard = 0
    while (hasMore.value && !loadingMore.value && guard < 100) {
      guard += 1
      await loadMore()
    }
  }

  return {
    list,
    featured,
    sections,
    sectionBrowse,
    uncategorizedBrowse,
    loading,
    loadingMore,
    loaded,
    hasMore,
    total,
    selectedSectionId,
    filmCount,
    gridFilms,
    fetchAll,
    fetchSections,
    fetchPage,
    setSection,
    loadMore,
    invalidate,
    recordView,
    filmById,
    allFilmsForFeed,
    loadAllPages
  }
})
