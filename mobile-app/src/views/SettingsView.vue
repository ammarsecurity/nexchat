<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, LogOut, User, Key, Pencil, Image, Upload, X, Trash2, Shield, Copy, Users } from 'lucide-vue-next'
import { useAuthStore } from '../stores/auth'
import logoImg from '../assets/logo.png'
import api from '../services/api'

const router = useRouter()
const auth = useAuthStore()
const user = computed(() => auth.user)

const showAvatarPicker = ref(false)
const avatarTab = ref('preset')
const uploadingAvatar = ref(false)
const avatarFileInput = ref(null)
const showDeleteConfirm = ref(false)
const showDeletePassword = ref(false)
const deletePassword = ref('')
const deleteError = ref('')
const deleting = ref(false)
const copiedCode = ref(false)

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

function openDeleteConfirm() {
  showDeleteConfirm.value = true
  showDeletePassword.value = false
  deletePassword.value = ''
  deleteError.value = ''
}

function proceedToPassword() {
  showDeleteConfirm.value = false
  showDeletePassword.value = true
}

function copyCode() {
  if (user?.uniqueCode) {
    navigator.clipboard.writeText(user.uniqueCode)
    copiedCode.value = true
    setTimeout(() => { copiedCode.value = false }, 2000)
  }
}

async function confirmDelete() {
  if (!deletePassword.value) {
    deleteError.value = 'أدخل كلمة المرور'
    return
  }
  deleting.value = true
  deleteError.value = ''
  try {
    await api.delete('/user/account', { data: { password: deletePassword.value } })
    auth.logout()
    router.replace('/login')
  } catch (e) {
    deleteError.value = e.response?.data?.message || 'فشل حذف الحساب'
  } finally {
    deleting.value = false
  }
}
</script>

<template>
  <div class="settings page">
    <!-- Header -->
    <header class="top-bar">
      <button class="back-btn" @click="router.back()"><ChevronRight :size="22" /></button>
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
          <div class="edit-badge"><Pencil :size="14" /></div>
        </div>
        <div class="hero-name">{{ user?.name }}</div>
        <div class="hero-code gradient-text">{{ user?.uniqueCode }}</div>
        <div class="hero-gender text-muted text-sm">{{ genderLabel[user?.gender] || user?.gender }}</div>
      </div>

      <!-- Info -->
      <div class="section-label">معلومات الحساب</div>
      <div class="info-card glass-card">
        <div class="info-row">
          <span class="row-icon"><User :size="20" /></span>
          <div class="row-body">
            <div class="row-label">الاسم</div>
            <div class="row-val">{{ user?.name }}</div>
          </div>
        </div>
        <div class="sep"></div>
        <div class="info-row info-row-code" @click="copyCode">
          <span class="row-icon"><Key :size="20" /></span>
          <div class="row-body">
            <div class="row-label">الكود الفريد</div>
            <div class="row-val gradient-text code-val">{{ user?.uniqueCode }}</div>
          </div>
          <button type="button" class="copy-code-btn" :title="copiedCode ? 'تم النسخ' : 'نسخ'">
            <Copy v-if="!copiedCode" :size="18" />
            <span v-else class="copied-text">تم</span>
          </button>
        </div>
        <div class="sep"></div>
        <div class="info-row">
          <span class="row-icon"><Users :size="20" /></span>
          <div class="row-body">
            <div class="row-label">الجنس</div>
            <div class="row-val">{{ genderLabel[user?.gender] }}</div>
          </div>
        </div>
      </div>

      <!-- About -->
      <div class="section-label">عن التطبيق</div>
      <div class="about-card glass-card">
        <img :src="logoImg" alt="NexChat" class="about-logo-img" />
        <div class="text-muted text-sm" style="text-align:center">تواصل مع العالم بخطوة واحدة</div>
        <div class="ver-badge">v1.0.0</div>
      </div>

      <!-- Privacy Policy -->
      <RouterLink to="/privacy" class="link-row glass-card">
        <Shield :size="20" class="link-icon" />
        <span>سياسة الخصوصية</span>
        <ChevronRight :size="18" class="link-arrow" />
      </RouterLink>

      <!-- Logout -->
      <button class="logout-btn" @click="logout">
        <LogOut :size="20" />
        <span>تسجيل الخروج</span>
      </button>

      <!-- Delete Account -->
      <button class="delete-account-btn" @click="openDeleteConfirm">
        <Trash2 :size="20" />
        <span>حذف الحساب</span>
      </button>

    </div>

    <!-- Delete Confirm Dialog 1 - Warnings -->
    <Transition name="modal">
      <div v-if="showDeleteConfirm" class="modal-overlay delete-overlay" @click.self="showDeleteConfirm = false">
        <div class="delete-dialog glass-card">
          <div class="delete-dialog-icon">⚠️</div>
          <h3 class="delete-dialog-title">تنبيه: حذف الحساب نهائياً</h3>
          <p class="delete-dialog-text">
            سيتم حذف حسابك وجميع بياناتك بشكل نهائي ولا يمكن التراجع عنه:
          </p>
          <ul class="delete-dialog-list">
            <li>جميع المحادثات والرسائل</li>
            <li>سجل الجلسات والاتصالات</li>
            <li>معلومات الحساب الشخصية</li>
          </ul>
          <p class="delete-dialog-warn">هل أنت متأكد من المتابعة؟</p>
          <div class="delete-dialog-actions">
            <button class="btn-ghost" @click="showDeleteConfirm = false">إلغاء</button>
            <button class="delete-confirm-btn" @click="proceedToPassword">نعم، أريد الحذف</button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Delete Confirm Dialog 2 - Password -->
    <Transition name="modal">
      <div v-if="showDeletePassword" class="modal-overlay delete-overlay" @click.self="showDeletePassword = false">
        <div class="delete-dialog glass-card">
          <h3 class="delete-dialog-title">تأكيد الحذف</h3>
          <p class="delete-dialog-text">أدخل كلمة المرور لتأكيد حذف الحساب:</p>
          <input
            v-model="deletePassword"
            type="password"
            class="input-field"
            placeholder="كلمة المرور"
            @keyup.enter="confirmDelete"
          />
          <div v-if="deleteError" class="delete-error">{{ deleteError }}</div>
          <div class="delete-dialog-actions">
            <button class="btn-ghost" @click="showDeletePassword = false" :disabled="deleting">إلغاء</button>
            <button class="delete-confirm-btn" @click="confirmDelete" :disabled="deleting">
              {{ deleting ? 'جاري الحذف...' : 'حذف نهائياً' }}
            </button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Avatar Picker -->
    <Transition name="modal">
      <div v-if="showAvatarPicker" class="modal-overlay" @click.self="showAvatarPicker = false">
        <div class="picker-sheet glass-card">
          <div class="sheet-handle"></div>

          <div class="picker-hdr">
            <span class="picker-title">اختر أفاتار</span>
            <button class="close-x" @click="showAvatarPicker = false"><X :size="18" /></button>
          </div>

          <div class="picker-tabs">
            <button class="ptab" :class="{ active: avatarTab === 'preset' }" @click="avatarTab = 'preset'"><Image :size="16" /> جاهزة</button>
            <button class="ptab" :class="{ active: avatarTab === 'upload' }" @click="avatarTab = 'upload'"><Upload :size="16" /> رفع صورة</button>
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
                <Image :size="44" style="color: var(--text-muted)" />
                <span class="text-muted text-sm">لا توجد صورة</span>
              </div>
            </div>
            <input ref="avatarFileInput" type="file" accept="image/*" style="display:none" @change="handleAvatarUpload" />
            <button class="upload-btn" :disabled="uploadingAvatar" @click="avatarFileInput.click()">
              {{ uploadingAvatar ? 'جارٍ الرفع...' : 'اختر صورة' }}
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
}

.top-bar {
  align-items: center;
  display: flex;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 12px;
}
.back-btn {
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
  transition: background 0.2s;
}
.back-btn:active { background: var(--bg-card-hover); }
.top-title { font-size: 17px; font-weight: 600; }

.scroll-area {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-sm);
  overflow-y: auto;
  padding: 0 var(--spacing) calc(40px + var(--safe-bottom));
}

/* Hero */
.profile-hero {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: var(--spacing) 0;
}

.avatar-wrap {
  cursor: pointer;
  height: 96px;
  position: relative;
  width: 96px;
}
.avatar-img,
.avatar-circle {
  border: 2px solid var(--border);
  border-radius: 50%;
  height: 96px;
  width: 96px;
}
.avatar-img { object-fit: cover; display: block; }
.avatar-circle {
  align-items: center;
  display: flex;
  justify-content: center;
}
.av-letter { color: white; font-size: 36px; font-weight: 700; }
.av-emoji  { font-size: 48px; line-height: 1; }

.edit-badge {
  align-items: center;
  background: var(--primary);
  border-radius: 50%;
  bottom: 0;
  color: white;
  display: flex;
  height: 28px;
  justify-content: center;
  position: absolute;
  right: 0;
  width: 28px;
}

.hero-name { font-size: 20px; font-weight: 700; margin-top: 4px; }
.hero-code { font-size: 15px; font-weight: 600; letter-spacing: 2px; }

/* Section label */
.section-label {
  color: var(--text-muted);
  font-size: 12px;
  font-weight: 500;
  padding: 4px 0 0;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

/* Info card */
.info-card { overflow: hidden; padding: 0; }
.info-row {
  align-items: center;
  display: flex;
  gap: 14px;
  padding: var(--spacing) var(--spacing);
}
.row-icon { color: var(--text-muted); flex-shrink: 0; }
.row-body { flex: 1; min-width: 0; }
.row-label { color: var(--text-muted); font-size: 12px; margin-bottom: 2px; }
.row-val { font-size: 15px; font-weight: 600; }
.row-val.code-val { letter-spacing: 2px; font-weight: 800; }
.info-row-code { cursor: pointer; }
.info-row-code:active { background: var(--bg-card-hover); }
.copy-code-btn {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-muted);
  cursor: pointer;
  display: flex;
  height: 36px;
  justify-content: center;
  min-width: 36px;
  padding: 0;
  transition: color 0.2s, background 0.2s;
}
.copy-code-btn:active { background: var(--bg-card-hover); color: var(--primary); }
.copied-text { color: var(--success); font-size: 12px; font-weight: 600; }
.sep { background: var(--border); height: 1px; margin: 0 var(--spacing); }

/* About */
.about-card {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: var(--spacing);
}
.about-logo-img {
  height: 56px;
  width: auto;
  object-fit: contain;
}
.ver-badge {
  background: rgba(108,99,255,0.15);
  border: 1px solid rgba(108,99,255,0.2);
  border-radius: var(--radius-full);
  color: var(--primary);
  font-size: 12px;
  font-weight: 600;
  padding: 4px 14px;
}

/* Link row */
.link-row {
  align-items: center;
  color: var(--text-secondary);
  display: flex;
  gap: 12px;
  padding: var(--spacing);
  text-decoration: none;
  transition: background 0.2s;
}
.link-row:active { background: var(--bg-card-hover); }
.link-icon { color: var(--text-muted); flex-shrink: 0; }
.link-arrow { color: var(--text-muted); margin-right: auto; }

/* Delete account */
.delete-account-btn {
  align-items: center;
  background: transparent;
  border: 1px solid rgba(255,101,132,0.25);
  border-radius: var(--radius);
  color: var(--danger);
  cursor: pointer;
  display: flex;
  font-family: 'Cairo';
  font-size: 14px;
  font-weight: 600;
  gap: 10px;
  justify-content: center;
  margin-top: 16px;
  min-height: 44px;
  padding: 0 var(--spacing);
  transition: background 0.2s;
}
.delete-account-btn:active { background: rgba(255,101,132,0.1); }

/* Delete dialog */
.delete-overlay { align-items: center; justify-content: center; }
.delete-dialog {
  margin: var(--spacing);
  max-width: 360px;
  padding: var(--spacing);
  width: 100%;
}
.delete-dialog-icon { font-size: 48px; text-align: center; margin-bottom: 8px; }
.delete-dialog-title { font-size: 18px; font-weight: 700; margin-bottom: 12px; text-align: center; }
.delete-dialog-text { font-size: 14px; color: var(--text-secondary); margin-bottom: 12px; line-height: 1.5; }
.delete-dialog-list {
  color: var(--text-muted);
  font-size: 13px;
  margin: 0 0 16px 20px;
  padding: 0;
}
.delete-dialog-warn { font-size: 14px; font-weight: 600; color: var(--danger); margin-bottom: 16px; text-align: center; }
.delete-dialog-actions { display: flex; gap: 12px; }
.delete-confirm-btn {
  background: var(--danger);
  border: none;
  border-radius: var(--radius-sm);
  color: white;
  cursor: pointer;
  flex: 1;
  font-family: 'Cairo';
  font-size: 14px;
  font-weight: 600;
  min-height: 44px;
  padding: 0;
}
.delete-confirm-btn:disabled { opacity: 0.6; cursor: not-allowed; }
.delete-error { color: var(--danger); font-size: 13px; margin-bottom: 8px; }

/* Logout */
.logout-btn {
  align-items: center;
  background: rgba(255,101,132,0.1);
  border: 1px solid rgba(255,101,132,0.2);
  border-radius: var(--radius);
  color: var(--danger);
  cursor: pointer;
  display: flex;
  font-family: 'Cairo';
  font-size: 15px;
  font-weight: 600;
  gap: 10px;
  justify-content: center;
  margin-top: 4px;
  min-height: var(--touch-min);
  padding: 0 var(--spacing);
  transition: background 0.2s;
}
.logout-btn:active { background: rgba(255,101,132,0.18); }

/* Modal */
.modal-overlay {
  align-items: flex-end;
  background: rgba(0,0,0,0.5);
  bottom: 0;
  display: flex;
  left: 0;
  position: absolute;
  right: 0;
  top: 0;
  z-index: 200;
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
  background: rgba(255,255,255,0.2);
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
.picker-title { font-size: 17px; font-weight: 600; }
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
  font-size: 14px;
  gap: 6px;
  justify-content: center;
  min-height: 40px;
  padding: 0 14px;
  transition: 0.2s;
}
.ptab.active {
  background: rgba(108,99,255,0.2);
  border-color: var(--primary);
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
.preset-btn:active { opacity: 0.9; }
.preset-btn.selected { border-color: var(--primary); background: rgba(108,99,255,0.15) !important; }

/* Upload tab */
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
.prev-img { height: 100%; object-fit: cover; width: 100%; }
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
  font-size: 15px;
  font-weight: 600;
  min-height: var(--touch-min);
  padding: 0 var(--spacing);
  transition: opacity 0.2s;
  width: 100%;
}
.upload-btn:disabled { cursor: not-allowed; opacity: 0.6; }
.upload-btn:not(:disabled):active { opacity: 0.9; }

/* Transitions */
.modal-enter-active, .modal-leave-active { transition: opacity 0.25s; }
.modal-enter-from, .modal-leave-to { opacity: 0; }
.modal-enter-active .picker-sheet { transition: transform 0.3s ease; }
.modal-leave-active .picker-sheet { transition: transform 0.25s ease; }
.modal-enter-from .picker-sheet, .modal-leave-to .picker-sheet { transform: translateY(100%); }
</style>
