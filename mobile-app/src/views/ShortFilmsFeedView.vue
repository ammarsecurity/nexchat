<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { X, ChevronUp, ChevronDown, Volume2, VolumeX, Eye, Share2 } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useShortFilmsStore } from '../stores/shortFilms'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { buildShortFilmShareMessage } from '../utils/shortFilmShare'
import {
  prefetchAround,
  resolveVideoPlaybackUrl,
  onShortFilmCacheUpdate,
  revokeAllObjectUrls
} from '../services/shortFilmCache'

const route = useRoute()
const router = useRouter()
const { t } = useI18n()
const store = useShortFilmsStore()

const index = ref(0)
const muted = ref(false)
const descExpanded = ref(false)
const containerEl = ref(null)
const videoRefs = ref({})
const playbackUrls = ref({})

const films = computed(() => store.allFilmsForFeed())
const current = computed(() => films.value[index.value] ?? null)

async function refreshPlaybackUrl(film) {
  if (!film?.id) return
  const id = String(film.id)
  const url = await resolveVideoPlaybackUrl(film)
  if (!url) return
  const prev = playbackUrls.value[id]
  if (prev === url) return
  playbackUrls.value = { ...playbackUrls.value, [id]: url }
  if (current.value && String(current.value.id) === id) {
    await nextTick()
    playCurrent()
  }
}

function schedulePrefetchAround() {
  prefetchAround(films.value, index.value)
  const i = index.value
  for (let o = 0; o <= 3; o++) {
    const film = films.value[i + o]
    if (film) void refreshPlaybackUrl(film)
  }
}

function videoSrc(film) {
  if (!film) return ''
  const cached = playbackUrls.value[String(film.id)]
  if (cached) return cached
  return film.videoUrl ? ensureAbsoluteUrl(film.videoUrl) : ''
}

function setVideoRef(id, el) {
  if (el) videoRefs.value[id] = el
  else delete videoRefs.value[id]
}

function scrollToIndex(i, smooth = true) {
  const el = containerEl.value
  if (!el) return
  const h = el.clientHeight
  el.scrollTo({ top: i * h, behavior: smooth ? 'smooth' : 'instant' })
}

function onScroll() {
  const el = containerEl.value
  if (!el || !films.value.length) return
  const h = el.clientHeight
  if (h <= 0) return
  const i = Math.round(el.scrollTop / h)
  if (i !== index.value && i >= 0 && i < films.value.length) {
    index.value = i
    playCurrent()
  }
}

function playCurrent() {
  Object.values(videoRefs.value).forEach((v) => {
    if (!v) return
    v.pause()
  })
  const film = current.value
  if (!film) return
  const v = videoRefs.value[film.id]
  if (!v) return
  v.muted = muted.value
  v.currentTime = 0
  void v.play().catch(() => {})
}

function goPrev() {
  if (index.value > 0) {
    index.value--
    scrollToIndex(index.value)
    playCurrent()
  }
}

function goNext() {
  if (index.value < films.value.length - 1) {
    index.value++
    scrollToIndex(index.value)
    playCurrent()
  }
}

function toggleMute() {
  muted.value = !muted.value
  const v = current.value && videoRefs.value[current.value.id]
  if (v) v.muted = muted.value
}

function closeFeed() {
  router.back()
}

function shareFilm(film) {
  if (!film) return
  router.push({
    path: '/share-message',
    state: {
      shareMessage: buildShortFilmShareMessage(film),
      returnPath: `/short-films/watch?start=${film.id}`
    }
  })
}

let touchStartY = 0
function onTouchStart(e) {
  touchStartY = e.touches[0].clientY
}

function onTouchEnd(e) {
  const dy = touchStartY - e.changedTouches[0].clientY
  if (Math.abs(dy) < 48) return
  if (dy > 0) goNext()
  else goPrev()
}

let offCacheUpdate = null

onMounted(async () => {
  offCacheUpdate = onShortFilmCacheUpdate((filmId, kind) => {
    if (kind !== 'video') return
    const film = films.value.find((f) => String(f.id) === String(filmId))
    if (film) void refreshPlaybackUrl(film)
  })

  await store.fetchAll(true)
  await store.loadAllPages()
  const startId = route.query.start
  if (startId) {
    const i = films.value.findIndex(f => String(f.id) === String(startId))
    if (i >= 0) index.value = i
  }
  schedulePrefetchAround()
  await nextTick()
  scrollToIndex(index.value, false)
  playCurrent()
})

watch(current, (film) => {
  if (film) {
    void store.recordView(film.id)
    void refreshPlaybackUrl(film)
  }
}, { immediate: true })

watch(index, () => {
  descExpanded.value = false
  schedulePrefetchAround()
})

watch(() => route.query.start, async (id) => {
  if (!id) return
  const i = films.value.findIndex(f => String(f.id) === String(id))
  if (i >= 0 && i !== index.value) {
    index.value = i
    await nextTick()
    scrollToIndex(i, false)
    playCurrent()
  }
})

onUnmounted(() => {
  Object.values(videoRefs.value).forEach((v) => v?.pause())
  offCacheUpdate?.()
  revokeAllObjectUrls()
  playbackUrls.value = {}
})
</script>

<template>
  <div class="short-films-feed">
    <button type="button" class="feed-close" @click="closeFeed" aria-label="close">
      <X :size="24" />
    </button>
    <button type="button" class="feed-mute" @click="toggleMute" aria-label="mute">
      <VolumeX v-if="muted" :size="22" />
      <Volume2 v-else :size="22" />
    </button>

    <div v-if="!films.length" class="feed-empty">{{ t('shortFilms.empty') }}</div>

    <div
      v-else
      ref="containerEl"
      class="feed-scroll"
      @scroll.passive="onScroll"
      @touchstart.passive="onTouchStart"
      @touchend.passive="onTouchEnd"
    >
      <section
        v-for="(film, i) in films"
        :key="film.id"
        class="feed-slide"
      >
        <video
          :ref="(el) => setVideoRef(film.id, el)"
          class="feed-video"
          :src="videoSrc(film)"
          playsinline
          webkit-playsinline
          loop
          :muted="muted"
          preload="metadata"
          @click="toggleMute"
        />
        <div class="feed-gradient" />
        <template v-if="i === index">
          <aside class="feed-rail" aria-label="actions">
            <button type="button" class="feed-rail-btn" @click.stop="shareFilm(film)">
              <span class="feed-rail-btn__icon">
                <Share2 :size="18" stroke-width="2" />
              </span>
              <span class="feed-rail-btn__label">{{ t('shortFilms.share') }}</span>
            </button>
            <div class="feed-rail-stat">
              <Eye :size="18" stroke-width="2" />
              <span class="feed-rail-stat__value">{{ film.viewCount || 0 }}</span>
            </div>
          </aside>

          <div class="feed-meta">
            <h2 class="feed-title">{{ film.title }}</h2>
            <button
              v-if="film.description"
              type="button"
              class="feed-desc-wrap"
              :class="{ 'feed-desc-wrap--expanded': descExpanded }"
              @click.stop="descExpanded = !descExpanded"
            >
              <p class="feed-desc">{{ film.description }}</p>
              <span v-if="!descExpanded" class="feed-desc-more">{{ t('shortFilms.showMore') }}</span>
            </button>
          </div>
        </template>

        <div v-if="i === index" class="feed-nav-hint">
          <ChevronUp v-if="index > 0" :size="20" class="hint-icon" />
          <span v-if="index > 0 && index < films.length - 1" class="hint-dot">·</span>
          <ChevronDown v-if="index < films.length - 1" :size="20" class="hint-icon" />
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.short-films-feed {
  position: fixed;
  inset: 0;
  z-index: 200;
  background: #000;
  font-family: 'Cairo', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}

.short-films-feed button,
.short-films-feed p,
.short-films-feed h2 {
  font-family: inherit;
}

.feed-meta,
.feed-title,
.feed-desc-wrap,
.feed-desc,
.feed-desc-more {
  font-family: 'Cairo', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}

.feed-scroll {
  height: 100%;
  overflow-y: scroll;
  scroll-snap-type: y mandatory;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.feed-scroll::-webkit-scrollbar {
  display: none;
}

.feed-slide {
  position: relative;
  height: 100vh;
  height: 100dvh;
  scroll-snap-align: start;
  scroll-snap-stop: always;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #000;
}

.feed-video {
  width: 100%;
  height: 100%;
  object-fit: contain;
  background: #000;
}

.feed-gradient {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    linear-gradient(to top, rgba(0, 0, 0, 0.88) 0%, rgba(0, 0, 0, 0.35) 28%, transparent 48%),
    linear-gradient(to bottom, rgba(0, 0, 0, 0.35) 0%, transparent 18%);
}

.feed-rail {
  position: absolute;
  z-index: 3;
  bottom: calc(72px + var(--safe-bottom));
  inset-inline-end: 10px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 18px;
  pointer-events: auto;
}

.feed-rail-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 0;
  border: none;
  background: none;
  color: #fff;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  max-width: 56px;
}

.feed-rail-btn__icon {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(108, 99, 255, 0.92);
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.35);
}

.feed-rail-btn:active .feed-rail-btn__icon {
  transform: scale(0.94);
  opacity: 0.92;
}

.feed-rail-btn__label {
  font-family: inherit;
  font-size: 11px;
  font-weight: 700;
  line-height: 1.2;
  text-align: center;
  text-shadow: 0 1px 3px rgba(0, 0, 0, 0.6);
}

.feed-rail-stat {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  color: #fff;
  text-shadow: 0 1px 3px rgba(0, 0, 0, 0.6);
}

.feed-rail-stat__value {
  font-family: inherit;
  font-size: 12px;
  font-weight: 700;
  line-height: 1;
}

.feed-meta {
  position: absolute;
  z-index: 2;
  bottom: 0;
  inset-inline-start: 0;
  inset-inline-end: 0;
  padding: 12px 72px calc(14px + var(--safe-bottom)) 14px;
  color: #fff;
  text-align: start;
  pointer-events: none;
}

.feed-title {
  font-family: inherit;
  margin: 0 0 4px;
  font-size: 16px;
  font-weight: 700;
  line-height: 1.3;
  text-shadow: 0 1px 6px rgba(0, 0, 0, 0.65);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  pointer-events: auto;
}

.feed-desc-wrap {
  display: block;
  width: 100%;
  margin: 0;
  padding: 0;
  border: none;
  background: none;
  color: inherit;
  text-align: inherit;
  cursor: pointer;
  pointer-events: auto;
  -webkit-tap-highlight-color: transparent;
}

.feed-desc {
  font-family: inherit;
  margin: 0;
  font-size: 13px;
  line-height: 1.45;
  opacity: 0.92;
  text-shadow: 0 1px 4px rgba(0, 0, 0, 0.55);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.feed-desc-wrap--expanded .feed-desc {
  -webkit-line-clamp: unset;
  display: block;
}

.feed-desc-more {
  font-family: inherit;
  display: inline-block;
  margin-top: 4px;
  font-size: 12px;
  font-weight: 700;
  color: rgba(255, 255, 255, 0.85);
}

.feed-desc-wrap--expanded .feed-desc-more {
  display: none;
}

.feed-close,
.feed-mute {
  position: absolute;
  z-index: 10;
  width: 44px;
  height: 44px;
  border: none;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.45);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  backdrop-filter: blur(8px);
}

.feed-close {
  top: calc(12px + var(--safe-top));
  inset-inline-end: 12px;
}

.feed-mute {
  top: calc(12px + var(--safe-top));
  inset-inline-start: 12px;
}

.feed-nav-hint {
  position: absolute;
  inset-inline-start: 10px;
  top: 50%;
  transform: translateY(-50%);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  color: rgba(255, 255, 255, 0.45);
  pointer-events: none;
  z-index: 1;
}

.hint-dot {
  font-size: 10px;
}

.feed-empty {
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  opacity: 0.7;
}

@media (max-width: 380px) {
  .feed-rail {
    bottom: calc(64px + var(--safe-bottom));
    inset-inline-end: 8px;
    gap: 14px;
  }

  .feed-rail-btn__icon {
    width: 36px;
    height: 36px;
  }

  .feed-meta {
    padding-inline-end: 64px;
    padding-inline-start: 12px;
  }

  .feed-title {
    font-size: 15px;
  }

  .feed-desc {
    font-size: 12px;
  }
}

@media (min-width: 481px) {
  .feed-meta {
    max-width: min(420px, 72vw);
    padding-inline-end: 14px;
  }

  .feed-rail {
    bottom: calc(80px + var(--safe-bottom));
    inset-inline-end: 20px;
  }
}
</style>
