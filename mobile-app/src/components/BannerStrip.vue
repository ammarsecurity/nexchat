<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { useLayoutMode } from '../composables/useLayoutMode'

const props = defineProps({
  placement: { type: String, required: true }
})

const { isDesktop } = useLayoutMode()

const banners = ref([])
const loading = ref(false)
const scrollEl = ref(null)
const isUserInteracting = ref(false)
const resumeTimeout = ref(null)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

const SCROLL_SPEED = 0.8

let rafId = null

const bannersDoubled = computed(() => {
  const b = banners.value
  if (!b.length) return []
  if (b.length === 1) return b
  return [...b, ...b]
})

/** Desktop: unique banners in a grid; mobile: duplicated strip for auto-scroll */
const displayBanners = computed(() => {
  const b = banners.value
  if (!b.length) return []
  return isDesktop.value ? b : bannersDoubled.value
})

const isSingleBanner = computed(() => banners.value.length === 1)

async function fetchBanners() {
  loading.value = true
  try {
    const res = await fetch(`${API_BASE}/banners?placement=${props.placement}`)
    const data = await res.json()
    banners.value = Array.isArray(data) ? data : []
  } catch {
    banners.value = []
  } finally {
    loading.value = false
  }
}

function openLink(link) {
  if (link && link.startsWith('http')) {
    window.open(link, '_blank')
  }
}

function tick() {
  if (!scrollEl.value || isUserInteracting.value || banners.value.length <= 1) {
    rafId = requestAnimationFrame(tick)
    return
  }
  const el = scrollEl.value
  const halfWidth = el.scrollWidth / 2
  let next = el.scrollLeft + SCROLL_SPEED
  if (next >= halfWidth) next = 0
  el.scrollLeft = next
  rafId = requestAnimationFrame(tick)
}

function startTicker() {
  stopTicker()
  if (banners.value.length > 1) {
    rafId = requestAnimationFrame(tick)
  }
}

function stopTicker() {
  if (rafId) {
    cancelAnimationFrame(rafId)
    rafId = null
  }
}

function onUserInteractionStart() {
  isUserInteracting.value = true
  if (resumeTimeout.value) {
    clearTimeout(resumeTimeout.value)
    resumeTimeout.value = null
  }
}

function onUserInteractionEnd() {
  resumeTimeout.value = setTimeout(() => {
    isUserInteracting.value = false
    resumeTimeout.value = null
  }, 800)
}

onMounted(fetchBanners)
onUnmounted(() => {
  stopTicker()
  if (resumeTimeout.value) clearTimeout(resumeTimeout.value)
})
watch(() => props.placement, fetchBanners)
watch(bannersDoubled, (val) => {
  if (isDesktop.value || banners.value.length <= 1) stopTicker()
  else if (val.length > 1) startTicker()
}, { immediate: true })

watch(isDesktop, (desktop) => {
  if (desktop) stopTicker()
  else if (banners.value.length > 1) startTicker()
})
</script>

<template>
  <div
    v-if="displayBanners.length"
    class="banner-strip"
    :class="{
      'single-banner': isSingleBanner,
      'banner-strip--desktop': isDesktop
    }"
  >
    <div
      ref="scrollEl"
      class="banner-scroll"
      :class="{
        'single-banner-scroll': isSingleBanner,
        'banner-scroll--desktop': isDesktop
      }"
      @touchstart="onUserInteractionStart"
      @touchend="onUserInteractionEnd"
      @touchcancel="onUserInteractionEnd"
      @mousedown="onUserInteractionStart"
      @mouseup="onUserInteractionEnd"
      @mouseleave="onUserInteractionEnd"
    >
      <div
        v-for="(b, i) in displayBanners"
        :key="`${b.id}-${i}`"
        class="banner-item"
        :class="{ clickable: b.link }"
        @click="b.link && openLink(b.link)"
      >
        <img :src="ensureAbsoluteUrl(b.imageUrl)" :alt="''" loading="lazy" referrerpolicy="no-referrer" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.banner-strip {
  flex-shrink: 0;
  overflow: hidden;
  width: calc(100% - 2 * var(--spacing));
  max-width: var(--app-max-width, 100%);
  margin-block: var(--spacing);
  margin-inline: auto;
  box-sizing: border-box;
}

.banner-strip.single-banner {
  display: flex;
  justify-content: center;
}

.banner-scroll {
  display: flex;
  gap: clamp(8px, 2vw, 14px);
  overflow-x: auto;
  padding: 4px 0;
  direction: ltr;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
  cursor: grab;
  user-select: none;
  width: 100%;
}

.banner-scroll.single-banner-scroll {
  overflow: hidden;
  cursor: default;
  justify-content: center;
}
.banner-scroll.single-banner-scroll:active {
  cursor: default;
}

.banner-scroll:active {
  cursor: grabbing;
}
.banner-scroll::-webkit-scrollbar {
  display: none;
}

.banner-item {
  flex-shrink: 0;
  width: clamp(200px, 78vw, 280px);
  aspect-ratio: 280 / 120;
  height: auto;
  max-height: 140px;
  border-radius: var(--radius);
  overflow: hidden;
  background: var(--bg-card);
}

.banner-strip.single-banner .banner-item {
  width: min(100%, 320px);
  max-width: 100%;
}

.banner-item img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.banner-item.clickable {
  cursor: pointer;
  transition: opacity 0.2s;
}
.banner-item.clickable:active {
  opacity: 0.9;
}

@media (min-width: 480px) {
  .banner-item {
    width: clamp(240px, 42vw, 320px);
  }
  .banner-strip.single-banner .banner-item {
    width: min(100%, 400px);
  }
}

@media (min-width: 768px) {
  .banner-item {
    width: clamp(280px, 38vw, 400px);
    max-height: 168px;
  }
  .banner-strip.single-banner .banner-item {
    width: min(100%, 520px);
  }
}

@media (min-width: 1024px) {
  .banner-strip.banner-strip--desktop {
    width: 100%;
    max-width: var(--content-max, 1200px);
    margin-inline: auto;
    margin-block: var(--spacing-lg) var(--spacing);
    padding-inline: var(--spacing);
  }

  .banner-strip.banner-strip--desktop.single-banner {
    display: block;
  }

  .banner-scroll.banner-scroll--desktop {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(100%, 360px), 1fr));
    gap: var(--spacing);
    overflow: visible;
    cursor: default;
    padding: 0;
    direction: inherit;
  }

  .banner-strip--desktop.single-banner .banner-scroll--desktop {
    grid-template-columns: 1fr;
    max-width: 960px;
    margin-inline: auto;
  }

  .banner-strip--desktop .banner-item {
    width: 100%;
    max-width: none;
    max-height: none;
    aspect-ratio: 21 / 8;
    min-height: 140px;
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-card);
    border: 1px solid var(--border);
    transition: transform var(--motion-fast), box-shadow var(--motion-fast);
  }

  .banner-strip--desktop .banner-item.clickable {
    cursor: pointer;
  }

  .banner-strip--desktop .banner-item.clickable:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 24px rgba(15, 23, 42, 0.12);
  }

  .banner-strip--desktop .banner-item.clickable:active {
    opacity: 1;
    transform: translateY(0);
  }

  .banner-strip--desktop.single-banner .banner-item {
    aspect-ratio: 21 / 7;
    min-height: 160px;
  }
}
</style>
