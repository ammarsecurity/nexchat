<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const supportAvatar = ref(null)
const avatarUploading = ref(false)
const avatarFileInput = ref(null)

async function fetchSupportAvatar() {
  try {
    const res = await api.get('/admin/support/avatar')
    supportAvatar.value = res.data.avatar ?? null
  } catch {
    supportAvatar.value = null
  }
}

function triggerAvatarUpload() {
  avatarFileInput.value?.click()
}

async function onAvatarFileChange(e) {
  const file = e.target?.files?.[0]
  if (!file) return
  avatarUploading.value = true
  try {
    const fd = new FormData()
    fd.append('file', file)
    const res = await api.post('/media/upload', fd, {
      headers: { 'Content-Type': 'multipart/form-data' }
    })
    await api.put('/admin/support/avatar', { avatar: res.data.url })
    supportAvatar.value = res.data.url
  } catch (err) {
    alert(err.response?.data?.message || 'فشل رفع الصورة')
  } finally {
    avatarUploading.value = false
    e.target.value = ''
  }
}

function isAvatarUrl(av) {
  return av && (av.startsWith('http://') || av.startsWith('https://'))
}

onMounted(fetchSupportAvatar)
</script>

<template>
  <div class="settings-page">
    <div class="page-header mb-6">
      <div>
        <div class="text-h5 font-weight-bold">الإعدادات</div>
        <div class="text-body-2 text-medium-emphasis">
          إعدادات التطبيق والدعم
        </div>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="settings-card">
      <v-card-title class="section-title">
        <v-icon start>mdi-account-circle</v-icon>
        صورة الدعم الفني
      </v-card-title>
      <v-card-text>
        <div class="avatar-section">
          <div class="avatar-preview">
            <img v-if="isAvatarUrl(supportAvatar)" :src="supportAvatar" alt="دعم" class="avatar-img" />
            <span v-else class="avatar-placeholder">{{ supportAvatar || 'د' }}</span>
          </div>
          <div class="avatar-controls">
            <input
              ref="avatarFileInput"
              type="file"
              accept="image/*"
              class="d-none"
              @change="onAvatarFileChange"
            />
            <v-btn
              color="primary"
              variant="tonal"
              prepend-icon="mdi-camera"
              rounded="lg"
              :loading="avatarUploading"
              @click="triggerAvatarUpload"
            >
              رفع صورة
            </v-btn>
          </div>
        </div>
      </v-card-text>
    </v-card>
  </div>
</template>

<style scoped>
.settings-page {
  max-width: 800px;
}

.settings-card {
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.section-title {
  font-size: 1rem;
  font-weight: 600;
  padding: 20px 24px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}

.avatar-section {
  display: flex;
  align-items: flex-start;
  gap: 24px;
  padding: 24px 0;
}

.avatar-preview {
  width: 80px;
  height: 80px;
  border-radius: 16px;
  overflow: hidden;
  background: linear-gradient(135deg, #6C63FF, #FF6584);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.avatar-placeholder {
  font-size: 32px;
  font-weight: 700;
  color: white;
}

.avatar-controls {
  flex: 1;
}

@media (max-width: 600px) {
  .avatar-section {
    flex-direction: column;
  }
}
</style>
