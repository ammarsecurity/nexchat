<script setup>
import { ref, watch, onUnmounted } from 'vue'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { getCachedAvatarUrl, saveAvatarToCache } from '../services/cache'

const props = defineProps({
  /** Avatar URL (relative or absolute) - image URL only; emoji/letter handled by parent */
  url: { type: String, default: null },
  /** CSS class for the img */
  imgClass: { type: String, default: 'avatar-img' }
})

function isImageUrl(u) {
  return u && (u.startsWith('http') || u.startsWith('/'))
}

/** تجنّب CORS: لا نستدعي fetch للصور من مصدر آخر (مثلاً API على دومين مختلف عن التطبيق). */
function isCrossOrigin(url) {
  if (!url || !url.startsWith('http')) return false
  try {
    return new URL(url).origin !== (typeof location !== 'undefined' ? location.origin : '')
  } catch {
    return true
  }
}

const effectiveSrc = ref(null)
const loadedFromCache = ref(false)
let revokedBlobUrl = null

async function loadAvatar() {
  const u = props.url
  if (!u || !isImageUrl(u)) {
    effectiveSrc.value = null
    return
  }
  const absolute = ensureAbsoluteUrl(u)
  if (revokedBlobUrl) {
    try { URL.revokeObjectURL(revokedBlobUrl) } catch {}
    revokedBlobUrl = null
  }
  try {
    const cached = await getCachedAvatarUrl(absolute)
    if (cached && cached.startsWith('blob:')) {
      effectiveSrc.value = cached
      revokedBlobUrl = cached
      loadedFromCache.value = true
    } else {
      effectiveSrc.value = absolute
      loadedFromCache.value = false
    }
  } catch {
    effectiveSrc.value = absolute
    loadedFromCache.value = false
  }
}

async function onImageLoad() {
  if (loadedFromCache.value) return
  const src = effectiveSrc.value
  if (!src || !src.startsWith('http')) return
  if (isCrossOrigin(src)) return // لا fetch لصور من مصدر آخر → لا CORS error، الصورة تظهر عبر <img> فقط
  try {
    const token = typeof localStorage !== 'undefined' ? localStorage.getItem('nexchat_token') : null
    const res = await fetch(src, {
      credentials: 'include',
      headers: token ? { Authorization: `Bearer ${token}` } : {}
    })
    if (!res.ok) return
    const blob = await res.blob()
    await saveAvatarToCache(src, blob)
  } catch {
    // شبكة ضعيفة أو مقطوعة - لا نكرر المحاولة
  }
}

watch(() => props.url, loadAvatar, { immediate: true })

onUnmounted(() => {
  if (revokedBlobUrl) {
    try { URL.revokeObjectURL(revokedBlobUrl) } catch {}
  }
})
</script>

<template>
  <img
    v-if="effectiveSrc"
    :src="effectiveSrc"
    :class="imgClass"
    referrerpolicy="no-referrer"
    loading="lazy"
    @load="onImageLoad"
  />
</template>
