<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { X, ChevronUp, ChevronDown, Volume2, VolumeX, Eye, Share2, Play, Pause } from 'lucide-vue-next'
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
import { playVideoWithOptionalSound, unmuteVideoOnUserGesture } from '../utils/mobileVideoPlayback'

const SNAP_MS = 340
const SWIPE_RATIO = 0.2
const SWIPE_MIN_PX = 56
const SWIPE_MAX_MS = 420

const route = useRoute()
const router = useRouter()
const { t } = useI18n()
const store = useShortFilmsStore()

const index = ref(0)
const muted = ref(true)
const userWantsSound = ref(false)
const descExpanded = ref(false)
const viewportEl = ref(null)
const videoRefs = ref({})
const playbackUrls = ref({})
const slideH = ref(0)
const dragY = ref(0)
const isDragging = ref(false)
const snapAnimating = ref(false)
const userPaused = ref(false)

const films = computed(() => store.allFilmsForFeed())
const current = computed(() => films.value[index.value] ?? null)

const windowSlots = computed(() => {
  const list = films.value
  const i = index.value
  if (!list.length) return []
  const slots = []
  if (i > 0) slots.push({ film: list[i - 1], role: 'prev' })
  slots.push({ film: list[i], role: 'current' })
  if (i < list.length - 1) slots.push({ film: list[i + 1], role: 'next' })
  return slots
})

const activeSlotIndex = computed(() => (index.value > 0 ? 1 : 0))

const trackStyle = computed(() => {
  const h = slideH.value
  if (!h) return {}
  const base = -activeSlotIndex.value * h + dragY.value
  const transition = isDragging.value || !snapAnimating.value
    ? 'none'
    : `transform ${SNAP_MS}ms cubic-bezier(0.22, 1, 0.36, 1)`
  return {
    transform: `translate3d(0, ${base}px, 0)`,
    transition
  }
})

let playingFilmId = null
let touchStartY = 0
let touchStartTime = 0
let snapTimer = null
let offCacheUpdate = null
let resizeObserver = null
let touchStartedOnMedia = false

function measureSlideHeight() {
  slideH.value = viewportEl.value?.clientHeight ?? window.innerHeight
}

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
  for (let o = -1; o <= 3; o++) {
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

function pauseAllVideos() {
  Object.values(videoRefs.value).forEach((v) => v?.pause())
}

function currentVideoEl() {
  const film = current.value
  return film ? videoRefs.value[film.id] : null
}

async function playCurrent(force = false) {
  const film = current.value
  if (!film || isDragging.value || snapAnimating.value) return
  if (userPaused.value && !force) return

  Object.entries(videoRefs.value).forEach(([id, v]) => {
    if (!v || String(id) === String(film.id)) return
    v.pause()
  })

  const v = currentVideoEl()
  if (!v) return

  const isSameFilm = playingFilmId === film.id
  if (!isSameFilm) {
    v.currentTime = 0
  }

  const wantSound = userWantsSound.value && !muted.value
  const result = await playVideoWithOptionalSound(v, wantSound)
  if (result.playing) {
    playingFilmId = film.id
  }
  if (wantSound && result.muted) {
    muted.value = true
  } else if (!result.muted) {
    muted.value = false
  }
}

function maxDragDown() {
  return activeSlotIndex.value * slideH.value
}

function maxDragUp() {
  const slots = windowSlots.value.length
  return (slots - 1 - activeSlotIndex.value) * slideH.value
}

function clampDrag(value) {
  const maxDown = maxDragDown()
  const maxUp = maxDragUp()
  if (value > maxDown) return maxDown + (value - maxDown) * 0.28
  if (value < -maxUp) return -maxUp + (value + maxUp) * 0.28
  return value
}

function clearSnapTimer() {
  if (snapTimer) {
    clearTimeout(snapTimer)
    snapTimer = null
  }
}

function finishSnap(direction) {
  clearSnapTimer()
  snapAnimating.value = false
  dragY.value = 0
  if (direction === 'next' && index.value < films.value.length - 1) {
    index.value++
  } else if (direction === 'prev' && index.value > 0) {
    index.value--
  }
  void nextTick().then(() => playCurrent())
}

function animateSnap(targetDrag, direction = null) {
  clearSnapTimer()
  snapAnimating.value = true
  dragY.value = targetDrag
  snapTimer = setTimeout(() => finishSnap(direction), SNAP_MS)
}

function settleDrag() {
  const h = slideH.value
  if (!h) return

  const dy = dragY.value
  const dt = Date.now() - touchStartTime
  const threshold = Math.max(SWIPE_MIN_PX, h * SWIPE_RATIO)
  const flick = dt < SWIPE_MAX_MS && Math.abs(dy) > threshold * 0.65

  if ((dy <= -threshold || (flick && dy < 0)) && index.value < films.value.length - 1) {
    pauseAllVideos()
    animateSnap(-maxDragUp(), 'next')
    return
  }

  if ((dy >= threshold || (flick && dy > 0)) && index.value > 0) {
    pauseAllVideos()
    animateSnap(maxDragDown(), 'prev')
    return
  }

  animateSnap(0)
}

function onTouchStart(e) {
  if (snapAnimating.value) return
  if (e.target.closest('button, a, .feed-desc-wrap, .feed-rail')) {
    touchStartedOnMedia = false
    return
  }
  touchStartedOnMedia = true
  clearSnapTimer()
  snapAnimating.value = false
  isDragging.value = true
  touchStartY = e.touches[0].clientY
  touchStartTime = Date.now()
}

function onTouchMove(e) {
  if (!isDragging.value || snapAnimating.value) return
  const dy = e.touches[0].clientY - touchStartY
  dragY.value = clampDrag(dy)
  if (Math.abs(dy) > 8 && e.cancelable) e.preventDefault()
}

function onTouchEnd() {
  if (!isDragging.value) return
  const dy = dragY.value
  const dt = Date.now() - touchStartTime
  isDragging.value = false

  if (touchStartedOnMedia && Math.abs(dy) < 14 && dt < 350) {
    dragY.value = 0
    togglePlayPause()
    touchStartedOnMedia = false
    return
  }

  touchStartedOnMedia = false
  settleDrag()
}

function goPrev() {
  if (index.value <= 0 || snapAnimating.value || isDragging.value) return
  pauseAllVideos()
  dragY.value = 0
  animateSnap(maxDragDown(), 'prev')
}

function goNext() {
  if (index.value >= films.value.length - 1 || snapAnimating.value || isDragging.value) return
  pauseAllVideos()
  dragY.value = 0
  animateSnap(-maxDragUp(), 'next')
}

function togglePlayPause() {
  const v = currentVideoEl()
  if (!v || snapAnimating.value || isDragging.value) return
  if (userPaused.value || v.paused) {
    userPaused.value = false
    void playCurrent(true)
  } else {
    userPaused.value = true
    v.pause()
  }
}

function onVideoLoadedData(film) {
  if (current.value && String(film.id) === String(current.value.id)) {
    void playCurrent()
  }
}

async function toggleMute() {
  const v = currentVideoEl()
  if (muted.value) {
    userWantsSound.value = true
    muted.value = false
    if (v) {
      const ok = await unmuteVideoOnUserGesture(v)
      if (!ok) {
        muted.value = true
        userWantsSound.value = false
      }
    }
  } else {
    userWantsSound.value = false
    muted.value = true
    if (v) v.muted = true
  }
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
  measureSlideHeight()
  if (viewportEl.value && typeof ResizeObserver !== 'undefined') {
    resizeObserver = new ResizeObserver(() => measureSlideHeight())
    resizeObserver.observe(viewportEl.value)
  }
  playCurrent()
})

watch(current, (film) => {
  if (film) {
    void store.recordView(film.id)
    void refreshPlaybackUrl(film)
  }
}, { immediate: true })

watch(index, () => {
  userPaused.value = false
  descExpanded.value = false
  schedulePrefetchAround()
})

watch(() => route.query.start, async (id) => {
  if (!id) return
  const i = films.value.findIndex(f => String(f.id) === String(id))
  if (i >= 0 && i !== index.value) {
    index.value = i
    dragY.value = 0
    await nextTick()
    playCurrent()
  }
})

onUnmounted(() => {
  clearSnapTimer()
  resizeObserver?.disconnect()
  resizeObserver = null
  pauseAllVideos()
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
    <button
      type="button"
      class="feed-play"
      :aria-label="userPaused ? t('shortFilms.play') : t('shortFilms.pause')"
      @click="togglePlayPause"
    >
      <Play v-if="userPaused" :size="22" />
      <Pause v-else :size="22" />
    </button>

    <div v-if="!films.length" class="feed-empty">{{ t('shortFilms.empty') }}</div>

    <div
      v-else
      ref="viewportEl"
      class="feed-viewport"
      @touchstart.passive="onTouchStart"
      @touchmove="onTouchMove"
      @touchend.passive="onTouchEnd"
      @touchcancel.passive="onTouchEnd"
    >
      <div class="feed-track" :style="trackStyle">
        <section
          v-for="slot in windowSlots"
          :key="slot.film.id"
          class="feed-slide"
          :class="{ 'feed-slide--current': slot.role === 'current' }"
        >
          <video
            :ref="(el) => setVideoRef(slot.film.id, el)"
            class="feed-video"
            :src="videoSrc(slot.film)"
            playsinline
            webkit-playsinline
            x5-playsinline
            loop
            :muted="muted"
            :preload="slot.role === 'current' ? 'auto' : 'metadata'"
            disablepictureinpicture
            controlslist="nodownload nofullscreen noremoteplayback"
            @loadeddata="onVideoLoadedData(slot.film)"
          />
          <div
            v-if="userPaused && slot.role === 'current'"
            class="feed-pause-indicator"
            aria-hidden="true"
          >
            <Play :size="56" stroke-width="1.5" />
          </div>
          <div class="feed-gradient" />
          <aside
            class="feed-rail"
            :class="{ 'feed-rail--active': slot.role === 'current' && !isDragging && !snapAnimating }"
            aria-label="actions"
          >
            <button type="button" class="feed-rail-btn" @click.stop="shareFilm(slot.film)">
              <span class="feed-rail-btn__icon">
                <Share2 :size="18" stroke-width="2" />
              </span>
              <span class="feed-rail-btn__label">{{ t('shortFilms.share') }}</span>
            </button>
            <div class="feed-rail-stat">
              <Eye :size="18" stroke-width="2" />
              <span class="feed-rail-stat__value">{{ slot.film.viewCount || 0 }}</span>
            </div>
          </aside>

          <div
            class="feed-meta"
            :class="{ 'feed-meta--active': slot.role === 'current' && !isDragging && !snapAnimating }"
          >
            <h2 class="feed-title">{{ slot.film.title }}</h2>
            <button
              v-if="slot.film.description"
              type="button"
              class="feed-desc-wrap"
              :class="{ 'feed-desc-wrap--expanded': descExpanded && slot.role === 'current' }"
              @click.stop="slot.role === 'current' && (descExpanded = !descExpanded)"
            >
              <p class="feed-desc">{{ slot.film.description }}</p>
              <span v-if="!descExpanded || slot.role !== 'current'" class="feed-desc-more">
                {{ t('shortFilms.showMore') }}
              </span>
            </button>
          </div>

          <div
            v-if="slot.role === 'current'"
            class="feed-nav-hint"
            :class="{ 'feed-nav-hint--active': !isDragging && !snapAnimating }"
          >
            <button
              v-if="index > 0"
              type="button"
              class="feed-nav-btn"
              aria-label="previous"
              @click.stop="goPrev"
            >
              <ChevronUp :size="20" />
            </button>
            <button
              v-if="index < films.length - 1"
              type="button"
              class="feed-nav-btn"
              aria-label="next"
              @click.stop="goNext"
            >
              <ChevronDown :size="20" />
            </button>
          </div>
        </section>
      </div>
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

.feed-viewport {
  height: 100%;
  height: 100dvh;
  overflow: hidden;
  touch-action: none;
  -webkit-user-select: none;
  user-select: none;
}

.feed-track {
  will-change: transform;
  backface-visibility: hidden;
}

.feed-slide {
  position: relative;
  height: 100dvh;
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #000;
  contain: layout style paint;
}

.feed-video {
  width: 100%;
  height: 100%;
  object-fit: contain;
  background: #000;
  pointer-events: auto;
}

.feed-slide:not(.feed-slide--current) .feed-video {
  pointer-events: none;
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
  opacity: 0;
  transform: translateY(8px);
  transition: opacity 0.32s cubic-bezier(0.22, 1, 0.36, 1), transform 0.32s cubic-bezier(0.22, 1, 0.36, 1);
  pointer-events: none;
}

.feed-rail--active {
  opacity: 1;
  transform: translateY(0);
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
  opacity: 0;
  transform: translateY(10px);
  transition: opacity 0.32s cubic-bezier(0.22, 1, 0.36, 1), transform 0.32s cubic-bezier(0.22, 1, 0.36, 1);
  pointer-events: none;
}

.feed-meta--active {
  opacity: 1;
  transform: translateY(0);
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

.feed-play {
  position: absolute;
  z-index: 10;
  top: calc(12px + var(--safe-top));
  inset-inline-start: calc(12px + 44px + 8px);
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

.feed-pause-indicator {
  position: absolute;
  inset: 0;
  z-index: 2;
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none;
  color: rgba(255, 255, 255, 0.92);
  background: rgba(0, 0, 0, 0.18);
}

.feed-nav-hint {
  position: absolute;
  inset-inline-start: 10px;
  top: 50%;
  transform: translateY(-50%);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  opacity: 0;
  transition: opacity 0.32s ease;
  pointer-events: none;
  z-index: 1;
}

.feed-nav-hint--active {
  opacity: 1;
  pointer-events: auto;
}

.feed-nav-btn {
  width: 36px;
  height: 36px;
  border: none;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.35);
  color: rgba(255, 255, 255, 0.55);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.feed-nav-btn:active {
  background: rgba(0, 0, 0, 0.5);
  color: rgba(255, 255, 255, 0.85);
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
