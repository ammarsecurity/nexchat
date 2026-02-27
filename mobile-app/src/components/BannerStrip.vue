<script setup>
import { ref, onMounted, watch } from 'vue'
import { ensureAbsoluteUrl } from '../utils/imageUrl'

const props = defineProps({
  placement: { type: String, required: true }
})

const banners = ref([])
const loading = ref(false)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

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

onMounted(fetchBanners)
watch(() => props.placement, fetchBanners)
</script>

<template>
  <div v-if="banners.length" class="banner-strip">
    <div class="banner-scroll">
      <div
        v-for="b in banners"
        :key="b.id"
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
  scroll-snap-type: x mandatory;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
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
  scroll-snap-align: start;
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
