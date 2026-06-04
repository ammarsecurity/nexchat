<script setup>
import { ref } from 'vue'
import { Image, Upload, X } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { notify } from '../utils/notify'
import LoaderOverlay from './LoaderOverlay.vue'

const open = defineModel('open', { type: Boolean, default: false })
const emit = defineEmits(['updated'])

const { t } = useI18n()
const auth = useAuthStore()

const avatarTab = ref('preset')
const uploadingAvatar = ref(false)
const avatarFileInput = ref(null)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

const presetAvatars = [
  '🦊', '🐺', '🦁', '🐯', '🐻', '🐼', '🐨', '🦋',
  '🦅', '🐬', '🦈', '🐙', '🌟', '🎭', '🎯', '🎮',
  '🚀', '⚡', '🔥', '💎', '👑', '🤖', '👻', '🎃',
  '🌈', '🌊', '🌺', '🍀', '⭐', '🎵'
]

const isImageUrl = (v) => v && (v.startsWith('http') || v.startsWith('/'))

function close() {
  open.value = false
}

async function selectPreset(emoji) {
  await auth.setAvatar(emoji)
  emit('updated')
  close()
}

async function handleAvatarUpload(e) {
  const file = e.target.files?.[0]
  if (!file) return
  if (avatarFileInput.value) avatarFileInput.value.value = ''
  const formData = new FormData()
  formData.append('file', file)
  const token = localStorage.getItem('nexchat_token')
  uploadingAvatar.value = true
  try {
    const res = await fetch(`${API_BASE}/media/upload`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: formData
    })
    if (!res.ok) throw new Error()
    const { url } = await res.json()
    await auth.setAvatar(url)
    emit('updated')
    close()
  } catch {
    notify.error(t('common.error'))
  } finally {
    uploadingAvatar.value = false
  }
}
</script>

<template>
  <LoaderOverlay :show="uploadingAvatar" :text="t('settings.uploadingImage')" />

  <Teleport to="body">
    <Transition name="avatar-picker-modal">
      <div v-if="open" class="avatar-picker-overlay" @click.self="close">
        <div class="picker-sheet glass-card" role="dialog" aria-modal="true" :aria-label="t('settings.chooseAvatar')">
          <div class="sheet-handle" aria-hidden="true" />

          <div class="picker-hdr">
            <span class="picker-title">{{ t('settings.chooseAvatar') }}</span>
            <button type="button" class="close-x" :aria-label="t('common.cancel')" @click="close">
              <X :size="18" />
            </button>
          </div>

          <div class="picker-tabs">
            <button type="button" class="ptab" :class="{ active: avatarTab === 'preset' }" @click="avatarTab = 'preset'">
              <Image :size="16" /> {{ t('settings.preset') }}
            </button>
            <button type="button" class="ptab" :class="{ active: avatarTab === 'upload' }" @click="avatarTab = 'upload'">
              <Upload :size="16" /> {{ t('settings.uploadImage') }}
            </button>
          </div>

          <div v-if="avatarTab === 'preset'" class="presets-grid">
            <button
              v-for="emoji in presetAvatars"
              :key="emoji"
              type="button"
              class="preset-btn"
              :class="{ selected: auth.avatar === emoji }"
              :style="{ background: auth.avatarColor }"
              @click="selectPreset(emoji)"
            >
              {{ emoji }}
            </button>
          </div>

          <div v-else class="upload-tab">
            <div class="upload-preview">
              <img
                v-if="isImageUrl(auth.avatar)"
                :src="ensureAbsoluteUrl(auth.avatar)"
                class="prev-img"
                alt=""
                referrerpolicy="no-referrer"
              />
              <div v-else class="prev-empty">
                <Image :size="44" style="color: var(--text-muted)" />
                <span class="text-muted text-sm">{{ t('settings.noImage') }}</span>
              </div>
            </div>
            <input
              ref="avatarFileInput"
              type="file"
              accept="image/jpeg,image/png,image/gif,image/webp,image/avif"
              class="hidden-input"
              @change="handleAvatarUpload"
            />
            <button type="button" class="upload-btn" :disabled="uploadingAvatar" @click="avatarFileInput?.click()">
              {{ uploadingAvatar ? t('settings.uploading') : t('settings.chooseImage') }}
            </button>
            <div class="upload-hint text-muted text-sm">{{ t('settings.maxSize') }}</div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.hidden-input {
  display: none;
}

.avatar-picker-overlay {
  position: fixed;
  inset: 0;
  z-index: 500;
  display: flex;
  align-items: flex-end;
  background: rgba(0, 0, 0, 0.5);
}

.picker-sheet {
  border-radius: var(--radius) var(--radius) 0 0 !important;
  display: flex;
  flex-direction: column;
  max-height: 75vh;
  padding: 12px 0 calc(32px + var(--safe-bottom));
  width: 100%;
}

.sheet-handle {
  background: rgba(255, 255, 255, 0.2);
  border-radius: 2px;
  height: 4px;
  margin: 0 auto 16px;
  width: 40px;
}

.picker-hdr {
  align-items: center;
  display: flex;
  justify-content: space-between;
  padding: 0 var(--spacing) var(--spacing-sm);
}

.picker-title {
  font-size: 17px;
  font-weight: 600;
}

.close-x {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  height: var(--touch-min);
  justify-content: center;
  min-width: var(--touch-min);
  padding: 0;
}

.picker-tabs {
  display: flex;
  gap: 8px;
  padding: 0 var(--spacing) var(--spacing);
}

.ptab {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-full);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  flex: 1;
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
  gap: 6px;
  justify-content: center;
  min-height: 40px;
  padding: 0 14px;
  transition: 0.2s;
}

.ptab.active {
  background: rgba(59, 130, 246, 0.15);
  border-color: var(--primary);
  color: var(--primary);
  font-weight: 600;
}

.presets-grid {
  display: grid;
  flex: 1;
  gap: 10px;
  grid-template-columns: repeat(6, 1fr);
  overflow-y: auto;
  padding: 0 var(--spacing) var(--spacing);
}

.preset-btn {
  align-items: center;
  border: 2px solid transparent;
  border-radius: var(--radius-sm);
  cursor: pointer;
  display: flex;
  font-size: 24px;
  height: 48px;
  justify-content: center;
  transition: 0.15s;
}

.preset-btn.selected {
  border-color: var(--primary);
  background: var(--primary-soft) !important;
}

.upload-tab {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: var(--spacing);
  padding: 0 var(--spacing);
}

.upload-preview {
  border: 2px solid var(--border);
  border-radius: 50%;
  height: 112px;
  overflow: hidden;
  width: 112px;
}

.prev-img {
  height: 100%;
  object-fit: cover;
  width: 100%;
}

.prev-empty {
  align-items: center;
  background: var(--bg-card);
  display: flex;
  flex-direction: column;
  gap: 8px;
  height: 100%;
  justify-content: center;
  width: 100%;
}

.upload-btn {
  background: var(--primary);
  border: none;
  border-radius: var(--radius-sm);
  color: white;
  cursor: pointer;
  font-family: 'Cairo', sans-serif;
  font-size: 15px;
  font-weight: 600;
  min-height: var(--touch-min);
  padding: 0 var(--spacing);
  width: 100%;
}

.upload-btn:disabled {
  cursor: not-allowed;
  opacity: 0.6;
}

.upload-hint {
  text-align: center;
}

.avatar-picker-modal-enter-active,
.avatar-picker-modal-leave-active {
  transition: opacity 0.25s;
}

.avatar-picker-modal-enter-from,
.avatar-picker-modal-leave-to {
  opacity: 0;
}

.avatar-picker-modal-enter-active .picker-sheet,
.avatar-picker-modal-leave-active .picker-sheet {
  transition: transform 0.3s ease;
}

.avatar-picker-modal-enter-from .picker-sheet,
.avatar-picker-modal-leave-to .picker-sheet {
  transform: translateY(100%);
}
</style>
