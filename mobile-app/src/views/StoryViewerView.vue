<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { X, Eye, Send, Pause, Volume2, VolumeX, Share2 } from 'lucide-vue-next'
import { shareStoryPublic } from '../utils/shareExternal'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../stores/locale'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { useStoriesStore } from '../stores/stories'
import { useAuthStore } from '../stores/auth'
import CachedAvatar from '../components/CachedAvatar.vue'
import StoryDialog from '../components/stories/StoryDialog.vue'
import { playVideoWithOptionalSound, unmuteVideoOnUserGesture } from '../utils/mobileVideoPlayback'

const route = useRoute()
const router = useRouter()
const { t } = useI18n()
const storiesStore = useStoriesStore()
const auth = useAuthStore()
const localeStore = useLocaleStore()
const userId = computed(() => route.params.userId)
const slides = ref([])
const loading = ref(true)
const mediaReady = ref(false)
const videoPlaying = ref(false)
const index = ref(0)
const progress = ref(0)
const paused = ref(false)
const replyText = ref('')
const sending = ref(false)
const showViewers = ref(false)
const viewers = ref([])
const slideDir = ref(null)
const dragX = ref(0)
const isDragging = ref(false)
const transitioning = ref(false)
const videoEl = ref(null)
const muted = ref(true)
const userWantsSound = ref(false)
const skipNextRouteLoad = ref(false)
const userSwitching = ref(false)

const dialogOpen = ref(false)
const dialogMessage = ref('')

function showStoryAlert(message) {
  dialogMessage.value = message
  dialogOpen.value = true
}

function closeStoryDialog() {
  dialogOpen.value = false
  dialogMessage.value = ''
}

async function shareCurrentStory() {
  await shareStoryPublic(userId.value, { t, publisherName: publisherName.value })
}

const mediaCache = new Set()
let timer = null
let touchStartX = 0
let touchStartY = 0
let touchStartTime = 0
let didSwipe = false

const SLIDE_MS = 5000
const SWIPE_RATIO = 0.18
const SWIPE_DOWN_MIN = 72

const current = computed(() => slides.value[index.value])
const isOwner = computed(() => String(userId.value) === String(auth.user?.id))
const publisherName = computed(() => storiesStore.feed.find(r => String(r.userId) === String(userId.value))?.name ?? '—')

const feedRings = computed(() => {
  const withSlides = storiesStore.feed.filter(r => (r.slideCount ?? 0) > 0)
  const mine = withSlides.filter(r => r.isMine)
  const others = withSlides.filter(r => !r.isMine)
  return [...mine, ...others]
})

const slideTransitionName = computed(() => {
  if (slideDir.value === 'next') return 'story-slide-next'
  if (slideDir.value === 'prev') return 'story-slide-prev'
  return 'story-fade'
})

const mediaDragStyle = computed(() => {
  if (!isDragging.value || !dragX.value) return {}
  const damp = 0.55
  return {
    transform: `translateX(${dragX.value * damp}px)`,
    transition: 'none'
  }
})

const filterStyle = computed(() => {
  const f = current.value?.filterId
  if (!f || f === 'none') return {}
  const map = {
    grayscale: 'grayscale(100%)',
    sepia: 'sepia(80%)',
    vintage: 'sepia(40%) contrast(1.1)',
    warm: 'sepia(30%) hue-rotate(-10deg)',
    cool: 'hue-rotate(180deg) saturate(0.85)',
    vivid: 'saturate(1.4) contrast(1.05)'
  }
  return { filter: map[f] || 'none' }
})

function preloadMedia(slide) {
  if (!slide?.mediaUrl || slide.mediaType === 'text') return Promise.resolve()
  const url = ensureAbsoluteUrl(slide.mediaUrl)
  if (slide.mediaType === 'video') {
    return new Promise((resolve) => {
      const el = document.createElement('video')
      el.preload = 'auto'
      el.muted = true
      el.playsInline = true
      const done = () => resolve()
      el.addEventListener('loadeddata', done, { once: true })
      el.addEventListener('error', done, { once: true })
      setTimeout(done, 8000)
      el.src = url
    })
  }
  return new Promise((resolve) => {
    const img = new Image()
    img.onload = () => resolve()
    img.onerror = () => resolve()
    img.src = url
  })
}

function cacheSlide(slide) {
  if (slide?.id) mediaCache.add(slide.id)
}

function prefetchAdjacent() {
  const prev = slides.value[index.value - 1]
  const next = slides.value[index.value + 1]
  if (prev) void preloadMedia(prev).then(() => cacheSlide(prev))
  if (next) void preloadMedia(next).then(() => cacheSlide(next))
}

async function playCurrentVideo() {
  await nextTick()
  const el = videoEl.value
  if (!el || current.value?.mediaType !== 'video') return
  el.currentTime = 0
  const wantSound = userWantsSound.value && !muted.value
  const result = await playVideoWithOptionalSound(el, wantSound)
  if (wantSound && result.muted) {
    muted.value = true
  } else if (!result.muted) {
    muted.value = false
  }
}

function onStoryVideoPause() {
  if (!paused.value) videoPlaying.value = false
}

async function toggleStoryMute() {
  const el = videoEl.value
  if (muted.value) {
    userWantsSound.value = true
    muted.value = false
    if (el) {
      const ok = await unmuteVideoOnUserGesture(el)
      if (!ok) {
        muted.value = true
        userWantsSound.value = false
      }
    }
  } else {
    userWantsSound.value = false
    muted.value = true
    if (el) el.muted = true
  }
}

async function onSlideChange() {
  clearTimer()
  progress.value = 0
  videoPlaying.value = false
  const slide = current.value
  if (!slide) return
  const cached = mediaCache.has(slide.id)
  if (!cached) {
    mediaReady.value = false
    await preloadMedia(slide)
    cacheSlide(slide)
  }
  mediaReady.value = true
  await playCurrentVideo()
  if (!paused.value) startProgress()
  void recordView()
  prefetchAdjacent()
}

async function loadSlidesForUser(uid, opts = {}) {
  const { startSlideId = null, startIndex = null, direction = null, initial = false } = opts
  if (initial) loading.value = true
  else userSwitching.value = true
  if (!mediaCache.size) mediaReady.value = false
  try {
    const { data } = await api.get(`/stories/user/${uid}`, { skipGlobalLoader: true })
    const list = (data ?? []).map(normalizeSlide)
    if (!list.length) {
      if (direction === 'prev') return false
      router.replace('/conversations')
      return false
    }
    slides.value = list
    if (startIndex != null) {
      index.value = Math.max(0, Math.min(startIndex, list.length - 1))
    } else if (startSlideId) {
      const idx = list.findIndex(s => String(s.id) === String(startSlideId))
      index.value = idx >= 0 ? idx : 0
    } else {
      index.value = direction === 'prev' ? list.length - 1 : 0
    }
    if (initial) loading.value = false
    await onSlideChange()
    return true
  } catch {
    router.replace('/conversations')
    return false
  } finally {
    loading.value = false
    userSwitching.value = false
  }
}

async function loadSlides(opts = {}) {
  const { initial = true, clearCache = true } = opts
  if (clearCache) mediaCache.clear()
  await loadSlidesForUser(userId.value, { startSlideId: route.query.slideId, initial })
}

async function switchToFeedUser(targetUid, direction) {
  if (transitioning.value || String(targetUid) === String(userId.value)) return
  transitioning.value = true
  slideDir.value = direction
  clearTimer()
  paused.value = false
  try {
    const ok = await loadSlidesForUser(targetUid, {
      direction,
      startIndex: direction === 'prev' ? undefined : 0
    })
    if (!ok) return
    if (String(route.params.userId) !== String(targetUid)) {
      skipNextRouteLoad.value = true
      const q = route.query.from ? { from: route.query.from } : {}
      await router.replace({ path: `/stories/view/${targetUid}`, query: q })
    }
  } finally {
    transitioning.value = false
    setTimeout(() => { slideDir.value = null }, 320)
  }
}

function feedUserIndex(uid) {
  return feedRings.value.findIndex(r => String(r.userId) === String(uid))
}

async function goToAdjacentUser(delta) {
  const i = feedUserIndex(userId.value)
  if (i < 0) {
    goBack()
    return
  }
  const target = feedRings.value[i + delta]
  if (!target) {
    if (delta > 0) goBack()
    return
  }
  await switchToFeedUser(target.userId, delta > 0 ? 'next' : 'prev')
}

function normalizeSlide(s) {
  return {
    id: s.id ?? s.Id,
    userId: s.userId ?? s.UserId,
    mediaUrl: s.mediaUrl ?? s.MediaUrl,
    mediaType: s.mediaType ?? s.MediaType ?? 'image',
    caption: s.caption ?? s.Caption,
    backgroundColor: s.backgroundColor ?? s.BackgroundColor,
    filterId: s.filterId ?? s.FilterId,
    videoDurationSeconds: s.videoDurationSeconds ?? s.VideoDurationSeconds,
    viewedByMe: s.viewedByMe ?? s.ViewedByMe
  }
}

async function recordView() {
  const slide = current.value
  if (!slide?.id || isOwner.value) return
  try {
    await api.post(`/stories/${slide.id}/view`, null, { skipGlobalLoader: true })
    storiesStore.markRingSeen(userId.value)
  } catch {}
}

function clearTimer() {
  if (timer) {
    clearInterval(timer)
    timer = null
  }
}

function startProgress() {
  clearTimer()
  progress.value = 0
  if (paused.value || !current.value) return
  const duration = current.value.mediaType === 'video'
    ? Math.min((current.value.videoDurationSeconds || 15) * 1000, 60000)
    : SLIDE_MS
  const step = 50
  timer = setInterval(() => {
    if (paused.value) return
    progress.value += (step / duration) * 100
    if (progress.value >= 100) nextSlide()
  }, step)
}

async function navigateSlide(direction) {
  if (transitioning.value || loading.value || userSwitching.value) return
  transitioning.value = true
  slideDir.value = direction
  clearTimer()
  try {
    if (direction === 'next') {
      if (index.value < slides.value.length - 1) {
        index.value++
        await onSlideChange()
      } else {
        await goToAdjacentUser(1)
      }
    } else if (index.value > 0) {
      index.value--
      await onSlideChange()
    } else {
      await goToAdjacentUser(-1)
    }
  } finally {
    transitioning.value = false
    setTimeout(() => { slideDir.value = null }, 320)
  }
}

async function nextSlide() {
  await navigateSlide('next')
}

async function prevSlide() {
  await navigateSlide('prev')
}

function goBack() {
  if (route.query.from === 'create') {
    router.replace('/stories/create')
    return
  }
  router.replace('/conversations')
}

function onTapZone(clientX) {
  const w = window.innerWidth
  const isRtl = localeStore.htmlDir === 'rtl'
  const inStart = clientX < w * 0.34
  const inEnd = clientX > w * 0.66
  if (isRtl) {
    if (inStart) void nextSlide()
    else if (inEnd) void prevSlide()
    else togglePause()
  } else {
    if (inStart) void prevSlide()
    else if (inEnd) void nextSlide()
    else togglePause()
  }
}

function onPointerDown(e) {
  if (showViewers.value || transitioning.value || userSwitching.value) return
  const t = e.touches?.[0] ?? e
  touchStartX = t.clientX
  touchStartY = t.clientY
  touchStartTime = Date.now()
  isDragging.value = true
  didSwipe = false
  dragX.value = 0
  clearTimer()
}

function onPointerMove(e) {
  if (!isDragging.value) return
  const t = e.touches?.[0] ?? e
  const dx = t.clientX - touchStartX
  const dy = t.clientY - touchStartY
  if (Math.abs(dy) > Math.abs(dx) * 1.2 && Math.abs(dy) > 24) return
  if (e.cancelable) e.preventDefault()
  dragX.value = dx
}

async function onPointerUp(e) {
  if (!isDragging.value) return
  isDragging.value = false
  const t = e.changedTouches?.[0] ?? e
  const dx = dragX.value
  const dy = (t.clientY ?? touchStartY) - touchStartY
  const dt = Date.now() - touchStartTime
  dragX.value = 0

  const threshold = window.innerWidth * SWIPE_RATIO
  const swipeLeft = dx < -threshold || (dx < -40 && dt < 280)
  const swipeRight = dx > threshold || (dx > 40 && dt < 280)

  if (Math.abs(dy) > Math.abs(dx) && dy > SWIPE_DOWN_MIN && dy > threshold) {
    didSwipe = true
    goBack()
    return
  }

  if (Math.abs(dx) > Math.abs(dy) && swipeLeft) {
    didSwipe = true
    await navigateSlide('next')
    return
  }
  if (Math.abs(dx) > Math.abs(dy) && swipeRight) {
    didSwipe = true
    await navigateSlide('prev')
    return
  }

  if (Math.abs(dx) < 12 && Math.abs(dy) < 12 && dt < 320 && !didSwipe) {
    onTapZone(t.clientX ?? touchStartX)
    return
  }

  if (!paused.value && mediaReady.value) startProgress()
}

function togglePause() {
  paused.value = !paused.value
  if (!paused.value) startProgress()
  else clearTimer()
}

async function sendReply() {
  const slide = current.value
  const text = replyText.value.trim()
  if (!slide?.id || !text || sending.value || isOwner.value) return
  sending.value = true
  try {
    const { data } = await api.post(`/stories/${slide.id}/reply`, { text })
    replyText.value = ''
    const convId = data?.conversationId ?? data?.ConversationId
    if (convId) router.push(`/conversation/${convId}`)
  } catch (e) {
    showStoryAlert(e.response?.data?.message ?? e.userMessage ?? t('common.error'))
  } finally {
    sending.value = false
  }
}

async function openViewers() {
  const slide = current.value
  if (!slide?.id || !isOwner.value) return
  showViewers.value = true
  try {
    const { data } = await api.get(`/stories/${slide.id}/viewers`)
    viewers.value = data ?? []
  } catch {
    viewers.value = []
  }
}

watch(
  () => route.params.userId,
  (id, prev) => {
    if (!id || id === prev) return
    if (skipNextRouteLoad.value) {
      skipNextRouteLoad.value = false
      return
    }
    mediaCache.clear()
    void loadSlides({ initial: false })
  }
)

onMounted(async () => {
  if (!storiesStore.loaded) await storiesStore.fetchFeed()
  await loadSlides()
})
onUnmounted(clearTimer)
</script>

<template>
  <div class="story-viewer page">
    <div v-if="loading" class="viewer-loading">{{ t('common.loading') }}</div>

    <template v-else-if="current">
      <div class="progress-row">
        <div
          v-for="(s, i) in slides"
          :key="s.id"
          class="progress-seg"
        >
          <div
            class="progress-fill"
            :style="{ width: i < index ? '100%' : i === index ? `${progress}%` : '0%' }"
          />
        </div>
      </div>

      <header class="viewer-header" @click.stop>
        <button type="button" class="icon-btn" @click="goBack"><X :size="22" /></button>
        <span class="viewer-name">{{ publisherName }}</span>
        <button
          v-if="current.mediaType === 'video'"
          type="button"
          class="icon-btn"
          aria-label="mute"
          @click="toggleStoryMute"
        >
          <VolumeX v-if="muted" :size="20" />
          <Volume2 v-else :size="20" />
        </button>
        <button type="button" class="icon-btn" :title="t('share.shareStory')" @click="shareCurrentStory">
          <Share2 :size="20" />
        </button>
        <button v-if="isOwner" type="button" class="icon-btn" @click="openViewers"><Eye :size="20" /></button>
        <span v-else-if="current?.mediaType !== 'video'" class="header-spacer" />
      </header>

      <div
        class="viewer-media"
        :class="{ 'is-dragging': isDragging }"
        :style="[
          current.mediaType === 'text'
            ? { background: current.backgroundColor || 'linear-gradient(135deg,#6c63ff,#ff6584)' }
            : {},
          mediaDragStyle
        ]"
        @touchstart="onPointerDown"
        @touchmove.prevent="onPointerMove"
        @touchend="onPointerUp"
        @touchcancel="onPointerUp"
        @mousedown="onPointerDown"
        @mousemove="onPointerMove"
        @mouseup="onPointerUp"
        @mouseleave="isDragging && onPointerUp($event)"
      >
        <div class="viewer-media-stage">
          <Transition :name="slideTransitionName">
            <div :key="`${userId}-${current.id}`" class="media-slide">
            <video
              v-if="current.mediaType === 'video' && current.mediaUrl"
              v-show="mediaReady"
              ref="videoEl"
              :src="ensureAbsoluteUrl(current.mediaUrl)"
              class="media-el"
              :class="{ 'media-el--playing': videoPlaying }"
              :style="filterStyle"
              playsinline
              webkit-playsinline
              x5-playsinline
              :muted="muted"
              preload="auto"
              disablepictureinpicture
              controlslist="nodownload nofullscreen noremoteplayback"
              @playing="videoPlaying = true"
              @pause="onStoryVideoPause"
            />
            <img
              v-else-if="current.mediaUrl"
              v-show="mediaReady"
              :src="ensureAbsoluteUrl(current.mediaUrl)"
              class="media-el"
              :style="filterStyle"
              alt=""
              decoding="async"
              fetchpriority="high"
            />
            <p v-else-if="current.caption" class="text-story">{{ current.caption }}</p>
            <p v-if="current.caption && current.mediaType !== 'text'" class="caption">{{ current.caption }}</p>
            </div>
          </Transition>
        </div>
        <div v-if="userSwitching" class="media-loading media-loading--overlay">
          {{ t('common.loading') }}
        </div>
        <div
          v-else-if="!mediaReady && !isDragging && current.mediaType !== 'text'"
          class="media-loading media-loading--overlay"
        >
          {{ t('common.loading') }}
        </div>
        <div v-if="paused && mediaReady && videoPlaying" class="pause-indicator" aria-hidden="true">
          <Pause :size="44" stroke-width="1.5" />
        </div>
      </div>

      <footer v-if="!isOwner" class="viewer-reply" @click.stop>
        <input
          v-model="replyText"
          type="text"
          class="reply-input"
          :placeholder="t('stories.replyPlaceholder')"
          @keydown.enter.prevent="sendReply"
        />
        <button type="button" class="reply-send" :disabled="sending || !replyText.trim()" @click="sendReply">
          <Send :size="18" />
        </button>
      </footer>
    </template>

    <Teleport to="body">
      <div v-if="showViewers" class="viewers-overlay" @click="showViewers = false">
        <div class="viewers-sheet" @click.stop>
          <h3>{{ t('stories.viewersTitle') }}</h3>
          <div v-if="!viewers.length" class="viewers-empty">{{ t('stories.noViewers') }}</div>
          <ul v-else class="viewers-list">
            <li v-for="v in viewers" :key="v.userId">
              <CachedAvatar v-if="v.avatar" :url="v.avatar" img-class="viewer-av" />
              <span>{{ v.name }}</span>
            </li>
          </ul>
          <button type="button" class="btn-close" @click="showViewers = false">{{ t('common.cancel') }}</button>
        </div>
      </div>
    </Teleport>

    <StoryDialog
      v-model:open="dialogOpen"
      mode="alert"
      variant="error"
      :message="dialogMessage"
      @confirm="closeStoryDialog"
      @cancel="closeStoryDialog"
    />
  </div>
</template>

<style scoped>
.story-viewer {
  position: fixed;
  inset: 0;
  z-index: 200;
  background: #000;
  color: #fff;
  display: flex;
  flex-direction: column;
  font-family: 'Cairo', sans-serif;
}

.viewer-loading,
.media-loading {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1;
  color: #fff;
  background: rgba(0, 0, 0, 0.35);
  pointer-events: none;
}

.progress-row {
  display: flex;
  gap: 4px;
  padding: calc(var(--safe-top) + 8px) 10px 0;
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  z-index: 3;
}

.progress-seg {
  flex: 1;
  height: 3px;
  background: rgba(255, 255, 255, 0.35);
  border-radius: 2px;
  overflow: hidden;
}

.progress-fill {
  height: 100%;
  background: #fff;
  transition: width 0.05s linear;
}

.viewer-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: calc(var(--safe-top) + 16px) 12px 8px;
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  z-index: 2;
  background: linear-gradient(to bottom, rgba(0, 0, 0, 0.5), transparent);
}

.viewer-name {
  flex: 1;
  font-weight: 600;
  font-size: 15px;
}

.icon-btn {
  background: rgba(0, 0, 0, 0.4);
  border: 1px solid rgba(255, 255, 255, 0.12);
  color: #fff;
  width: 38px;
  height: 38px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  transition: transform 0.12s ease, background 0.15s ease;
}

.icon-btn:active {
  transform: scale(0.96);
  background: rgba(0, 0, 0, 0.55);
}

.header-spacer {
  width: 36px;
}

.viewer-media {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  justify-content: center;
  min-height: 0;
  position: relative;
  overflow: hidden;
  background: #000;
  touch-action: pan-y pinch-zoom;
  transition: transform 0.25s cubic-bezier(0.25, 0.8, 0.25, 1);
}

.viewer-media.is-dragging {
  transition: none;
}

.viewer-media-stage {
  position: relative;
  flex: 1;
  width: 100%;
  min-height: 0;
  align-self: stretch;
  overflow: hidden;
}

.media-slide {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  position: absolute;
  inset: 0;
}

.pause-indicator {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 2;
  pointer-events: none;
  color: rgba(255, 255, 255, 0.92);
  background: rgba(0, 0, 0, 0.15);
}

.pause-indicator :deep(svg) {
  width: 44px;
  height: 44px;
  flex-shrink: 0;
}

.media-loading--overlay {
  z-index: 2;
}

/* انتقالات بين الشرائح */
.story-slide-next-enter-active,
.story-slide-next-leave-active,
.story-slide-prev-enter-active,
.story-slide-prev-leave-active,
.story-fade-enter-active,
.story-fade-leave-active {
  transition: transform 0.3s cubic-bezier(0.25, 0.8, 0.25, 1), opacity 0.28s ease;
}

.story-slide-next-leave-active,
.story-slide-prev-leave-active,
.story-fade-leave-active {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
}

.story-slide-next-enter-from {
  transform: translateX(100%);
  opacity: 0.35;
}
.story-slide-next-leave-to {
  transform: translateX(-28%);
  opacity: 0;
}

.story-slide-prev-enter-from {
  transform: translateX(-100%);
  opacity: 0.35;
}
.story-slide-prev-leave-to {
  transform: translateX(28%);
  opacity: 0;
}

.story-fade-enter-from,
.story-fade-leave-to {
  opacity: 0;
}

[dir='rtl'] .story-slide-next-enter-from {
  transform: translateX(-100%);
}
[dir='rtl'] .story-slide-next-leave-to {
  transform: translateX(28%);
}
[dir='rtl'] .story-slide-prev-enter-from {
  transform: translateX(100%);
}
[dir='rtl'] .story-slide-prev-leave-to {
  transform: translateX(-28%);
}

.media-el {
  display: block;
  max-width: 100%;
  max-height: 100%;
  width: auto;
  height: auto;
  object-fit: contain;
  object-position: center;
}

video.media-el {
  width: 100%;
  height: 100%;
  opacity: 0;
  transition: opacity 0.22s ease;
}

video.media-el.media-el--playing {
  opacity: 1;
}

.text-story {
  font-size: 22px;
  font-weight: 700;
  text-align: center;
  padding: 24px;
  line-height: 1.4;
}

.caption {
  position: absolute;
  bottom: 80px;
  left: 16px;
  right: 16px;
  text-align: center;
  font-size: 14px;
  text-shadow: 0 1px 4px rgba(0, 0, 0, 0.8);
}

.viewer-reply {
  display: flex;
  gap: 8px;
  padding: 12px 12px calc(12px + var(--safe-bottom));
  background: linear-gradient(to top, rgba(0, 0, 0, 0.6), transparent);
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
}

.reply-input {
  flex: 1;
  border: 1px solid rgba(255, 255, 255, 0.3);
  border-radius: 24px;
  padding: 10px 16px;
  background: rgba(0, 0, 0, 0.35);
  color: #fff;
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
}

.reply-send {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  border: none;
  background: var(--primary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.reply-send:disabled {
  opacity: 0.5;
}

.viewers-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  z-index: 300;
  display: flex;
  align-items: flex-end;
}

.viewers-sheet {
  width: 100%;
  max-height: 60vh;
  background: var(--bg-card);
  color: var(--text-primary);
  border-radius: var(--radius-lg) var(--radius-lg) 0 0;
  padding: 20px 16px calc(16px + var(--safe-bottom));
  box-shadow: 0 -8px 32px rgba(0, 0, 0, 0.2);
}

.viewers-sheet h3 {
  margin: 0 0 12px;
  font-size: 16px;
}

.viewers-list {
  list-style: none;
  max-height: 40vh;
  overflow-y: auto;
}

.viewers-list li {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 0;
  border-bottom: 1px solid var(--border);
}

.viewer-av {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  object-fit: cover;
}

.btn-close {
  margin-top: 12px;
  width: 100%;
  padding: 12px;
  border: none;
  border-radius: 999px;
  background: var(--bg-elevated);
  font-family: 'Cairo', sans-serif;
  font-weight: 600;
  cursor: pointer;
}
</style>

