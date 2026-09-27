<script setup>
import { computed } from 'vue'
import { fullMediaUrl } from '../utils/media'
import {
  parseAlbumUrls,
  parseShortFilm,
  parseStoryShare,
  parseCall,
  formatCallLabel,
  callIcon
} from '../utils/messageContent'

const props = defineProps({
  type: { type: String, default: 'text' },
  content: { type: String, default: '' },
  isViewOnce: { type: Boolean, default: false },
  viewOnceOpenCount: { type: Number, default: 0 }
})

const normalizedType = computed(() => (props.type || 'text').toLowerCase())

const viewOnceLabel = computed(() => {
  if (!props.isViewOnce) return ''
  if (props.viewOnceOpenCount > 0) return 'مشاهدة مرة واحدة · تم الفتح'
  return 'مشاهدة مرة واحدة'
})

const mediaSrc = computed(() => fullMediaUrl(props.content))

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

const callLabel = computed(() => (call.value ? formatCallLabel(props.content) : ''))
const callMdi = computed(() => (call.value ? callIcon(props.content) : 'mdi-phone'))

const showImage = computed(() => !props.isViewOnce && normalizedType.value === 'image' && props.content)
const showVideo = computed(() => !props.isViewOnce && normalizedType.value === 'video' && props.content)
const showAudio = computed(() => normalizedType.value === 'audio' && props.content)
const showViewOnceOnly = computed(() => props.isViewOnce && (normalizedType.value === 'image' || normalizedType.value === 'video'))
const showText = computed(() => {
  if (showViewOnceOnly.value) return false
  if (showImage.value || showVideo.value || showAudio.value) return false
  if (albumUrls.value) return false
  if (shortFilm.value) return false
  if (storyShare.value) return false
  if (call.value) return false
  return true
})
</script>

<template>
  <div class="admin-msg-body">
    <div v-if="viewOnceLabel" class="msg-view-once-badge">
      <v-icon size="16" color="primary">mdi-eye</v-icon>
      <span>{{ viewOnceLabel }}</span>
      <span v-if="showViewOnceOnly" class="msg-view-once-type">
        · {{ normalizedType === 'video' ? 'فيديو' : 'صورة' }}
      </span>
    </div>

    <!-- Image -->
    <a
      v-if="showImage"
      :href="mediaSrc"
      target="_blank"
      rel="noopener"
      class="msg-media-link"
    >
      <img :src="mediaSrc" alt="صورة" class="msg-thumb" loading="lazy" />
    </a>

    <!-- Video -->
    <div v-else-if="showVideo" class="msg-video-wrap">
      <video :src="mediaSrc" controls preload="metadata" class="msg-video" />
      <a :href="mediaSrc" target="_blank" rel="noopener" class="msg-open-link">
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
      <audio :src="mediaSrc" controls preload="metadata" class="msg-audio" />
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
