<script setup>
import { ref, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, ChevronLeft, Image, Send, Pencil, Trash2, Eye, Play, Loader2 } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api, { MEDIA_UPLOAD_TIMEOUT_MS, STORY_PUBLISH_TIMEOUT_MS } from '../services/api'
import StoryEditorCanvas from '../components/stories/StoryEditorCanvas.vue'
import StoryDialog from '../components/stories/StoryDialog.vue'
import { useStoriesStore } from '../stores/stories'
import { useAuthStore } from '../stores/auth'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { captureVideoPoster } from '../utils/videoPoster'

const router = useRouter()
const { t } = useI18n()
const storiesStore = useStoriesStore()
const auth = useAuthStore()

const step = ref('pick')
const imageSrc = ref('')
const videoSrc = ref('')
const videoFile = ref(null)
const originalImageFile = ref(null)
const textOnly = ref(false)
const backgroundColor = ref('linear-gradient(135deg,#6c63ff 0%,#ff6584 100%)')
const caption = ref('')
const publishing = ref(false)
const editorRef = ref(null)
const editingSlideId = ref(null)
const editingFilterId = ref('none')
const mySlides = ref([])
const mySlidesLoading = ref(false)
const videoPosters = ref({})
let posterLoadGen = 0

const fileInput = ref(null)

const dialogOpen = ref(false)
const dialogMode = ref('alert')
const dialogVariant = ref('error')
const dialogTitle = ref('')
const dialogMessage = ref('')
const dialogLoading = ref(false)
let dialogConfirmHandler = null
const pendingDeleteSlide = ref(null)

async function showStoryAlert(message) {
  dialogMode.value = 'alert'
  dialogVariant.value = 'error'
  dialogTitle.value = ''
  dialogMessage.value = message
  dialogConfirmHandler = null
  dialogOpen.value = true
  await nextTick()
}

async function showStoryConfirm(message, onConfirm) {
  dialogMode.value = 'confirm'
  dialogVariant.value = 'danger'
  dialogTitle.value = ''
  dialogMessage.value = message
  dialogConfirmHandler = onConfirm
  dialogOpen.value = true
  await nextTick()
}

function closeStoryDialog() {
  dialogOpen.value = false
  dialogConfirmHandler = null
  dialogLoading.value = false
  pendingDeleteSlide.value = null
}

async function onStoryDialogConfirm() {
  if (dialogMode.value === 'confirm' && dialogConfirmHandler) {
    dialogLoading.value = true
    try {
      await dialogConfirmHandler()
      closeStoryDialog()
    } catch (err) {
      dialogLoading.value = false
      showStoryAlert(err.response?.data?.message ?? err.userMessage ?? t('common.error'))
    }
    return
  }
  closeStoryDialog()
}

function normalizeSlide(s) {
  return {
    id: s.id ?? s.Id,
    mediaUrl: s.mediaUrl ?? s.MediaUrl,
    mediaType: (s.mediaType ?? s.MediaType ?? 'image').toLowerCase(),
    caption: s.caption ?? s.Caption,
    backgroundColor: s.backgroundColor ?? s.BackgroundColor,
    filterId: s.filterId ?? s.FilterId ?? 'none',
    viewCount: s.viewCount ?? s.ViewCount ?? 0
  }
}

function thumbBgStyle(slide) {
  if (slide.mediaType === 'text' || (slide.backgroundColor && !slide.mediaUrl)) {
    return { background: slide.backgroundColor || 'linear-gradient(160deg,#6c63ff,#ff6584)' }
  }
  return { background: 'var(--bg-elevated)' }
}

function slideThumbSrc(slide) {
  if (!slide.mediaUrl || slide.mediaType === 'text') return null
  if (slide.mediaType === 'video') {
    return videoPosters.value[slide.id] || null
  }
  return ensureAbsoluteUrl(slide.mediaUrl)
}

async function loadVideoPosters(slides) {
  const gen = ++posterLoadGen
  const videos = slides.filter(s => s.mediaType === 'video' && s.mediaUrl)
  if (!videos.length) return

  await Promise.all(
    videos.map(async (slide) => {
      const url = ensureAbsoluteUrl(slide.mediaUrl)
      const poster = await captureVideoPoster(url)
      if (gen !== posterLoadGen) return
      if (poster) {
        videoPosters.value = { ...videoPosters.value, [slide.id]: poster }
      }
    })
  )
}

function viewMyStory(slide) {
  const uid = auth.user?.id
  if (!uid) return
  router.push({
    path: `/stories/view/${uid}`,
    query: { slideId: slide.id, from: 'create' }
  })
}

function resetEditorState() {
  editingSlideId.value = null
  editingFilterId.value = 'none'
  imageSrc.value = ''
  videoSrc.value = ''
  videoFile.value = null
  originalImageFile.value = null
  textOnly.value = false
  caption.value = ''
  backgroundColor.value = 'linear-gradient(135deg,#6c63ff 0%,#ff6584 100%)'
}

async function loadMySlides() {
  mySlidesLoading.value = true
  videoPosters.value = {}
  try {
    const { data } = await api.get('/stories/mine', { skipGlobalLoader: true })
    mySlides.value = (data ?? []).map(normalizeSlide)
    void loadVideoPosters(mySlides.value)
  } catch {
    mySlides.value = []
  } finally {
    mySlidesLoading.value = false
  }
}

function goBack() {
  if (step.value === 'edit') {
    resetEditorState()
    step.value = 'pick'
    loadMySlides()
  } else {
    router.replace('/conversations')
  }
}

function pickImage() {
  fileInput.value?.click()
}

function onFile(e) {
  const file = e.target.files?.[0]
  if (!file) return
  editingSlideId.value = null
  if (file.type.startsWith('video/')) {
    videoFile.value = file
    videoSrc.value = URL.createObjectURL(file)
    imageSrc.value = ''
    textOnly.value = false
  } else {
    imageSrc.value = URL.createObjectURL(file)
    originalImageFile.value = file
    videoSrc.value = ''
    videoFile.value = null
    textOnly.value = false
  }
  step.value = 'edit'
  e.target.value = ''
}

function startTextStory() {
  resetEditorState()
  textOnly.value = true
  step.value = 'edit'
}

function startEdit(slide) {
  resetEditorState()
  editingSlideId.value = slide.id
  caption.value = slide.caption || ''
  editingFilterId.value = slide.filterId || 'none'

  if (slide.mediaType === 'video' && slide.mediaUrl) {
    videoSrc.value = ensureAbsoluteUrl(slide.mediaUrl)
    textOnly.value = false
  } else if (slide.mediaType === 'text' || (slide.backgroundColor && !slide.mediaUrl)) {
    textOnly.value = true
    backgroundColor.value = slide.backgroundColor || backgroundColor.value
  } else if (slide.mediaUrl) {
    imageSrc.value = ensureAbsoluteUrl(slide.mediaUrl)
    textOnly.value = false
  } else {
    textOnly.value = true
  }
  step.value = 'edit'
}

function requestDeleteSlide(slide) {
  pendingDeleteSlide.value = slide
  void showStoryConfirm(t('stories.confirmDeleteSlide'), confirmDeleteSlide)
}

async function confirmDeleteSlide() {
  const slide = pendingDeleteSlide.value
  if (!slide?.id) return
  await api.delete(`/stories/${slide.id}`, { skipGlobalLoader: true })
  mySlides.value = mySlides.value.filter(s => s.id !== slide.id)
  storiesStore.invalidate()
  await storiesStore.fetchFeed(true)
  pendingDeleteSlide.value = null
}

async function publish() {
  if (publishing.value) return
  publishing.value = true
  try {
    if (editingSlideId.value) {
      await saveEdit()
      return
    }

    let mediaUrl = null
    let mediaType = 'image'
    let videoDurationSeconds = null

    if (textOnly.value) {
      mediaType = 'text'
      const blob = await editorRef.value?.exportImage()
      if (blob) {
        const fd = new FormData()
        fd.append('file', blob, 'story.jpg')
        const { data } = await api.post('/media/upload-story-image', fd, {
          timeout: MEDIA_UPLOAD_TIMEOUT_MS,
          skipGlobalLoader: true
        })
        mediaUrl = data.url
        mediaType = 'image'
      }
    } else if (videoFile.value) {
      mediaType = 'video'
      const fd = new FormData()
      fd.append('file', videoFile.value)
      const { data } = await api.post('/media/upload-story-video', fd, {
        timeout: MEDIA_UPLOAD_TIMEOUT_MS,
        skipGlobalLoader: true
      })
      mediaUrl = data.url
    } else if (imageSrc.value) {
      const useOriginal = originalImageFile.value && !editorRef.value?.hasEditorChanges?.()
      if (useOriginal) {
        const fd = new FormData()
        fd.append('file', originalImageFile.value)
        const { data } = await api.post('/media/upload-story-image', fd, {
          timeout: MEDIA_UPLOAD_TIMEOUT_MS,
          skipGlobalLoader: true
        })
        mediaUrl = data.url
      } else {
        const blob = await editorRef.value?.exportImage()
        if (!blob) throw new Error('export failed')
        const fd = new FormData()
        fd.append('file', blob, 'story.jpg')
        const { data } = await api.post('/media/upload-story-image', fd, {
          timeout: MEDIA_UPLOAD_TIMEOUT_MS,
          skipGlobalLoader: true
        })
        mediaUrl = data.url
      }
      mediaType = 'image'
    }

    const overlayJson = editorRef.value?.getOverlayJson?.() ?? null
    const filterId = editorRef.value?.getFilterId?.() ?? 'none'

    await api.post('/stories', {
      mediaUrl,
      mediaType,
      caption: caption.value.trim() || null,
      overlayJson,
      backgroundColor: textOnly.value ? backgroundColor.value : null,
      filterId: filterId === 'none' ? null : filterId,
      videoDurationSeconds
    }, {
      timeout: STORY_PUBLISH_TIMEOUT_MS,
      skipGlobalLoader: true
    })

    storiesStore.invalidate()
    await storiesStore.fetchFeed(true)
    router.replace('/conversations')
  } catch (e) {
    showStoryAlert(e.response?.data?.message ?? e.userMessage ?? t('common.error'))
  } finally {
    publishing.value = false
  }
}

async function saveEdit() {
  const slideId = editingSlideId.value
  if (!slideId) return

  let mediaUrl = null
  const filterId = editorRef.value?.getFilterId?.() ?? 'none'
  const overlayJson = editorRef.value?.getOverlayJson?.() ?? null

  if (textOnly.value) {
    const blob = await editorRef.value?.exportImage()
    if (blob) {
      const fd = new FormData()
      fd.append('file', blob, 'story.jpg')
      const { data } = await api.post('/media/upload-story-image', fd, {
        timeout: MEDIA_UPLOAD_TIMEOUT_MS,
        skipGlobalLoader: true
      })
      mediaUrl = data.url
    }
  } else if (!videoFile.value && imageSrc.value) {
    const blob = await editorRef.value?.exportImage()
    if (blob) {
      const fd = new FormData()
      fd.append('file', blob, 'story.jpg')
      const { data } = await api.post('/media/upload-story-image', fd, {
        timeout: MEDIA_UPLOAD_TIMEOUT_MS,
        skipGlobalLoader: true
      })
      mediaUrl = data.url
    }
  }

  const body = {
    caption: caption.value.trim() || null,
    overlayJson,
    backgroundColor: textOnly.value ? backgroundColor.value : null,
    filterId: filterId === 'none' ? null : filterId
  }
  if (mediaUrl) body.mediaUrl = mediaUrl

  await api.put(`/stories/${slideId}`, body, {
    timeout: STORY_PUBLISH_TIMEOUT_MS,
    skipGlobalLoader: true
  })

  storiesStore.invalidate()
  await storiesStore.fetchFeed(true)
  resetEditorState()
  step.value = 'pick'
  await loadMySlides()
}

onMounted(() => {
  if (step.value === 'pick') loadMySlides()
})

watch(step, (s) => {
  if (s === 'pick') loadMySlides()
})

onUnmounted(() => {
  posterLoadGen++
})
</script>

<template>
  <div class="story-create page auth-pattern" :class="{ 'story-create--edit': step === 'edit' }">
    <header class="top-bar">
      <button type="button" class="back-btn" @click="goBack"><ChevronRight :size="22" /></button>
      <span class="top-title">{{ editingSlideId ? t('stories.editStory') : t('stories.createTitle') }}</span>
      <button
        v-if="step === 'edit'"
        type="button"
        class="publish-btn"
        :class="{ 'is-publishing': publishing }"
        :disabled="publishing"
        :aria-label="publishing ? t('common.loading') : t('stories.publish')"
        @click="publish"
      >
        <Loader2 v-if="publishing" :size="18" class="publish-spin" />
        <Send v-else :size="18" />
      </button>
      <span v-else class="top-spacer" />
    </header>

    <input
      ref="fileInput"
      type="file"
      accept="image/*,video/*"
      class="hidden-input"
      @change="onFile"
    />

    <div v-if="step === 'pick'" class="pick-step">
      <p class="pick-lead">{{ t('stories.pickSubtitle') }}</p>

      <section v-if="mySlidesLoading || mySlides.length" class="my-stories-section">
        <div class="my-stories-header">
          <h3 class="my-stories-title">{{ t('stories.myActiveStories') }}</h3>
          <span v-if="!mySlidesLoading && mySlides.length" class="my-stories-count">{{ mySlides.length }}</span>
        </div>
        <p v-if="mySlidesLoading" class="my-stories-loading">{{ t('common.loading') }}</p>
        <div v-else class="my-stories-panel">
          <div class="my-stories-scroll">
            <article
              v-for="(slide, i) in mySlides"
              :key="slide.id"
              class="my-story-card"
            >
              <div class="my-story-shell">
                <button
                  type="button"
                  class="my-story-ring"
                  :aria-label="t('stories.viewMyStory')"
                  @click="viewMyStory(slide)"
                >
                  <div class="my-story-thumb" :style="thumbBgStyle(slide)">
                  <img
                    v-if="slideThumbSrc(slide)"
                    :src="slideThumbSrc(slide)"
                    class="my-story-img"
                    alt=""
                    loading="lazy"
                    referrerpolicy="no-referrer"
                  />
                  <video
                    v-else-if="slide.mediaType === 'video' && slide.mediaUrl"
                    :src="ensureAbsoluteUrl(slide.mediaUrl)"
                    class="my-story-img my-story-video-fallback"
                    muted
                    playsinline
                    preload="metadata"
                    @loadeddata="(e) => { try { e.target.currentTime = 0.1 } catch {} }"
                  />
                  <span v-else-if="slide.caption" class="my-story-caption-preview">{{ slide.caption }}</span>
                  <span v-else class="my-story-aa">Aa</span>
                  <span v-if="slide.mediaType === 'video'" class="my-story-type-badge" aria-hidden="true">
                    <Play :size="14" fill="currentColor" />
                  </span>
                  <span v-if="slide.viewCount > 0" class="my-story-views-badge">
                    <Eye :size="11" />
                    {{ slide.viewCount }}
                  </span>
                </div>
                </button>
                <div class="my-story-overlay">
                  <button type="button" class="my-story-action" :title="t('stories.editStory')" @click.stop="startEdit(slide)">
                    <Pencil :size="13" stroke-width="2.5" />
                  </button>
                  <button
                    type="button"
                    class="my-story-action my-story-action--danger"
                    :title="t('common.delete')"
                    :aria-label="t('common.delete')"
                    @click.stop.prevent="requestDeleteSlide(slide)"
                  >
                    <Trash2 :size="13" stroke-width="2.5" />
                  </button>
                </div>
              </div>
              <span class="my-story-index">{{ i + 1 }}</span>
            </article>
          </div>
        </div>
      </section>

      <div class="pick-list">
        <button type="button" class="pick-card pick-card--media" @click="pickImage">
          <div class="pick-card-preview pick-card-preview--media" aria-hidden="true">
            <Image :size="24" stroke-width="2" />
          </div>
          <div class="pick-card-copy">
            <span class="pick-card-title">{{ t('stories.pickPhotoVideo') }}</span>
            <span class="pick-card-desc">{{ t('stories.pickPhotoVideoDesc') }}</span>
          </div>
          <span class="pick-card-chevron" aria-hidden="true"><ChevronLeft :size="20" stroke-width="2" /></span>
        </button>

        <button type="button" class="pick-card pick-card--text" @click="startTextStory">
          <div class="pick-card-preview pick-card-preview--text" aria-hidden="true">
            <span class="preview-aa">Aa</span>
          </div>
          <div class="pick-card-copy">
            <span class="pick-card-title">{{ t('stories.pickText') }}</span>
            <span class="pick-card-desc">{{ t('stories.pickTextDesc') }}</span>
          </div>
          <span class="pick-card-chevron" aria-hidden="true"><ChevronLeft :size="20" stroke-width="2" /></span>
        </button>
      </div>
    </div>

    <div v-else class="editor-shell">
      <StoryEditorCanvas
        ref="editorRef"
        class="story-editor"
        :image-src="imageSrc"
        :video-src="videoSrc"
        :text-only="textOnly"
        :background-color="backgroundColor"
        :initial-filter-id="editingFilterId"
        @update:background-color="backgroundColor = $event"
      />
      <div class="caption-wrap">
        <input v-model="caption" type="text" class="caption-input" :placeholder="t('stories.captionPlaceholder')" />
      </div>
    </div>

    <StoryDialog
      v-model:open="dialogOpen"
      :mode="dialogMode"
      :variant="dialogVariant"
      :title="dialogTitle"
      :message="dialogMessage"
      :loading="dialogLoading"
      @confirm="onStoryDialogConfirm"
      @cancel="closeStoryDialog"
    />
  </div>
</template>

<style scoped>
.story-create {
  display: flex;
  flex-direction: column;
  min-height: 100%;
  background: var(--bg-primary);
  font-family: 'Cairo', sans-serif;
}

.story-create--edit {
  overflow: hidden;
  min-height: 0;
}

.editor-shell {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.editor-shell :deep(.editor-root) {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
}

.editor-shell :deep(.editor-stage) {
  flex: 0 1 auto;
  max-height: min(40vh, 300px);
  min-height: 200px;
}

.editor-shell :deep(.tools-panel) {
  flex-shrink: 0;
}

.top-bar {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: calc(var(--safe-top) + 8px) 12px 8px;
  flex-shrink: 0;
}

.back-btn {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  border: 1px solid var(--border);
  background: var(--bg-card);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  color: var(--text-secondary);
  -webkit-tap-highlight-color: transparent;
}

.top-title {
  flex: 1;
  text-align: center;
  font-size: 15px;
  font-weight: 600;
}

.publish-btn {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  border: none;
  background: var(--primary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  flex-shrink: 0;
  transition: opacity 0.15s ease, transform 0.12s ease;
}

.publish-btn:disabled,
.publish-btn.is-publishing {
  opacity: 0.9;
  cursor: wait;
  pointer-events: none;
}

.publish-btn:active:not(:disabled) {
  transform: scale(0.96);
}

.publish-spin {
  animation: publish-spin 0.75s linear infinite;
}

@keyframes publish-spin {
  to {
    transform: rotate(360deg);
  }
}

.top-spacer {
  width: 40px;
}

.hidden-input {
  display: none;
}

/* —— Pick step —— */
.pick-step {
  flex: 1;
  display: flex;
  flex-direction: column;
  padding: 4px 16px calc(20px + var(--safe-bottom));
  overflow-y: auto;
}

.pick-lead {
  margin: 0 0 16px;
  padding: 0 4px;
  font-size: 14px;
  line-height: 1.55;
  color: var(--text-secondary);
  text-align: center;
}

.pick-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.pick-card {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  padding: 12px;
  border-radius: 16px;
  border: 1px solid var(--border);
  background: var(--bg-card);
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  text-align: start;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.12s ease, background 0.12s ease;
  box-shadow: 0 1px 8px rgba(0, 0, 0, 0.04);
}

.pick-card:active {
  transform: scale(0.99);
  background: var(--bg-elevated);
}

.pick-card-preview {
  flex-shrink: 0;
  width: 48px;
  height: 64px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
}

.pick-card-preview--media {
  background: linear-gradient(160deg, #6c63ff 0%, #00d4ff 100%);
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.15);
}

.pick-card-preview--text {
  background: linear-gradient(160deg, #6c63ff 0%, #ff6584 100%);
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.15);
}

.preview-aa {
  font-size: 20px;
  font-weight: 800;
  letter-spacing: -0.03em;
}

.pick-card-copy {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.pick-card-title {
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
  line-height: 1.3;
}

.pick-card-desc {
  font-size: 12px;
  font-weight: 500;
  color: var(--text-secondary);
  line-height: 1.45;
}

.pick-card-chevron {
  flex-shrink: 0;
  color: var(--text-tertiary);
  opacity: 0.7;
}

html[dir='ltr'] .pick-card-chevron {
  transform: scaleX(-1);
}

html.light .pick-card,
[data-theme='light'] .pick-card {
  box-shadow: 0 2px 16px rgba(108, 99, 255, 0.08);
}

.my-stories-section {
  margin-bottom: 22px;
}

.my-stories-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 10px;
  padding: 0 2px;
}

.my-stories-title {
  margin: 0;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
}

.my-stories-count {
  min-width: 24px;
  height: 24px;
  padding: 0 8px;
  border-radius: 12px;
  background: rgba(108, 99, 255, 0.12);
  color: var(--primary);
  font-size: 12px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
}

.my-stories-loading {
  margin: 0;
  padding: 24px;
  font-size: 13px;
  color: var(--text-tertiary);
  text-align: center;
  background: var(--bg-card);
  border-radius: 16px;
  border: 1px solid var(--border);
}

.my-stories-panel {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 18px;
  padding: 14px 12px;
  box-shadow: 0 2px 14px rgba(0, 0, 0, 0.04);
}

html.light .my-stories-panel,
[data-theme='light'] .my-stories-panel {
  box-shadow: 0 2px 16px rgba(108, 99, 255, 0.06);
}

.my-stories-scroll {
  display: flex;
  gap: 14px;
  overflow-x: auto;
  padding: 4px 4px 2px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.my-stories-scroll::-webkit-scrollbar {
  display: none;
}

.my-story-card {
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  width: 100px;
}

.my-story-shell {
  position: relative;
  padding: 2px;
  border-radius: 16px;
  background: linear-gradient(135deg, #6c63ff, #ff6584, #00d4ff);
}

.my-story-ring {
  display: block;
  padding: 0;
  border: none;
  border-radius: 14px;
  background: none;
  cursor: pointer;
  font: inherit;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.12s ease, opacity 0.12s ease;
}

.my-story-ring:active {
  transform: scale(0.98);
  opacity: 0.92;
}

.my-story-thumb {
  position: relative;
  width: 92px;
  height: 122px;
  border-radius: 14px;
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--bg-card);
  box-sizing: border-box;
}

.my-story-img {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.my-story-video-fallback {
  pointer-events: none;
  background: #111;
}

.my-story-aa {
  font-size: 26px;
  font-weight: 800;
  color: #fff;
  text-shadow: 0 1px 4px rgba(0, 0, 0, 0.25);
  z-index: 0;
}

.my-story-caption-preview {
  position: relative;
  z-index: 0;
  padding: 12px;
  font-size: 13px;
  font-weight: 700;
  color: #fff;
  text-align: center;
  line-height: 1.35;
  display: -webkit-box;
  -webkit-line-clamp: 4;
  -webkit-box-orient: vertical;
  overflow: hidden;
  text-shadow: 0 1px 3px rgba(0, 0, 0, 0.35);
}

.my-story-type-badge {
  position: absolute;
  top: 8px;
  inset-inline-start: 8px;
  z-index: 2;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.45);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  backdrop-filter: blur(4px);
}

.my-story-views-badge {
  position: absolute;
  top: 8px;
  inset-inline-end: 8px;
  z-index: 2;
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 4px 8px;
  border-radius: 20px;
  background: rgba(0, 0, 0, 0.5);
  color: #fff;
  font-size: 11px;
  font-weight: 600;
  backdrop-filter: blur(4px);
}

.my-story-overlay {
  position: absolute;
  inset-inline: 2px;
  bottom: 2px;
  z-index: 4;
  pointer-events: auto;
  display: flex;
  justify-content: center;
  gap: 6px;
  padding: 6px 8px 8px;
  background: linear-gradient(to top, rgba(0, 0, 0, 0.65), transparent);
}

.my-story-action {
  width: 28px;
  height: 28px;
  flex-shrink: 0;
  border: none;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.95);
  color: var(--primary);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.1s ease, opacity 0.1s ease;
}

.my-story-action:active {
  transform: scale(0.96);
  opacity: 0.9;
}

.my-story-action--danger {
  color: #e53935;
  background: rgba(255, 255, 255, 0.95);
}

.my-story-index {
  font-size: 11px;
  font-weight: 600;
  color: var(--text-tertiary);
}

.caption-wrap {
  flex-shrink: 0;
  padding: 10px 12px calc(10px + var(--safe-bottom));
  border-top: 1px solid var(--border);
  background: var(--bg-card);
  position: relative;
  z-index: 3;
}

.caption-input {
  width: 100%;
  padding: 12px 14px;
  border-radius: 12px;
  border: 1px solid var(--border);
  background: var(--bg-elevated);
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
  color: var(--text-primary);
}

.caption-input::placeholder {
  color: var(--text-muted);
}

.caption-input:focus {
  outline: none;
  border-color: var(--primary);
}
</style>



