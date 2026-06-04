<script setup>
import { ref, computed, onMounted, watch } from 'vue'
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

const props = defineProps({
  variant: { type: String, default: 'default' }
})

const isHero = computed(() => props.variant === 'hero')
const skeletonCount = computed(() => (isHero.value ? 5 : 6))
const showStoriesLoading = computed(() => storiesStore.loading)
</script>

<template>
  <div class="stories-strip" :class="{ 'stories-strip--hero': variant === 'hero' }">
    <div
      class="stories-scroll"
      :class="{ 'stories-scroll--loading': showStoriesLoading }"
      :aria-busy="showStoriesLoading"
      :aria-label="showStoriesLoading ? t('stories.loadingFeed') : undefined"
    >
      <template v-if="showStoriesLoading">
        <div
          v-for="i in skeletonCount"
          :key="`sk-${i}`"
          class="story-ring-skeleton"
          :class="{ 'story-ring-skeleton--hero': isHero }"
          aria-hidden="true"
        >
          <div class="story-skeleton-ring skeleton-shimmer" />
          <div class="story-skeleton-label skeleton-shimmer" />
        </div>
      </template>

      <template v-else>
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
      </template>
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
  background: linear-gradient(145deg, #2563EB, #60A5FA);
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

/* داخل بطاقة المحادثات الزرقاء */
.stories-strip--hero {
  padding: 2px 0 6px;
  background: transparent;
  border-bottom: none;
}

.stories-strip--hero .stories-scroll {
  padding: 0 2px 2px;
  gap: 10px;
}

.stories-strip--hero .story-ring {
  min-width: 52px;
  max-width: 56px;
  gap: 2px;
}

.stories-strip--hero .ring-inner {
  width: 42px;
  height: 42px;
  border-color: rgba(255, 255, 255, 0.92);
}

.stories-strip--hero .ring-add-badge {
  width: 14px;
  height: 14px;
}

.stories-strip--hero .story-ring--mine .ring-add-badge {
  width: 16px;
  height: 16px;
}

.stories-strip--hero .ring-label {
  color: rgba(255, 255, 255, 0.95);
  font-weight: 600;
  font-size: 10px;
  max-width: 56px;
}

.stories-strip--hero .ring-outer {
  background: rgba(255, 255, 255, 0.28);
}

.stories-strip--hero .ring-outer.unseen {
  background: linear-gradient(145deg, #FFFFFF 0%, #BFDBFE 55%, #60A5FA 100%);
}

.stories-strip--hero .ring-outer--mine .ring-inner {
  border: 2px dashed rgba(255, 255, 255, 0.88);
  background: rgba(255, 255, 255, 0.12);
}

.stories-strip--hero .ring-letter {
  font-size: 15px;
  color: #fff;
}

.stories-strip--hero .ring-add-badge {
  background: #fff;
  color: #2563EB;
  border-color: rgba(255, 255, 255, 0.95);
}

.story-ring-skeleton {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 3px;
  min-width: 60px;
  max-width: 66px;
  flex-shrink: 0;
}

.story-ring-skeleton--hero {
  min-width: 52px;
  max-width: 56px;
  gap: 2px;
}

.story-skeleton-ring {
  width: 54px;
  height: 54px;
  border-radius: 50%;
  flex-shrink: 0;
}

.story-ring-skeleton--hero .story-skeleton-ring {
  width: 46px;
  height: 46px;
}

.story-skeleton-label {
  width: 48px;
  height: 10px;
  border-radius: 6px;
}

.story-ring-skeleton--hero .story-skeleton-label {
  width: 40px;
  height: 8px;
}

.stories-strip--hero .story-skeleton-ring.skeleton-shimmer,
.stories-strip--hero .story-skeleton-label.skeleton-shimmer {
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 0.14) 0%,
    rgba(255, 255, 255, 0.34) 45%,
    rgba(255, 255, 255, 0.14) 90%
  );
  background-size: 200% 100%;
}
</style>

