<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronRight, X, Eye, Send } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { useStoriesStore } from '../stores/stories'
import { useAuthStore } from '../stores/auth'
import CachedAvatar from '../components/CachedAvatar.vue'

const route = useRoute()
const router = useRouter()
const { t } = useI18n()
const storiesStore = useStoriesStore()
const auth = useAuthStore()

const userId = computed(() => route.params.userId)
const slides = ref([])
const loading = ref(true)
const mediaReady = ref(false)
const index = ref(0)
const progress = ref(0)
const paused = ref(false)
const replyText = ref('')
const sending = ref(false)
const showViewers = ref(false)
const viewers = ref([])

let timer = null
const SLIDE_MS = 5000

const current = computed(() => slides.value[index.value])
const isOwner = computed(() => String(userId.value) === String(auth.user?.id))
const publisherName = computed(() => storiesStore.feed.find(r => String(r.userId) === String(userId.value))?.name ?? '—')

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

function prefetchAdjacent() {
  const next = slides.value[index.value + 1]
  if (next) void preloadMedia(next)
}

async function onSlideChange() {
  clearTimer()
  progress.value = 0
  mediaReady.value = false
  const slide = current.value
  if (!slide) return
  await preloadMedia(slide)
  mediaReady.value = true
  startProgress()
  void recordView()
  prefetchAdjacent()
}

async function loadSlides() {
  loading.value = true
  mediaReady.value = false
  try {
    const { data } = await api.get(`/stories/user/${userId.value}`, { skipGlobalLoader: true })
    slides.value = (data ?? []).map(normalizeSlide)
    if (!slides.value.length) {
      router.replace('/conversations')
      return
    }
    const startId = route.query.slideId
    if (startId) {
      const idx = slides.value.findIndex(s => String(s.id) === String(startId))
      index.value = idx >= 0 ? idx : 0
    } else {
      index.value = 0
    }
    loading.value = false
    await onSlideChange()
  } catch {
    router.replace('/conversations')
  } finally {
    loading.value = false
  }
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

async function nextSlide() {
  if (index.value < slides.value.length - 1) {
    index.value++
    await onSlideChange()
  } else {
    goBack()
  }
}

async function prevSlide() {
  if (index.value > 0) {
    index.value--
    await onSlideChange()
  }
}

function goBack() {
  if (route.query.from === 'create') {
    router.replace('/stories/create')
    return
  }
  router.replace('/conversations')
}

function onTap(e) {
  const w = window.innerWidth
  const x = e.clientX ?? e.changedTouches?.[0]?.clientX ?? w / 2
  if (x < w * 0.35) prevSlide()
  else if (x > w * 0.65) nextSlide()
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
    window.alert(e.response?.data?.message ?? e.userMessage ?? t('common.error'))
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

onMounted(loadSlides)
onUnmounted(clearTimer)
</script>

<template>
  <div class="story-viewer page" @click="onTap">
    <div v-if="loading" class="viewer-loading">{{ t('common.loading') }}</div>

    <template v-else-if="current">
      <div v-if="!mediaReady" class="media-loading">{{ t('common.loading') }}</div>
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
        <button v-if="isOwner" type="button" class="icon-btn" @click="openViewers"><Eye :size="20" /></button>
        <span v-else class="header-spacer" />
      </header>

      <div
        class="viewer-media"
        :style="current.mediaType === 'text' ? { background: current.backgroundColor || 'linear-gradient(135deg,#6c63ff,#ff6584)' } : {}"
        @click.stop="togglePause"
      >
        <video
          v-if="current.mediaType === 'video' && current.mediaUrl"
          v-show="mediaReady"
          :key="`v-${current.id}`"
          :src="ensureAbsoluteUrl(current.mediaUrl)"
          class="media-el"
          :style="filterStyle"
          autoplay
          playsinline
          muted
          preload="auto"
        />
        <img
          v-else-if="current.mediaUrl"
          v-show="mediaReady"
          :key="`i-${current.id}`"
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
  background: rgba(0, 0, 0, 0.35);
  border: none;
  color: #fff;
  width: 36px;
  height: 36px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.header-spacer {
  width: 36px;
}

.viewer-media {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 0;
  position: relative;
}

.media-el {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
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
  border-radius: 16px 16px 0 0;
  padding: 20px 16px calc(16px + var(--safe-bottom));
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
  border-radius: 12px;
  background: var(--bg-elevated);
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}
</style>

