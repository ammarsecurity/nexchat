<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Film, Play, ChevronLeft, ChevronRight, ChevronDown, ChevronUp } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../stores/locale'
import { useShortFilmsStore } from '../stores/shortFilms'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { captureVideoPoster } from '../utils/videoPoster'
import { resolveThumbUrl, onShortFilmCacheUpdate } from '../services/shortFilmCache'

const STRIP_EXPANDED_KEY = 'nexchat:shortFilmsStripExpanded'

const router = useRouter()
const { t } = useI18n()
const localeStore = useLocaleStore()
const store = useShortFilmsStore()
const posters = ref({})
const thumbUrls = ref({})

function readExpandedPreference() {
  try {
    const saved = localStorage.getItem(STRIP_EXPANDED_KEY)
    if (saved === '0') return false
    if (saved === '1') return true
  } catch {}
  return false
}

const expanded = ref(readExpandedPreference())

const stripFilms = () => {
  const featured = store.featured.slice(0, 6)
  if (featured.length) return featured
  return store.list.slice(0, 8)
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

async function loadPosters() {
  const films = stripFilms()
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

function openHub() {
  router.push('/short-films')
}

function openFilm(film) {
  router.push({ path: '/short-films/watch', query: { start: film.id } })
}

function toggleExpanded() {
  expanded.value = !expanded.value
  try {
    localStorage.setItem(STRIP_EXPANDED_KEY, expanded.value ? '1' : '0')
  } catch {}
}

let offCacheUpdate = null

onMounted(async () => {
  offCacheUpdate = onShortFilmCacheUpdate((filmId, kind) => {
    if (kind !== 'thumb') return
    const film = stripFilms().find((f) => String(f.id) === String(filmId))
    if (film) void resolveThumbForFilm(film)
  })
  await store.fetchAll()
  void loadPosters()
})

watch(
  () => store.list.map(f => f.id).join(','),
  () => { void loadPosters() }
)

onUnmounted(() => {
  offCacheUpdate?.()
})
</script>

<template>
  <section
    v-if="store.list.length"
    class="short-films-strip"
    :class="{ 'short-films-strip--collapsed': !expanded }"
    :aria-label="t('shortFilms.title')"
  >
    <div class="strip-head">
      <button
        type="button"
        class="strip-toggle"
        :aria-expanded="expanded"
        :aria-label="expanded ? t('shortFilms.collapseStrip') : t('shortFilms.expandStrip')"
        @click="toggleExpanded"
      >
        <ChevronUp v-if="expanded" :size="18" stroke-width="2.25" aria-hidden="true" />
        <ChevronDown v-else :size="18" stroke-width="2.25" aria-hidden="true" />
      </button>
      <button type="button" class="strip-head-title" @click="openHub">
        <Film :size="16" stroke-width="2" class="strip-icon" aria-hidden="true" />
        <span class="strip-title">{{ t('shortFilms.title') }}</span>
      </button>
      <button type="button" class="strip-see-all" @click="openHub">
        <span>{{ t('shortFilms.seeAll') }}</span>
        <ChevronLeft v-if="localeStore.isRtl" :size="15" stroke-width="2.25" aria-hidden="true" />
        <ChevronRight v-else :size="15" stroke-width="2.25" aria-hidden="true" />
      </button>
    </div>
    <div class="strip-body" :class="{ 'strip-body--collapsed': !expanded }">
      <div class="strip-body-inner">
        <div class="strip-scroll">
          <button
            v-for="film in stripFilms()"
            :key="film.id"
            type="button"
            class="strip-card"
            @click="openFilm(film)"
          >
            <div class="strip-thumb">
              <img v-if="thumbSrc(film)" :src="thumbSrc(film)" alt="" class="strip-thumb-img" />
              <div v-else class="strip-thumb-fallback">
                <Film :size="18" stroke-width="1.75" aria-hidden="true" />
              </div>
              <span class="strip-play" aria-hidden="true">
                <Play :size="12" fill="currentColor" stroke-width="0" />
              </span>
            </div>
            <span class="strip-label">{{ film.title }}</span>
          </button>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.short-films-strip {
  --strip-font: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
    'Helvetica Neue', Arial, sans-serif;
  flex-shrink: 0;
  padding: 4px 0 6px;
  background: var(--wa-subbar, var(--bg-primary));
  border-bottom: 1px solid var(--border);
  font-family: var(--strip-font);
}

.short-films-strip--collapsed {
  padding-bottom: 4px;
}

html.light .conversations--wa .short-films-strip,
[data-theme='light'] .conversations--wa .short-films-strip {
  background: var(--wa-subbar, #fff);
}

.strip-head {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 4px 10px 6px;
  min-height: 32px;
}

.short-films-strip--collapsed .strip-head {
  padding-bottom: 4px;
}

.strip-toggle {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  width: 28px;
  height: 28px;
  margin: 0;
  padding: 0;
  border: none;
  border-radius: 50%;
  background: transparent;
  color: var(--text-muted);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.strip-toggle:active {
  background: var(--bg-card);
  opacity: 0.85;
}

.strip-head-title,
.strip-see-all {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  border: none;
  background: none;
  padding: 0;
  margin: 0;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  font-family: 'Cairo', sans-serif;
  color: inherit;
}

.strip-head-title {
  flex: 1;
  min-width: 0;
  justify-content: flex-start;
}

.strip-icon {
  flex-shrink: 0;
  color: var(--primary);
}

.strip-title {
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--text-primary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.strip-see-all {
  font-family: 'Cairo', sans-serif;
  flex-shrink: 0;
  gap: 2px;
  font-size: 12px;
  font-weight: 500;
  color: var(--text-muted);
}

.strip-see-all:active {
  opacity: 0.7;
}

.strip-body {
  display: grid;
  grid-template-rows: 1fr;
  transition: grid-template-rows 0.22s ease;
}

.strip-body--collapsed {
  grid-template-rows: 0fr;
}

.strip-body-inner {
  overflow: hidden;
  min-height: 0;
}

.strip-scroll {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding: 0 10px 2px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.strip-scroll::-webkit-scrollbar {
  display: none;
}

.strip-card {
  flex: 0 0 auto;
  width: 76px;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 5px;
  background: none;
  border: none;
  padding: 0;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  text-align: start;
  font-family: var(--strip-font);
}

.strip-thumb {
  position: relative;
  width: 76px;
  height: 104px;
  border-radius: 10px;
  overflow: hidden;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
}

.strip-thumb-img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.strip-thumb-fallback {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary);
  opacity: 0.4;
  background: var(--bg-card);
}

.strip-play {
  position: absolute;
  inset-inline-end: 6px;
  bottom: 6px;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.55);
  color: #fff;
  backdrop-filter: blur(4px);
}

.strip-label {
  display: block;
  font-family: 'Cairo', sans-serif !important;
  font-size: 11px;
  font-weight: 500;
  line-height: 1.25;
  letter-spacing: -0.01em;
  color: var(--text-secondary);
  max-width: 76px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
