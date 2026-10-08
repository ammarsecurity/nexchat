<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import api from '../services/api'
import { fullMediaUrl } from '../utils/media'
import {
  parseAlbumUrls,
  parseShortFilm,
  parseStoryShare,
  parseCall,
  parseLocation,
  parseFile,
  formatCallLabel,
  callIcon
} from '../utils/messageContent'

const props = defineProps({
  type: { type: String, default: 'text' },
  content: { type: String, default: '' },
  isViewOnce: { type: Boolean, default: false },
  viewOnceOpenCount: { type: Number, default: 0 },
  messageId: { type: String, default: '' }
})

const normalizedType = computed(() => (props.type || 'text').toLowerCase())

const viewOnceLabel = computed(() => {
  if (!props.isViewOnce) return ''
  if (props.viewOnceOpenCount > 0) return 'مشاهدة مرة واحدة · تم الفتح'
  return 'مشاهدة مرة واحدة'
})

const isPrivateMedia = computed(() =>
  typeof props.content === 'string' && props.content.startsWith('/api/media/private/')
)

const mediaSrc = computed(() => fullMediaUrl(props.content))

/** Authenticated blob URL for view-once / private files (admin JWT). */
const adminBlobUrl = ref('')
const adminBlobLoading = ref(false)
const adminBlobError = ref(false)

async function loadAdminMediaBlob() {
  if (adminBlobUrl.value) {
    URL.revokeObjectURL(adminBlobUrl.value)
    adminBlobUrl.value = ''
  }
  adminBlobError.value = false
  if (!props.messageId) return
  const needsAdminFetch =
    props.isViewOnce ||
    isPrivateMedia.value
  if (!needsAdminFetch) return

  adminBlobLoading.value = true
  try {
    const res = await api.get(`/admin/media/message/${props.messageId}`, { responseType: 'blob' })
    adminBlobUrl.value = URL.createObjectURL(res.data)
  } catch {
    adminBlobError.value = true
  } finally {
    adminBlobLoading.value = false
  }
}

watch(
  () => [props.messageId, props.isViewOnce, props.content],
  () => { loadAdminMediaBlob() },
  { immediate: true }
)

onBeforeUnmount(() => {
  if (adminBlobUrl.value) URL.revokeObjectURL(adminBlobUrl.value)
})

const resolvedMediaSrc = computed(() => adminBlobUrl.value || mediaSrc.value)

const albumUrls = computed(() => {
  if (normalizedType.value !== 'album') return null
  const urls = parseAlbumUrls(props.content)
  return urls ? urls.map(fullMediaUrl) : null
})

const shortFilm = computed(() => {
  if (normalizedType.value === 'short_film') return parseShortFilm(props.content)
  // Some older shares may arrive as text JSON
  if (normalizedType.value === 'text') {
    const sf = parseShortFilm(props.content)
    if (sf && (sf.id || sf.title || sf.thumbnailUrl)) return sf
  }
  return null
})

const storyShare = computed(() => {
  if (normalizedType.value === 'story_share') return parseStoryShare(props.content)
  return null
})

const call = computed(() => {
  if (normalizedType.value === 'call') return parseCall(props.content)
  if (normalizedType.value === 'text' && parseCall(props.content)) return parseCall(props.content)
  return null
})

const location = computed(() => {
  if (normalizedType.value === 'location') return parseLocation(props.content)
  return null
})

const fileMsg = computed(() => {
  if (normalizedType.value === 'file') return parseFile(props.content)
  return null
})

const callLabel = computed(() => (call.value ? formatCallLabel(props.content) : ''))
const callMdi = computed(() => (call.value ? callIcon(props.content) : 'mdi-phone'))

const showImage = computed(() => normalizedType.value === 'image' && props.content)
const showVideo = computed(() => normalizedType.value === 'video' && props.content)
const showAudio = computed(() => normalizedType.value === 'audio' && props.content)
const showViewOnceBadge = computed(() => props.isViewOnce && (normalizedType.value === 'image' || normalizedType.value === 'video'))
const showText = computed(() => {
  if (showImage.value || showVideo.value || showAudio.value) return false
  if (albumUrls.value) return false
  if (shortFilm.value) return false
  if (storyShare.value) return false
  if (call.value) return false
  if (location.value) return false
  if (fileMsg.value) return false
  return true
})
</script>

<template>
  <div class="admin-msg-body">
    <div v-if="viewOnceLabel" class="msg-view-once-badge">
      <v-icon size="16" color="primary">mdi-eye</v-icon>
      <span>{{ viewOnceLabel }}</span>
      <span v-if="showViewOnceBadge" class="msg-view-once-type">
        · {{ normalizedType === 'video' ? 'فيديو' : 'صورة' }}
      </span>
    </div>

    <div v-if="adminBlobLoading" class="msg-media-loading text-caption text-medium-emphasis">
      جاري تحميل الوسائط…
    </div>
    <div v-else-if="adminBlobError && (isViewOnce || isPrivateMedia)" class="msg-media-loading text-caption text-error">
      تعذر تحميل الملف
    </div>

    <!-- Image (including view-once for admins) -->
    <a
      v-if="showImage && resolvedMediaSrc"
      :href="resolvedMediaSrc"
      target="_blank"
      rel="noopener"
      class="msg-media-link"
    >
      <img :src="resolvedMediaSrc" alt="صورة" class="msg-thumb" loading="lazy" />
    </a>

    <!-- Video -->
    <div v-else-if="showVideo && resolvedMediaSrc" class="msg-video-wrap">
      <video :src="resolvedMediaSrc" controls preload="metadata" class="msg-video" />
      <a :href="resolvedMediaSrc" target="_blank" rel="noopener" class="msg-open-link">
        <v-icon size="16">mdi-open-in-new</v-icon>
        فتح الفيديو
      </a>
    </div>

    <!-- Voice / audio -->
    <div v-else-if="showAudio" class="msg-audio-wrap">
      <div class="msg-audio-label">
        <v-icon size="18" color="primary">mdi-microphone</v-icon>
        <span>رسالة صوتية</span>
      </div>
      <audio :src="resolvedMediaSrc" controls preload="metadata" class="msg-audio" />
    </div>

    <!-- Album -->
    <div v-else-if="albumUrls?.length" class="msg-album">
      <a
        v-for="(u, i) in albumUrls"
        :key="i"
        :href="u"
        target="_blank"
        rel="noopener"
        class="msg-album-item"
      >
        <img :src="u" :alt="`صورة ${i + 1}`" loading="lazy" />
      </a>
    </div>

    <!-- Short film share -->
    <div v-else-if="shortFilm" class="msg-short-film">
      <img
        v-if="shortFilm.thumbnailUrl"
        :src="fullMediaUrl(shortFilm.thumbnailUrl)"
        alt=""
        class="msg-sf-thumb"
        loading="lazy"
      />
      <div class="msg-sf-meta">
        <v-icon size="18" color="primary">mdi-movie-open</v-icon>
        <span class="msg-sf-title">{{ shortFilm.title || 'فيلم قصير' }}</span>
      </div>
    </div>

    <!-- Story share -->
    <div v-else-if="storyShare" class="msg-short-film">
      <img
        v-if="storyShare.mediaUrl && storyShare.mediaType !== 'text'"
        :src="fullMediaUrl(storyShare.mediaUrl)"
        alt=""
        class="msg-sf-thumb"
        loading="lazy"
      />
      <div class="msg-sf-meta">
        <v-icon size="18" color="primary">mdi-circle-outline</v-icon>
        <span class="msg-sf-title">ستوري {{ storyShare.name }}</span>
      </div>
    </div>

    <!-- Call -->
    <div v-else-if="call" class="msg-call">
      <v-icon size="20" :color="call.status === 'ended' ? 'primary' : 'error'">{{ callMdi }}</v-icon>
      <span>{{ callLabel }}</span>
    </div>

    <!-- Location -->
    <a
      v-else-if="location"
      :href="location.mapsUrl"
      target="_blank"
      rel="noopener"
      class="msg-call"
    >
      <v-icon size="20" color="primary">mdi-map-marker</v-icon>
      <span>{{ location.name }}</span>
    </a>

    <!-- File -->
    <a
      v-else-if="fileMsg"
      :href="fullMediaUrl(fileMsg.url)"
      target="_blank"
      rel="noopener"
      class="msg-call"
    >
      <v-icon size="20" color="primary">mdi-file-document-outline</v-icon>
      <span>{{ fileMsg.name }}</span>
    </a>

    <!-- Plain text -->
    <div v-else-if="showText" class="msg-text">{{ content || '—' }}</div>
  </div>
</template>

<style scoped>
.admin-msg-body {
  min-width: 0;
}

.msg-view-once-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 700;
  color: #6366f1;
  margin-bottom: 8px;
}

.msg-view-once-type {
  font-weight: 600;
  opacity: 0.85;
}

.msg-text {
  font-size: 14px;
  line-height: 1.5;
  word-break: break-word;
  white-space: pre-wrap;
}

.msg-media-link {
  display: block;
  max-width: 280px;
}

.msg-thumb {
  display: block;
  max-width: 100%;
  max-height: 260px;
  border-radius: 12px;
  object-fit: cover;
  background: rgba(15, 23, 42, 0.04);
}

.msg-video-wrap {
  display: flex;
  flex-direction: column;
  gap: 6px;
  max-width: 320px;
}

.msg-video {
  width: 100%;
  max-height: 280px;
  border-radius: 12px;
  background: #0f172a;
}

.msg-open-link {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  color: #0ea5e9;
  text-decoration: none;
}
.msg-open-link:hover {
  text-decoration: underline;
}

.msg-audio-wrap {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-width: 220px;
}

.msg-audio-label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  font-weight: 600;
  color: #64748b;
}

.msg-audio {
  width: 100%;
  max-width: 280px;
  height: 36px;
}

.msg-album {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(72px, 1fr));
  gap: 6px;
  max-width: 280px;
}

.msg-album-item {
  display: block;
  aspect-ratio: 1;
  border-radius: 8px;
  overflow: hidden;
  background: rgba(15, 23, 42, 0.06);
}

.msg-album-item img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.msg-short-film {
  display: flex;
  flex-direction: column;
  gap: 8px;
  max-width: 260px;
}

.msg-sf-thumb {
  width: 100%;
  max-height: 180px;
  object-fit: cover;
  border-radius: 12px;
  background: rgba(15, 23, 42, 0.06);
}

.msg-sf-meta {
  display: flex;
  align-items: center;
  gap: 6px;
}

.msg-sf-title {
  font-size: 13px;
  font-weight: 600;
  line-height: 1.35;
  word-break: break-word;
}

.msg-call {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 14px;
  font-weight: 600;
  color: #334155;
}
</style>
