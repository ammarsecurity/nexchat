<script setup>
import { ref, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { Plus } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useStoriesStore } from '../stores/stories'
import { useAuthStore } from '../stores/auth'
import CachedAvatar from './CachedAvatar.vue'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { captureVideoPoster, isVideoUrl } from '../utils/videoPoster'

const router = useRouter()
const { t } = useI18n()
const storiesStore = useStoriesStore()
const auth = useAuthStore()
const ringPosters = ref({})

function ringThumbSrc(ring) {
  if (!ring.latestThumbUrl) return null
  const abs = ensureAbsoluteUrl(ring.latestThumbUrl)
  if (isVideoUrl(ring.latestThumbUrl)) {
    return ringPosters.value[ring.userId] || null
  }
  return abs
}

async function loadRingPosters() {
  const rings = storiesStore.feed.filter(r => r.latestThumbUrl && isVideoUrl(r.latestThumbUrl))
  await Promise.all(
    rings.map(async (ring) => {
      if (ringPosters.value[ring.userId]) return
      const poster = await captureVideoPoster(ensureAbsoluteUrl(ring.latestThumbUrl))
      if (poster) {
        ringPosters.value = { ...ringPosters.value, [ring.userId]: poster }
      }
    })
  )
}

onMounted(async () => {
  await storiesStore.fetchFeed()
  void loadRingPosters()
})

watch(
  () => storiesStore.feed.map(r => `${r.userId}:${r.latestThumbUrl}`).join('|'),
  () => { void loadRingPosters() }
)

function openCreate() {
  router.push('/stories/create')
}

function openRing(ring) {
  if (ring.isMine && !ring.slideCount) {
    openCreate()
    return
  }
  router.push(`/stories/view/${ring.userId}`)
}

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))
</script>

<template>
  <div class="stories-strip">
    <div class="stories-scroll">
      <button type="button" class="story-ring story-ring--mine" @click="openCreate">
        <span class="ring-outer ring-outer--mine" :class="{ unseen: storiesStore.feed.some(r => r.isMine && r.hasUnseen) }">
          <span class="ring-inner">
            <CachedAvatar
              v-if="auth.avatar && isImageAvatar(auth.avatar)"
              :url="auth.avatar"
              img-class="ring-avatar-img"
            />
            <span v-else class="ring-letter">{{ auth.user?.name?.[0]?.toUpperCase() || '+' }}</span>
          </span>
          <span class="ring-add-badge" aria-hidden="true"><Plus :size="12" stroke-width="2.5" /></span>
        </span>
        <span class="ring-label">{{ t('stories.yourStory') }}</span>
      </button>

      <button
        v-for="ring in storiesStore.feed.filter(r => !r.isMine)"
        :key="ring.userId"
        type="button"
        class="story-ring"
        @click="openRing(ring)"
      >
        <span class="ring-outer" :class="{ unseen: ring.hasUnseen }">
          <span class="ring-inner">
            <img
              v-if="ringThumbSrc(ring)"
              :src="ringThumbSrc(ring)"
              class="ring-thumb"
              alt=""
            />
            <video
              v-else-if="ring.latestThumbUrl && isVideoUrl(ring.latestThumbUrl)"
              :src="ensureAbsoluteUrl(ring.latestThumbUrl)"
              class="ring-thumb ring-thumb-video"
              muted
              playsinline
              preload="metadata"
              @loadeddata="(e) => { try { e.target.currentTime = 0.1 } catch {} }"
            />
            <CachedAvatar
              v-else-if="ring.avatar && isImageAvatar(ring.avatar)"
              :url="ring.avatar"
              img-class="ring-avatar-img"
            />
            <span v-else class="ring-letter">{{ ring.name?.[0]?.toUpperCase() || '?' }}</span>
          </span>
        </span>
        <span class="ring-label">{{ ring.name }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.stories-strip {
  flex-shrink: 0;
  padding: 4px 0 2px;
  background: var(--wa-subbar, var(--bg-primary));
  border-bottom: 1px solid var(--border);
}
html.light .conversations--wa .stories-strip,
[data-theme="light"] .conversations--wa .stories-strip {
  background: var(--wa-subbar, #fff);
}

.stories-scroll {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding: 0 10px 4px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}
.stories-scroll::-webkit-scrollbar {
  display: none;
}

.story-ring {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 3px;
  min-width: 60px;
  max-width: 66px;
  background: none;
  border: none;
  padding: 0;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.story-ring--mine {
  position: relative;
  z-index: 2;
}

.story-ring--mine .ring-add-badge {
  width: 18px;
  height: 18px;
}

.ring-outer {
  position: relative;
  display: inline-flex;
  flex-shrink: 0;
  padding: 2px;
  border-radius: 50%;
  background: var(--border);
}

.ring-outer--mine {
  overflow: visible;
}
.ring-outer.unseen {
  background: linear-gradient(135deg, #6c63ff, #ff6584, #00d4ff);
}

.ring-inner {
  width: 50px;
  height: 50px;
  border-radius: 50%;
  overflow: hidden;
  background: var(--bg-elevated);
  display: block;
  position: relative;
  border: 2px solid var(--bg-primary);
  box-sizing: border-box;
}
html.light .ring-inner {
  border-color: #fff;
}

.ring-inner :deep(.ring-avatar-img),
.ring-thumb {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.ring-thumb-video {
  pointer-events: none;
  background: #111;
}

.ring-inner .ring-letter {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
}

.ring-letter {
  font-size: 18px;
  font-weight: 700;
  color: var(--primary);
}

.ring-add-badge {
  position: absolute;
  bottom: 0;
  inset-inline-end: 0;
  z-index: 3;
  width: 16px;
  height: 16px;
  border-radius: 50%;
  background: var(--primary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--bg-primary);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
  pointer-events: none;
}
html.light .ring-add-badge {
  border-color: #fff;
}

.ring-label {
  font-size: 12px;
  line-height: 1.2;
  color: var(--text-secondary);
  max-width: 68px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  text-align: center;
  font-family: 'Cairo', sans-serif;
}
</style>

