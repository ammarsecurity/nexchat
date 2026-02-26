<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const router = useRouter()
const auth = useAuthStore()
const user = computed(() => auth.user)

const showAvatarPicker = ref(false)
const avatarTab = ref('preset')
const uploadingAvatar = ref(false)
const avatarFileInput = ref(null)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

const genderLabel = { male: 'ذكر', female: 'أنثى', other: 'آخر' }

const presetAvatars = [
  '🦊','🐺','🦁','🐯','🐻','🐼','🐨','🦋',
  '🦅','🐬','🦈','🐙','🌟','🎭','🎯','🎮',
  '🚀','⚡','🔥','💎','👑','🤖','👻','🎃',
  '🌈','🌊','🌺','🍀','⭐','🎵'
]

const isImageUrl = (v) => v && (v.startsWith('http') || v.startsWith('/'))
const isEmoji   = (v) => v && !isImageUrl(v)

function selectPreset(emoji) {
  auth.setAvatar(emoji)
  showAvatarPicker.value = false
}

async function handleAvatarUpload(e) {
  const file = e.target.files[0]
  if (!file) return
  avatarFileInput.value.value = ''
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
    auth.setAvatar(url)
    showAvatarPicker.value = false
  } finally {
    uploadingAvatar.value = false
  }
}

function logout() {
  auth.logout()
  router.replace('/login')
}
</script>

<template>
  <div class="settings page">
    <div class="orb orb-1"></div>
    <div class="orb orb-2"></div>

    <!-- Header -->
    <header class="top-bar">
      <button class="back-btn" @click="router.back()">←</button>
      <span class="top-title">الإعدادات</span>
      <div style="width:40px"></div>
    </header>

    <div class="scroll-area">

      <!-- Profile Hero -->
      <div class="profile-hero">
        <div class="avatar-wrap" @click="showAvatarPicker = true">
          <img v-if="isImageUrl(auth.avatar)" :src="auth.avatar" class="avatar-img" />
          <div v-else-if="isEmoji(auth.avatar)" class="avatar-circle" :style="{ background: auth.avatarColor }">
            <span class="av-emoji">{{ auth.avatar }}</span>
          </div>
          <div v-else class="avatar-circle" :style="{ background: auth.avatarColor }">
            <span class="av-letter">{{ user?.name?.[0]?.toUpperCase() }}</span>
          </div>
          <div class="edit-badge">✏️</div>
        </div>
        <div class="hero-name">{{ user?.name }}</div>
        <div class="hero-code gradient-text">{{ user?.uniqueCode }}</div>
        <div class="hero-gender text-muted text-sm">{{ genderLabel[user?.gender] || user?.gender }}</div>
      </div>

      <!-- Info -->
      <div class="section-label">معلومات الحساب</div>
      <div class="info-card glass-card">
        <div class="info-row">
          <span class="row-icon">👤</span>
          <div class="row-body">
            <div class="row-label">الاسم</div>
            <div class="row-val">{{ user?.name }}</div>
          </div>
        </div>
        <div class="sep"></div>
        <div class="info-row">
          <span class="row-icon">🔑</span>
          <div class="row-body">
            <div class="row-label">الكود الفريد</div>
            <div class="row-val gradient-text" style="letter-spacing:2px;font-weight:800">{{ user?.uniqueCode }}</div>
          </div>
        </div>
        <div class="sep"></div>
        <div class="info-row">
          <span class="row-icon">{{ user?.gender === 'male' ? '👨' : user?.gender === 'female' ? '👩' : '🧑' }}</span>
          <div class="row-body">
            <div class="row-label">الجنس</div>
            <div class="row-val">{{ genderLabel[user?.gender] }}</div>
          </div>
        </div>
      </div>

      <!-- About -->
      <div class="section-label">عن التطبيق</div>
      <div class="about-card glass-card">
        <div class="about-logo">
          <div class="logo-n">N</div>
          <span class="gradient-text" style="font-size:20px;font-weight:800">NexChat</span>
        </div>
        <div class="text-muted text-sm" style="text-align:center">تواصل مع العالم بخطوة واحدة</div>
        <div class="ver-badge">v1.0.0</div>
      </div>

      <!-- Logout -->
      <button class="logout-btn" @click="logout">
        <span>🚪</span><span>تسجيل الخروج</span>
      </button>

    </div>

    <!-- Avatar Picker -->
    <Transition name="modal">
      <div v-if="showAvatarPicker" class="modal-overlay" @click.self="showAvatarPicker = false">
        <div class="picker-sheet glass-card">
          <div class="sheet-handle"></div>

          <div class="picker-hdr">
            <span class="picker-title">اختر أفاتار</span>
            <button class="close-x" @click="showAvatarPicker = false">✕</button>
          </div>

          <div class="picker-tabs">
            <button class="ptab" :class="{ active: avatarTab === 'preset' }" @click="avatarTab = 'preset'">🎨 جاهزة</button>
            <button class="ptab" :class="{ active: avatarTab === 'upload' }" @click="avatarTab = 'upload'">📷 رفع صورة</button>
          </div>

          <!-- Presets -->
          <div v-if="avatarTab === 'preset'" class="presets-grid">
            <button
              v-for="emoji in presetAvatars"
              :key="emoji"
              class="preset-btn"
              :class="{ selected: auth.avatar === emoji }"
              :style="{ background: auth.avatarColor }"
              @click="selectPreset(emoji)"
            >{{ emoji }}</button>
          </div>

          <!-- Upload -->
          <div v-else class="upload-tab">
            <div class="upload-preview">
              <img v-if="isImageUrl(auth.avatar)" :src="auth.avatar" class="prev-img" />
              <div v-else class="prev-empty">
                <span style="font-size:44px">📷</span>
                <span class="text-muted text-sm">لا توجد صورة</span>
              </div>
            </div>
            <input ref="avatarFileInput" type="file" accept="image/*" style="display:none" @change="handleAvatarUpload" />
            <button class="upload-btn" :disabled="uploadingAvatar" @click="avatarFileInput.click()">
              {{ uploadingAvatar ? '⏳ جارٍ الرفع...' : '📤 اختر صورة' }}
            </button>
            <div class="text-muted text-sm" style="text-align:center">الحد الأقصى 5 ميجابايت • JPG, PNG, GIF</div>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.settings {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  position: relative;
}

.orb {
  border-radius: 50%;
  filter: blur(80px);
  pointer-events: none;
  position: absolute;
}
.orb-1 { background: rgba(108,99,255,0.15); width:280px; height:280px; top:-80px; right:-60px; }
.orb-2 { background: rgba(255,101,132,0.1); width:220px; height:220px; bottom:80px; left:-60px; }

.top-bar {
  align-items: center;
  display: flex;
  justify-content: space-between;
  padding: 20px 20px 12px;
  position: relative;
  z-index: 10;
}
.back-btn {
  align-items: center;
  background: rgba(255,255,255,0.07);
  border: 1px solid var(--border);
  border-radius: 10px;
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  font-size: 16px;
  height: 36px;
  justify-content: center;
  width: 40px;
  transition: 0.2s;
}
.back-btn:hover { background: rgba(255,255,255,0.12); }
.top-title { font-size: 17px; font-weight: 700; }

.scroll-area {
  display: flex;
  flex-direction: column;
  gap: 12px;
  overflow-y: auto;
  padding: 0 20px 40px;
  position: relative;
  z-index: 10;
}

/* Hero */
.profile-hero {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 20px 0 12px;
}

.avatar-wrap {
  cursor: pointer;
  height: 100px;
  position: relative;
  width: 100px;
}
.avatar-img,
.avatar-circle {
  border: 3px solid rgba(108,99,255,0.4);
  border-radius: 50%;
  box-shadow: 0 0 28px rgba(108,99,255,0.35);
  height: 100px;
  width: 100px;
}
.avatar-img { object-fit: cover; display: block; }
.avatar-circle {
  align-items: center;
  display: flex;
  justify-content: center;
}
.av-letter { color: white; font-size: 38px; font-weight: 700; }
.av-emoji  { font-size: 50px; line-height: 1; }

.edit-badge {
  align-items: center;
  background: var(--gradient);
  border-radius: 50%;
  bottom: 2px;
  box-shadow: 0 2px 8px rgba(0,0,0,0.35);
  display: flex;
  font-size: 13px;
  height: 28px;
  justify-content: center;
  position: absolute;
  right: 2px;
  width: 28px;
}

.hero-name { font-size: 22px; font-weight: 800; margin-top: 4px; }
.hero-code { font-size: 16px; font-weight: 700; letter-spacing: 2px; }

/* Section label */
.section-label {
  color: var(--text-muted);
  font-size: 12px;
  font-weight: 500;
  padding: 4px 4px 0;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

/* Info card */
.info-card { overflow: hidden; padding: 0; }
.info-row {
  align-items: center;
  display: flex;
  gap: 14px;
  padding: 15px 18px;
}
.row-icon { flex-shrink: 0; font-size: 20px; }
.row-label { color: var(--text-muted); font-size: 11px; margin-bottom: 3px; }
.row-val { font-size: 15px; font-weight: 600; }
.sep { background: var(--border); height: 1px; margin: 0 18px; }

/* About */
.about-card {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 20px;
}
.about-logo { align-items: center; display: flex; gap: 10px; }
.logo-n {
  align-items: center;
  background: var(--gradient);
  border-radius: 10px;
  color: white;
  display: flex;
  font-size: 20px;
  font-weight: 900;
  height: 36px;
  justify-content: center;
  width: 36px;
}
.ver-badge {
  background: rgba(108,99,255,0.15);
  border: 1px solid rgba(108,99,255,0.25);
  border-radius: 20px;
  color: #6C63FF;
  font-size: 12px;
  font-weight: 600;
  padding: 3px 14px;
}

/* Logout */
.logout-btn {
  align-items: center;
  background: rgba(255,101,132,0.08);
  border: 1px solid rgba(255,101,132,0.2);
  border-radius: var(--radius);
  color: #FF6584;
  cursor: pointer;
  display: flex;
  font-size: 15px;
  font-weight: 600;
  gap: 10px;
  justify-content: center;
  margin-top: 4px;
  padding: 16px;
  transition: 0.2s;
}
.logout-btn:hover { background: rgba(255,101,132,0.15); }

/* Modal */
.modal-overlay {
  align-items: flex-end;
  backdrop-filter: blur(4px);
  background: rgba(0,0,0,0.55);
  bottom: 0;
  display: flex;
  left: 0;
  position: absolute;
  right: 0;
  top: 0;
  z-index: 200;
}

.picker-sheet {
  border-radius: 24px 24px 0 0 !important;
  display: flex;
  flex-direction: column;
  max-height: 75vh;
  padding: 12px 0 32px;
  width: 100%;
}

.sheet-handle {
  background: rgba(255,255,255,0.15);
  border-radius: 3px;
  height: 4px;
  margin: 0 auto 16px;
  width: 40px;
}

.picker-hdr {
  align-items: center;
  display: flex;
  justify-content: space-between;
  padding: 0 20px 12px;
}
.picker-title { font-size: 17px; font-weight: 700; }
.close-x {
  background: rgba(255,255,255,0.08);
  border: none;
  border-radius: 8px;
  color: var(--text-secondary);
  cursor: pointer;
  font-size: 14px;
  padding: 6px 10px;
}

.picker-tabs {
  display: flex;
  gap: 8px;
  padding: 0 20px 16px;
}
.ptab {
  background: rgba(255,255,255,0.06);
  border: 1px solid var(--border);
  border-radius: var(--radius-full);
  color: var(--text-secondary);
  cursor: pointer;
  flex: 1;
  font-size: 13px;
  padding: 8px 14px;
  transition: 0.2s;
}
.ptab.active {
  background: rgba(108,99,255,0.2);
  border-color: #6C63FF;
  color: white;
  font-weight: 600;
}

/* Presets */
.presets-grid {
  display: grid;
  flex: 1;
  gap: 10px;
  grid-template-columns: repeat(6, 1fr);
  overflow-y: auto;
  padding: 0 20px 8px;
}
.preset-btn {
  align-items: center;
  border: 2px solid transparent;
  border-radius: 14px;
  cursor: pointer;
  display: flex;
  font-size: 26px;
  height: 50px;
  justify-content: center;
  transition: 0.15s;
}
.preset-btn:hover { transform: scale(1.12); }
.preset-btn:active { transform: scale(0.93); }
.preset-btn.selected { border-color: white; box-shadow: 0 0 14px rgba(108,99,255,0.6); }

/* Upload tab */
.upload-tab {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding: 0 20px;
}
.upload-preview {
  border: 2px solid var(--border);
  border-radius: 50%;
  height: 120px;
  overflow: hidden;
  width: 120px;
}
.prev-img { height: 100%; object-fit: cover; width: 100%; }
.prev-empty {
  align-items: center;
  background: var(--bg-card);
  display: flex;
  flex-direction: column;
  gap: 4px;
  height: 100%;
  justify-content: center;
  width: 100%;
}
.upload-btn {
  background: var(--gradient);
  border: none;
  border-radius: var(--radius-full);
  color: white;
  cursor: pointer;
  font-size: 15px;
  font-weight: 600;
  padding: 14px;
  transition: 0.2s;
  width: 100%;
}
.upload-btn:disabled { cursor: not-allowed; opacity: 0.6; }
.upload-btn:not(:disabled):hover { opacity: 0.9; }

/* Transitions */
.modal-enter-active, .modal-leave-active { transition: opacity 0.25s; }
.modal-enter-from, .modal-leave-to { opacity: 0; }
.modal-enter-active .picker-sheet { transition: transform 0.3s ease; }
.modal-leave-active .picker-sheet { transition: transform 0.25s ease; }
.modal-enter-from .picker-sheet, .modal-leave-to .picker-sheet { transform: translateY(100%); }
</style>
