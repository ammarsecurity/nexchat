<script setup>
import { computed } from 'vue'
import { ensureAbsoluteUrl } from '../utils/imageUrl'

const props = defineProps({
  /** Avatar URL (relative or absolute) - image URL only; emoji/letter handled by parent */
  url: { type: String, default: null },
  /** CSS class for the img */
  imgClass: { type: String, default: 'avatar-img' }
})

function isImageUrl(u) {
  return u && (u.startsWith('http') || u.startsWith('/'))
}

const displayUrl = computed(() => {
  if (!props.url || !isImageUrl(props.url)) return null
  return ensureAbsoluteUrl(props.url)
})
</script>

<template>
  <img
    v-if="displayUrl"
    :src="displayUrl"
    :class="imgClass"
    referrerpolicy="no-referrer"
    loading="lazy"
  />
</template>
