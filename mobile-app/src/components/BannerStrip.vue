<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { ensureAbsoluteUrl } from '../utils/imageUrl'

const props = defineProps({
  placement: { type: String, required: true }
})

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
  return b.length ? [...b, ...b] : []
})

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
  if (!scrollEl.value || isUserInteracting.value || bannersDoubled.value.length <= 1) {
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
  if (bannersDoubled.value.length > 1) {
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
  if (val.length > 1) startTicker()
}, { immediate: true })
</script>

<template>
  <div v-if="bannersDoubled.length" class="banner-strip">
    <div
      ref="scrollEl"
      class="banner-scroll"
      @touchstart="onUserInteractionStart"
      @touchend="onUserInteractionEnd"
      @touchcancel="onUserInteractionEnd"
      @mousedown="onUserInteractionStart"
      @mouseup="onUserInteractionEnd"
      @mouseleave="onUserInteractionEnd"
    >
      <div
        v-for="(b, i) in bannersDoubled"
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
  margin: var(--spacing);
  overflow: hidden;
}

.banner-scroll {
  display: flex;
  gap: 12px;
  overflow-x: auto;
  padding: 4px 0;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
  cursor: grab;
  user-select: none;
}
.banner-scroll:active {
  cursor: grabbing;
}
.banner-scroll::-webkit-scrollbar {
  display: none;
}

.banner-item {
  flex-shrink: 0;
  width: 280px;
  height: 120px;
  border-radius: var(--radius);
  overflow: hidden;
  background: var(--bg-card);
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
</style>
