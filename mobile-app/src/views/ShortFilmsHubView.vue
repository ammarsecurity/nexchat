<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { Film, LayoutGrid, RefreshCw } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import ModernPageShell from '../components/ui/ModernPageShell.vue'
import EmptyState from '../components/ui/EmptyState.vue'
import { useShortFilmsStore } from '../stores/shortFilms'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { captureVideoPoster } from '../utils/videoPoster'
import { resolveThumbUrl, onShortFilmCacheUpdate } from '../services/shortFilmCache'

const router = useRouter()
const { t } = useI18n()
const store = useShortFilmsStore()

const shellRef = ref(null)
const posters = ref({})
const thumbUrls = ref({})
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
  return [...store.featured, ...store.list]
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

function scrollRoot() {
  return shellRef.value?.scrollEl ?? null
}

function setupLoadMoreObserver() {
  loadMoreObserver?.disconnect()
  const root = scrollRoot()
  if (!loadMoreSentinel.value || !root) return
  loadMoreObserver = new IntersectionObserver(
    (entries) => {
      if (entries[0]?.isIntersecting && store.hasMore && !store.loadingMore) {
        void store.loadMore().then(() => loadPosters())
      }
    },
    { root, rootMargin: '160px', threshold: 0 }
  )
  loadMoreObserver.observe(loadMoreSentinel.value)
}

function openFilm(film) {
  router.push({ path: '/short-films/watch', query: { start: film.id } })
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
  <ModernPageShell ref="shellRef" :title="t('shortFilms.title')" back-to="/home">
    <template #actions>
      <button
        type="button"
        class="modern-glass-btn"
        :disabled="store.loading"
        :aria-label="t('common.loading')"
        @click="store.fetchAll(true)"
      >
        <RefreshCw :size="18" stroke-width="2" :class="{ spin: store.loading }" />
      </button>
    </template>

    <template v-if="store.sections.length" #before-scroll>
      <div class="hub-toolbar">
        <div class="section-rings-scroll">
          <button type="button" class="section-ring" @click="selectSection(null)">
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
    </template>

    <div v-if="store.loading && !store.loaded" class="hub-state">
      <RefreshCw :size="28" class="state-icon spin" />
      <p>{{ t('common.loading') }}</p>
    </div>

    <EmptyState v-else-if="store.loaded && !store.featured.length && !store.list.length" :title="t('shortFilms.empty')">
      <template #icon><Film :size="32" stroke-width="1.5" /></template>
    </EmptyState>

    <template v-else>
      <section v-if="showFeatured" class="hub-block">
        <h2 class="modern-section-title">{{ t('shortFilms.featured') }}</h2>
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
        <h2 class="modern-section-title">{{ gridSectionTitle }}</h2>
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
    </template>
  </ModernPageShell>
</template>

<style scoped>
.hub-toolbar {
  flex-shrink: 0;
  padding: 4px 0 10px;
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
  background: linear-gradient(145deg, #2563eb, #60a5fa);
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
  font-family: 'Cairo', sans-serif;
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

.hub-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 48px var(--spacing);
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

.hub-block + .hub-block {
  margin-top: 20px;
}

.hub-block .modern-section-title {
  margin: 0 0 10px;
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
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
}

.film-card__thumb {
  position: relative;
  aspect-ratio: 9 / 14;
  border-radius: var(--radius-md);
  overflow: hidden;
  background: var(--bg-elevated);
  transition: transform 0.15s ease;
  box-shadow: var(--shadow-sm);
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
  padding: 20px 6px 6px;
  font-size: 10px;
  font-weight: 600;
  color: #fff;
  line-height: 1.25;
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
    gap: 4px;
  }

  .film-card__thumb {
    border-radius: 8px;
  }

  .film-card__title {
    font-size: 9px;
    padding: 16px 4px 4px;
  }

  .film-card--row {
    flex-basis: 100px;
  }
}
</style>
