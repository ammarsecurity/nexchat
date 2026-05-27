<script setup>
import { ref, onMounted, onUnmounted, watch, nextTick, computed } from 'vue'
import { useRouter } from 'vue-router'
import { Send, Pencil, Trash2, Eye, Play, Loader2, Type, Film, ChevronLeft, ChevronRight } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../stores/locale'
import ModernPageShell from '../components/ui/ModernPageShell.vue'
import api, { MEDIA_UPLOAD_TIMEOUT_MS, STORY_PUBLISH_TIMEOUT_MS } from '../services/api'
import StoryEditorCanvas from '../components/stories/StoryEditorCanvas.vue'
import StoryDialog from '../components/stories/StoryDialog.vue'
import { useStoriesStore } from '../stores/stories'
import { useAuthStore } from '../stores/auth'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { captureVideoPoster } from '../utils/videoPoster'
import { StoryExportError, isStoryExportError } from '../utils/storyExport'

const router = useRouter()
const { t } = useI18n()
const localeStore = useLocaleStore()

const BackIcon = computed(() => (localeStore.isRtl ? ChevronRight : ChevronLeft))
const ForwardIcon = computed(() => (localeStore.isRtl ? ChevronLeft : ChevronRight))
const storiesStore = useStoriesStore()
const auth = useAuthStore()

const step = ref('pick')
const imageSrc = ref('')
const videoSrc = ref('')
const videoFile = ref(null)
const originalImageFile = ref(null)
const textOnly = ref(false)
const backgroundColor = ref('linear-gradient(135deg,#2563eb 0%,#60a5fa 100%)')
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
    return { background: slide.backgroundColor || 'linear-gradient(160deg,#2563eb,#60a5fa)' }
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
  backgroundColor.value = 'linear-gradient(135deg,#2563eb 0%,#60a5fa 100%)'
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

function storyErrorMessage(e) {
  if (isStoryExportError(e)) return t('stories.exportFailed')
  if (e?.response?.status >= 500) return t('stories.publishFailed')
  return e.response?.data?.message ?? e.userMessage ?? t('common.error')
}

async function uploadStoryBlob(blob) {
  const file = blob instanceof File
    ? blob
    : new File([blob], 'story.jpg', { type: blob.type || 'image/jpeg' })
  const fd = new FormData()
  fd.append('file', file, file.name)
  const { data } = await api.post('/media/upload-story-image', fd, {
    timeout: MEDIA_UPLOAD_TIMEOUT_MS,
    skipGlobalLoader: true
  })
  return data.url
}

async function exportStoryBlob(required = true) {
  const blob = await editorRef.value?.exportImage()
  if (!blob && required) throw new StoryExportError()
  return blob
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
    let keepTextBackground = false

    if (textOnly.value) {
      mediaType = 'text'
      const blob = await exportStoryBlob(false)
      if (blob) {
        mediaUrl = await uploadStoryBlob(blob)
        mediaType = 'image'
      } else {
        keepTextBackground = true
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
        const blob = await exportStoryBlob(true)
        mediaUrl = await uploadStoryBlob(blob)
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
      backgroundColor: keepTextBackground ? backgroundColor.value : null,
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
    showStoryAlert(storyErrorMessage(e))
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
    const blob = await exportStoryBlob(false)
    if (blob) mediaUrl = await uploadStoryBlob(blob)
  } else if (!videoFile.value && imageSrc.value) {
    const blob = await exportStoryBlob(true)
    if (blob) mediaUrl = await uploadStoryBlob(blob)
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
  <div class="story-create" :class="{ 'story-create--edit': step === 'edit' }">
    <input
      ref="fileInput"
      type="file"
      accept="image/*,video/*"
      class="hidden-input"
      @change="onFile"
    />

    <ModernPageShell
      v-if="step === 'pick'"
      :title="t('stories.createTitle')"
      back-to="/conversations"
    >
      <section class="story-create-hero">
        <p class="story-create-hero__text">{{ t('stories.pickSubtitle') }}</p>
      </section>

      <div class="create-grid">
        <button type="button" class="create-tile create-tile--media" @click="pickImage">
          <span class="create-tile__icon create-tile__icon--media" aria-hidden="true">
            <Film :size="26" stroke-width="2" />
          </span>
          <span class="create-tile__title">{{ t('stories.pickPhotoVideo') }}</span>
          <span class="create-tile__desc">{{ t('stories.pickPhotoVideoDesc') }}</span>
          <component :is="ForwardIcon" class="create-tile__chevron" :size="18" stroke-width="2" aria-hidden="true" />
        </button>

        <button type="button" class="create-tile create-tile--text" @click="startTextStory">
          <span class="create-tile__icon create-tile__icon--text" aria-hidden="true">
            <Type :size="26" stroke-width="2" />
          </span>
          <span class="create-tile__title">{{ t('stories.pickText') }}</span>
          <span class="create-tile__desc">{{ t('stories.pickTextDesc') }}</span>
          <component :is="ForwardIcon" class="create-tile__chevron" :size="18" stroke-width="2" aria-hidden="true" />
        </button>
      </div>

      <section v-if="mySlidesLoading || mySlides.length" class="my-stories-section">
        <div class="section-head">
          <h2 class="section-head__title">{{ t('stories.myActiveStories') }}</h2>
          <span v-if="!mySlidesLoading && mySlides.length" class="section-head__badge">{{ mySlides.length }}</span>
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
                    <span class="my-story-order">{{ i + 1 }}</span>
                    <span v-if="slide.mediaType === 'video'" class="my-story-type-badge" aria-hidden="true">
                      <Play :size="12" fill="currentColor" />
                    </span>
                    <span v-if="slide.viewCount > 0" class="my-story-views-badge">
                      <Eye :size="10" />
                      {{ slide.viewCount }}
                    </span>
                  </div>
                </button>
              </div>
              <div class="my-story-actions">
                <button
                  type="button"
                  class="my-story-action-btn"
                  :title="t('stories.editStory')"
                  @click.stop="startEdit(slide)"
                >
                  <Pencil :size="14" stroke-width="2.5" />
                </button>
                <button
                  type="button"
                  class="my-story-action-btn my-story-action-btn--danger"
                  :title="t('common.delete')"
                  :aria-label="t('common.delete')"
                  @click.stop.prevent="requestDeleteSlide(slide)"
                >
                  <Trash2 :size="14" stroke-width="2.5" />
                </button>
              </div>
            </article>
          </div>
        </div>
      </section>

    </ModernPageShell>

    <div v-else class="story-create-edit modern-page">
      <header class="modern-page__nav story-edit-nav">
        <button type="button" class="modern-glass-btn" :aria-label="t('common.back')" @click="goBack">
          <component :is="BackIcon" :size="22" stroke-width="2" />
        </button>
        <h1 class="modern-page__title">{{ editingSlideId ? t('stories.editStory') : t('stories.createTitle') }}</h1>
        <button
          type="button"
          class="story-publish-btn"
          :class="{ 'is-publishing': publishing }"
          :disabled="publishing"
          :aria-label="publishing ? t('common.loading') : t('stories.publish')"
          @click="publish"
        >
          <Loader2 v-if="publishing" :size="18" class="publish-spin" />
          <Send v-else :size="18" />
        </button>
      </header>

      <div class="editor-shell">
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
  min-height: 100%;
  font-family: 'Cairo', sans-serif;
}

.story-create--edit {
  overflow: hidden;
  min-height: 100dvh;
}

.story-create-edit {
  display: flex;
  flex-direction: column;
  min-height: 100dvh;
  overflow: hidden;
}

.story-edit-nav {
  flex-shrink: 0;
}

.story-publish-btn {
  width: var(--header-btn-size);
  height: var(--header-btn-size);
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
  box-shadow: 0 4px 14px rgba(37, 99, 235, 0.28);
}

.story-publish-btn:disabled,
.story-publish-btn.is-publishing {
  opacity: 0.9;
  cursor: wait;
  pointer-events: none;
}

.story-publish-btn:active:not(:disabled) {
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

.hidden-input {
  display: none;
}

/* —— Pick step —— */
.story-create-hero {
  margin-bottom: 16px;
  padding: 14px 16px;
  border-radius: var(--radius-lg);
  background: linear-gradient(135deg, rgba(37, 99, 235, 0.1) 0%, rgba(96, 165, 250, 0.08) 100%);
  border: 1px solid rgba(37, 99, 235, 0.12);
}

.story-create-hero__text {
  margin: 0;
  font-size: 14px;
  line-height: 1.55;
  color: var(--text-secondary);
  text-align: center;
}

.create-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  margin-bottom: 24px;
}

.create-tile {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 8px;
  min-height: 168px;
  padding: 16px 14px;
  border-radius: var(--radius-lg);
  border: 1px solid var(--border);
  background: var(--bg-card);
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  text-align: start;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.12s ease, box-shadow 0.15s ease;
  box-shadow: var(--shadow-sm);
}

.create-tile:active {
  transform: scale(0.98);
}

.create-tile__icon {
  width: 48px;
  height: 48px;
  border-radius: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
}

.create-tile__icon--media {
  background: linear-gradient(145deg, #2563eb 0%, #60a5fa 100%);
}

.create-tile__icon--text {
  background: linear-gradient(145deg, #1d4ed8 0%, #93c5fd 100%);
}

.create-tile__title {
  font-size: 14px;
  font-weight: 700;
  line-height: 1.35;
  color: var(--text-primary);
}

.create-tile__desc {
  font-size: 11px;
  font-weight: 500;
  line-height: 1.45;
  color: var(--text-secondary);
  flex: 1;
}

.create-tile__chevron {
  position: absolute;
  bottom: 14px;
  inset-inline-end: 14px;
  color: var(--text-tertiary);
  opacity: 0.65;
}

.section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 10px;
  padding: 0 2px;
}

.section-head__title {
  margin: 0;
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
}

.section-head__badge {
  min-width: 24px;
  height: 24px;
  padding: 0 8px;
  border-radius: 12px;
  background: rgba(37, 99, 235, 0.12);
  color: var(--primary);
  font-size: 12px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
}

.my-stories-section {
  margin-bottom: 8px;
}

.my-stories-loading {
  margin: 0;
  padding: 24px;
  font-size: 13px;
  color: var(--text-tertiary);
  text-align: center;
  background: var(--bg-card);
  border-radius: var(--radius-lg);
  border: 1px solid var(--border);
}

.my-stories-panel {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 14px 12px;
  box-shadow: var(--shadow-sm);
}

.my-stories-scroll {
  display: flex;
  gap: 12px;
  overflow-x: auto;
  padding: 2px 2px 4px;
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
  align-items: stretch;
  gap: 8px;
  width: 108px;
}

.my-story-shell {
  padding: 2px;
  border-radius: 16px;
  background: linear-gradient(145deg, #2563eb, #60a5fa);
}

.my-story-ring {
  display: block;
  width: 100%;
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
  width: 100%;
  aspect-ratio: 9 / 14;
  border-radius: 14px;
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--bg-card);
  box-sizing: border-box;
}

.my-story-order {
  position: absolute;
  top: 6px;
  inset-inline-start: 6px;
  z-index: 3;
  min-width: 22px;
  height: 22px;
  padding: 0 6px;
  border-radius: 999px;
  background: rgba(15, 23, 42, 0.55);
  backdrop-filter: blur(6px);
  color: #fff;
  font-size: 11px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  line-height: 1;
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
  bottom: 6px;
  inset-inline-start: 6px;
  z-index: 2;
  width: 24px;
  height: 24px;
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
  bottom: 6px;
  inset-inline-end: 6px;
  z-index: 2;
  display: flex;
  align-items: center;
  gap: 3px;
  padding: 3px 7px;
  border-radius: 999px;
  background: rgba(0, 0, 0, 0.5);
  color: #fff;
  font-size: 10px;
  font-weight: 600;
  backdrop-filter: blur(4px);
}

.my-story-actions {
  display: flex;
  gap: 6px;
}

.my-story-action-btn {
  flex: 1;
  height: 34px;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--bg-elevated);
  color: var(--primary);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.1s ease, background 0.12s ease;
}

.my-story-action-btn:active {
  transform: scale(0.96);
  background: var(--bg-card-hover);
}

.my-story-action-btn--danger {
  color: var(--danger);
  background: rgba(244, 67, 54, 0.08);
  border-color: rgba(244, 67, 54, 0.2);
}

/* —— Edit step —— */
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
  max-height: min(42vh, 320px);
  min-height: 200px;
}

.editor-shell :deep(.tools-panel) {
  flex-shrink: 0;
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
  border-radius: var(--radius-md);
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



