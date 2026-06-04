<script setup>
import { computed } from 'vue'
import { ensureAbsoluteUrl } from '../utils/imageUrl'

const props = defineProps({
  urls: { type: Array, required: true }
})

const emit = defineEmits(['open'])

const displayUrls = computed(() => (props.urls || []).slice(0, 4))
const extraCount = computed(() => Math.max(0, (props.urls?.length || 0) - 4))
const gridClass = computed(() => {
  const n = displayUrls.value.length
  if (n <= 1) return 'album-grid--1'
  if (n === 2) return 'album-grid--2'
  if (n === 3) return 'album-grid--3'
  return 'album-grid--4'
})

function onTileClick(index) {
  emit('open', index)
}
</script>

<template>
  <div class="album-bubble" :class="gridClass">
    <button
      v-for="(url, i) in displayUrls"
      :key="url + i"
      type="button"
      class="album-tile"
      @click.stop="onTileClick(i)"
    >
      <img :src="ensureAbsoluteUrl(url)" alt="" class="album-tile__img" referrerpolicy="no-referrer" />
      <span v-if="i === 3 && extraCount > 0" class="album-tile__more">+{{ extraCount }}</span>
    </button>
  </div>
</template>

<style scoped>
.album-bubble {
  display: grid;
  gap: 3px;
  max-width: min(280px, 72vw);
  border-radius: 12px;
  overflow: hidden;
}

.album-grid--1 {
  grid-template-columns: 1fr;
}

.album-grid--2 {
  grid-template-columns: 1fr 1fr;
}

.album-grid--3 {
  grid-template-columns: 1fr 1fr;
  grid-template-rows: 1fr 1fr;
}

.album-grid--3 .album-tile:first-child {
  grid-row: span 2;
}

.album-grid--4 {
  grid-template-columns: 1fr 1fr;
  grid-template-rows: 1fr 1fr;
}

.album-tile {
  position: relative;
  padding: 0;
  border: none;
  background: var(--bg-elevated);
  aspect-ratio: 1;
  overflow: hidden;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.album-tile__img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.album-tile__more {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.55);
  color: #fff;
  font-size: 22px;
  font-weight: 700;
  font-family: 'Cairo', sans-serif;
}
</style>
