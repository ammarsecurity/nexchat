<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, ChevronRight, Film, LayoutGrid, RefreshCw } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../stores/locale'
import { useShortFilmsStore } from '../stores/shortFilms'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { captureVideoPoster } from '../utils/videoPoster'
import { resolveThumbUrl, onShortFilmCacheUpdate } from '../services/shortFilmCache'

const router = useRouter()
const { t } = useI18n()
const localeStore = useLocaleStore()
const store = useShortFilmsStore()

const posters = ref({})
const thumbUrls = ref({})
const scrollRoot = ref(null)
const loadMoreSentinel = ref(null)
let loadMoreObserver = null

const gridFilms = computed(() => store.gridFilms)
const showFeatured = computed(() => !store.selectedSectionId && store.featured.length > 0)

const gridSectionTitle = computed(() => {
  if (!store.selectedSectionId) return t('shortFilms.allFilms')
  const section = store.sections.find(s => String(s.id) === String(store.selectedSectionId))
  return section?.name ?? t('shortFilms.allFilms')
})

function formatDuration(sec) {
  if (!sec) return ''
  const m = Math.floor(sec / 60)
  const s = sec % 60
  return m > 0 ? `${m}:${String(s).padStart(2, '0')}` : `${s}s`
}

async function resolveThumbForFilm(film) {
  if (!film?.id) return
  const id = String(film.id)
  const url = await resolveThumbUrl(film)
  if (!url) return
  thumbUrls.value = { ...thumbUrls.value, [id]: url }
}

function thumbSrc(film) {
  const id = String(film.id)
  if (thumbUrls.value[id]) return thumbUrls.value[id]
  if (film.thumbnailUrl) return ensureAbsoluteUrl(film.thumbnailUrl)
  return posters.value[film.id] || null
}

function allFilmsForPosters() {
  const films = [...store.featured, ...store.list]
  return films
}

async function loadPosters() {
  const films = allFilmsForPosters()
  for (const film of films) {
    void resolveThumbForFilm(film)
  }
  const next = { ...posters.value }
  for (const film of films) {
    if (film.thumbnailUrl || thumbUrls.value[film.id] || next[film.id] || !film.videoUrl) continue
    const poster = await captureVideoPoster(ensureAbsoluteUrl(film.videoUrl))
    if (poster) next[film.id] = poster
  }
  posters.value = next
}

function selectSection(sectionId) {
  void store.setSection(sectionId)
}

function sectionImageSrc(section) {
  if (!section?.imageUrl) return null
  return ensureAbsoluteUrl(section.imageUrl)
}

function sectionInitial(name) {
  return (name?.trim()?.[0] ?? '?').toUpperCase()
}

function setupLoadMoreObserver() {
  loadMoreObserver?.disconnect()
  if (!loadMoreSentinel.value || !scrollRoot.value) return
  loadMoreObserver = new IntersectionObserver(
    (entries) => {
      if (entries[0]?.isIntersecting && store.hasMore && !store.loadingMore) {
        void store.loadMore().then(() => loadPosters())
      }
    },
    { root: scrollRoot.value, rootMargin: '160px', threshold: 0 }
  )
  loadMoreObserver.observe(loadMoreSentinel.value)
}

function openFilm(film) {
  router.push({ path: '/short-films/watch', query: { start: film.id } })
}

function goBack() {
  router.replace('/home')
}

let offCacheUpdate = null

onMounted(async () => {
  offCacheUpdate = onShortFilmCacheUpdate((filmId, kind) => {
    if (kind !== 'thumb') return
    const film = allFilmsForPosters().find((f) => String(f.id) === String(filmId))
    if (film) void resolveThumbForFilm(film)
  })
  await store.fetchAll(true)
  await loadPosters()
  await nextTick()
  setupLoadMoreObserver()
})

watch(() => store.gridFilms.length, async () => {
  await loadPosters()
  await nextTick()
  setupLoadMoreObserver()
})

watch(() => store.selectedSectionId, async () => {
  await nextTick()
  setupLoadMoreObserver()
})

onUnmounted(() => {
  loadMoreObserver?.disconnect()
  offCacheUpdate?.()
})
</script>

<template>
  <div class="short-films-hub page auth-pattern">
    <header class="hub-header">
      <button type="button" class="hub-header-btn" :aria-label="t('common.back')" @click="goBack">
        <ChevronRight v-if="localeStore.isRtl" :size="22" stroke-width="2" />
        <ChevronLeft v-else :size="22" stroke-width="2" />
      </button>
      <h1 class="hub-title">{{ t('shortFilms.title') }}</h1>
      <button
        type="button"
        class="hub-header-btn"
        :disabled="store.loading"
        :aria-label="t('common.loading')"
        @click="store.fetchAll(true)"
      >
        <RefreshCw :size="18" stroke-width="2" :class="{ spin: store.loading }" />
      </button>
    </header>

    <div v-if="store.sections.length" class="hub-toolbar">
      <div class="section-rings-scroll">
        <button
          type="button"
          class="section-ring"
          @click="selectSection(null)"
        >
          <span class="ring-outer" :class="{ active: !store.selectedSectionId }">
            <span class="ring-inner ring-inner--all">
              <LayoutGrid :size="20" stroke-width="2" class="ring-all-icon" />
            </span>
          </span>
          <span class="ring-label" :class="{ 'ring-label--active': !store.selectedSectionId }">
            {{ t('shortFilms.allSections') }}
          </span>
        </button>
        <button
          v-for="section in store.sections"
          :key="section.id"
          type="button"
          class="section-ring"
          @click="selectSection(section.id)"
        >
          <span
            class="ring-outer"
            :class="{ active: String(store.selectedSectionId) === String(section.id) }"
          >
            <span class="ring-inner">
              <img
                v-if="sectionImageSrc(section)"
                :src="sectionImageSrc(section)"
                class="ring-thumb"
                alt=""
              />
              <span v-else class="ring-letter">{{ sectionInitial(section.name) }}</span>
            </span>
          </span>
          <span
            class="ring-label"
            :class="{ 'ring-label--active': String(store.selectedSectionId) === String(section.id) }"
          >
            {{ section.name }}
          </span>
        </button>
      </div>
    </div>

    <div v-if="store.loading && !store.loaded" class="hub-state">
      <RefreshCw :size="28" class="state-icon spin" />
      <p>{{ t('common.loading') }}</p>
    </div>

    <div
      v-else-if="store.loaded && !store.featured.length && !store.list.length"
      class="hub-state"
    >
      <div class="empty-visual">
        <Film :size="40" stroke-width="1.5" />
      </div>
      <p class="state-title">{{ t('shortFilms.empty') }}</p>
    </div>

    <div v-else ref="scrollRoot" class="hub-scroll">
      <section v-if="showFeatured" class="hub-block">
        <h2 class="block-label">{{ t('shortFilms.featured') }}</h2>
        <div class="film-row">
          <button
            v-for="film in store.featured"
            :key="film.id"
            type="button"
            class="film-card film-card--row"
            @click="openFilm(film)"
          >
            <div class="film-card__thumb">
              <img v-if="thumbSrc(film)" :src="thumbSrc(film)" alt="" class="thumb-img" />
              <div v-else class="thumb-fallback"><Film :size="24" /></div>
              <span class="thumb-gradient" aria-hidden="true" />
              <span v-if="film.durationSeconds" class="duration-pill">{{ formatDuration(film.durationSeconds) }}</span>
              <span class="film-card__title">{{ film.title }}</span>
            </div>
          </button>
        </div>
      </section>

      <section v-if="gridFilms.length" class="hub-block">
        <h2 class="block-label">{{ gridSectionTitle }}</h2>
        <div class="films-grid">
          <button
            v-for="film in gridFilms"
            :key="film.id"
            type="button"
            class="film-card"
            @click="openFilm(film)"
          >
            <div class="film-card__thumb">
              <img v-if="thumbSrc(film)" :src="thumbSrc(film)" alt="" class="thumb-img" />
              <div v-else class="thumb-fallback"><Film :size="22" /></div>
              <span class="thumb-gradient" aria-hidden="true" />
              <span v-if="film.durationSeconds" class="duration-pill">{{ formatDuration(film.durationSeconds) }}</span>
              <span class="film-card__title">{{ film.title }}</span>
            </div>
          </button>
        </div>
      </section>

      <div ref="loadMoreSentinel" class="load-more-sentinel">
        <RefreshCw v-if="store.loadingMore" :size="20" class="spin" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.short-films-hub {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  width: 100%;
  max-width: 100%;
  overflow: hidden;
  background: var(--bg-primary);
  font-family: 'Cairo', system-ui, -apple-system, sans-serif;
  box-sizing: border-box;
}

.short-films-hub button {
  font-family: 'Cairo', system-ui, -apple-system, sans-serif;
}

.hub-header {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-shrink: 0;
  padding: calc(var(--safe-top) + 8px) var(--spacing) 12px;
  background: var(--bg-card);
  border-bottom: 1px solid var(--border);
  box-shadow: 0 1px 0 rgba(0, 0, 0, 0.06);
}

html.light .hub-header,
[data-theme='light'] .hub-header {
  box-shadow: 0 1px 4px rgba(26, 26, 46, 0.06);
}

.hub-header-btn {
  width: var(--header-btn-size);
  height: var(--header-btn-size);
  min-width: var(--header-btn-size);
  border-radius: var(--radius-full);
  border: 1px solid var(--border);
  background: var(--bg-card);
  color: var(--text-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.hub-header-btn:active:not(:disabled) {
  background: var(--bg-card-hover);
  color: var(--primary);
}

.hub-header-btn:disabled {
  opacity: 0.5;
}

.hub-title {
  flex: 1;
  min-width: 0;
  margin: 0;
  font-size: var(--top-title-size);
  font-weight: var(--top-title-weight);
  color: var(--text-primary);
  line-height: 1.25;
  text-align: center;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.hub-toolbar {
  flex-shrink: 0;
  padding: 8px 0 6px;
  background: var(--bg-primary);
  border-bottom: 1px solid var(--border);
}

.section-rings-scroll {
  display: flex;
  gap: 10px;
  overflow-x: auto;
  padding: 2px var(--spacing) 4px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.section-rings-scroll::-webkit-scrollbar {
  display: none;
}

.section-ring {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  min-width: 56px;
  max-width: 64px;
  flex-shrink: 0;
  background: none;
  border: none;
  padding: 0;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.ring-outer {
  display: inline-flex;
  flex-shrink: 0;
  padding: 2px;
  border-radius: 50%;
  background: var(--border);
  transition: background 0.15s ease;
}

.ring-outer.active {
  background: linear-gradient(135deg, #6c63ff, #ff6584, #00d4ff);
}

.ring-inner {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  overflow: hidden;
  background: var(--bg-elevated);
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--bg-primary);
  box-sizing: border-box;
}

.ring-inner--all {
  background: var(--bg-card);
}

.ring-all-icon {
  color: var(--text-secondary);
}

.ring-outer.active .ring-all-icon {
  color: var(--primary);
}

.ring-thumb {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.ring-letter {
  font-size: 17px;
  font-weight: 700;
  color: var(--primary);
}

.ring-label {
  font-size: 10px;
  color: var(--text-secondary);
  max-width: 64px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  text-align: center;
  line-height: 1.2;
}

.ring-label--active {
  color: var(--text-primary);
  font-weight: 600;
}

.hub-scroll {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  -webkit-overflow-scrolling: touch;
  padding: 12px var(--spacing) calc(20px + var(--safe-bottom));
}

.hub-state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 32px var(--spacing);
  color: var(--text-muted);
  text-align: center;
}

.state-icon {
  color: var(--primary);
  opacity: 0.7;
}

.spin {
  animation: spin 0.75s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.empty-visual {
  width: 64px;
  height: 64px;
  border-radius: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(108, 99, 255, 0.1);
  color: var(--primary);
}

.state-title {
  margin: 0;
  font-size: 14px;
  line-height: 1.45;
}

.hub-block + .hub-block {
  margin-top: 20px;
}

.block-label {
  margin: 0 0 10px;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
}

.film-row {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  margin-inline: calc(-1 * var(--spacing));
  padding-inline: var(--spacing);
  padding-bottom: 2px;
  scrollbar-width: none;
}

.film-row::-webkit-scrollbar {
  display: none;
}

.film-card {
  background: none;
  border: none;
  padding: 0;
  cursor: pointer;
  text-align: start;
  -webkit-tap-highlight-color: transparent;
}

.film-card--row {
  flex: 0 0 clamp(108px, 32vw, 130px);
}

.film-card:active .film-card__thumb {
  transform: scale(0.98);
}

.films-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
}

.film-card__thumb {
  position: relative;
  aspect-ratio: 9 / 14;
  border-radius: 12px;
  overflow: hidden;
  background: var(--bg-elevated);
  transition: transform 0.15s ease;
}

.thumb-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.thumb-fallback {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary);
  opacity: 0.5;
  background: var(--bg-card);
}

.thumb-gradient {
  position: absolute;
  inset: 0;
  background: linear-gradient(to top, rgba(0, 0, 0, 0.75) 0%, transparent 55%);
  pointer-events: none;
}

.duration-pill {
  position: absolute;
  top: 6px;
  inset-inline-start: 6px;
  padding: 2px 6px;
  border-radius: 5px;
  background: rgba(0, 0, 0, 0.55);
  color: #fff;
  font-size: 10px;
  font-weight: 700;
  z-index: 1;
}

.film-card__title {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  padding: 24px 8px 8px;
  font-size: 12px;
  font-weight: 600;
  color: #fff;
  line-height: 1.3;
  text-align: start;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  z-index: 1;
}

.load-more-sentinel {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 40px;
  margin-top: 8px;
  color: var(--text-muted);
}

@media (max-width: 360px) {
  .films-grid {
    gap: 6px;
  }

  .film-card__thumb {
    border-radius: 10px;
  }

  .film-card--row {
    flex-basis: 100px;
  }
}
</style>
