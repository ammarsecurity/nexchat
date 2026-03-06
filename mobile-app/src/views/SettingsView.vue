<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, LogOut, Pencil, Image, Upload, X, Trash2, Shield, Copy, MessageCircle, Sun, Moon, AlertCircle, Bell, Camera, Mic, Hash, Globe, BookmarkPlus, Send, Crown, Calendar, Download, RefreshCw } from 'lucide-vue-next'
import { useAuthStore } from '../stores/auth'
import { useLocaleStore } from '../stores/locale'
import { useI18n } from 'vue-i18n'
import { i18n } from '../i18n'
import { useThemeStore } from '../stores/theme'
import { useChatStore } from '../stores/chat'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import PrivacyBadge from '../components/PrivacyBadge.vue'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { requestMediaPermissions } from '../utils/mediaPermissions'
import { optInNotifications, optOutNotifications, getNotificationsEnabled, requestPermissionAndRegister } from '../services/notifications'
import { Capacitor } from '@capacitor/core'
import { fetchUpdateInfo } from '../services/updateCheck'

const router = useRouter()
const auth = useAuthStore()
const chat = useChatStore()
const localeStore = useLocaleStore()
const { t } = useI18n()
const theme = useThemeStore()
const user = computed(() => auth.user)
const logoImg = computed(() => theme.isLight ? '/logo-light.png' : '/logo.png')
const supportLoading = ref(false)

const showAvatarPicker = ref(false)
const avatarTab = ref('preset')
const uploadingAvatar = ref(false)
const avatarFileInput = ref(null)
const showLogoutConfirm = ref(false)
const showDeleteConfirm = ref(false)
const showDeletePassword = ref(false)
const deletePassword = ref('')
const deleteError = ref('')
const deleting = ref(false)
const copiedCode = ref(false)
const mediaPermLoading = ref(false)
const profileData = ref(null)
const showBirthDateModal = ref(false)
const birthDay = ref('')
const birthMonth = ref('')
const birthYear = ref('')
const birthDateSaving = ref(false)
const birthDateError = ref('')
const mediaPermMessage = ref('')
const mediaPermSuccess = ref(true)
const notificationsEnabled = ref(true)
const isNative = Capacitor.isNativePlatform()
const updateInfo = ref(null)
const updateChecking = ref(false)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

async function loadNotificationsState() {
  if (isNative) {
    notificationsEnabled.value = await getNotificationsEnabled()
  }
}

async function enableNotifications() {
  if (!isNative) return
  await requestPermissionAndRegister()
  notificationsEnabled.value = true
}

function disableNotifications() {
  if (!isNative) return
  optOutNotifications()
  notificationsEnabled.value = false
}

async function requestMediaPerms() {
  mediaPermLoading.value = true
  mediaPermMessage.value = ''
  try {
    await requestMediaPermissions()
    mediaPermMessage.value = t('settings.permissionsVerified')
    mediaPermSuccess.value = true
  } catch {
    mediaPermMessage.value = t('settings.permissionsFailed')
    mediaPermSuccess.value = false
  }
  setTimeout(() => { mediaPermMessage.value = '' }, 4000)
  mediaPermLoading.value = false
}

const genderLabel = computed(() => ({
  male: t('gender.male'),
  female: t('gender.female'),
  other: t('gender.other')
}))

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

function openLogoutConfirm() {
  showLogoutConfirm.value = true
}

function confirmLogout() {
  showLogoutConfirm.value = false
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
  const code = user.value?.uniqueCode
  if (code) {
    navigator.clipboard.writeText(code)
    copiedCode.value = true
    setTimeout(() => { copiedCode.value = false }, 2000)
  }
}

async function openSupportChat() {
  supportLoading.value = true
  try {
    const res = await api.get('/support/session')
    const { sessionId, partner } = res.data
    chat.setSession(sessionId, partner)
    router.push(`/chat/${sessionId}`)
  } catch (e) {
    console.error(e)
  } finally {
    supportLoading.value = false
  }
}

async function confirmDelete() {
  if (!deletePassword.value) {
    deleteError.value = t('settings.enterPassword')
    return
  }
  deleting.value = true
  deleteError.value = ''
  try {
    await api.delete('/user/account', { data: { password: deletePassword.value } })
    auth.logout()
    router.replace('/login')
  } catch (e) {
    deleteError.value = e.response?.data?.message || t('settings.deleteFailed')
  } finally {
    deleting.value = false
  }
}

const months = computed(() => Array.from({ length: 12 }, (_, i) => i + 1))
const years = computed(() => {
  const currentYear = new Date().getFullYear()
  const maxYear = currentYear - 18
  const minYear = currentYear - 120
  return Array.from({ length: maxYear - minYear + 1 }, (_, i) => maxYear - i)
})
const daysInMonth = computed(() => {
  const m = parseInt(birthMonth.value, 10)
  const y = parseInt(birthYear.value, 10)
  if (!m) return 31
  const isLeap = y && (y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0))
  const days = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  return days[m - 1] ?? 31
})
const validDays = computed(() => Array.from({ length: daysInMonth.value }, (_, i) => i + 1))

watch([birthMonth, birthYear], () => {
  const d = parseInt(birthDay.value, 10)
  if (d > daysInMonth.value) birthDay.value = String(daysInMonth.value)
})
const birthDateStr = computed(() => {
  if (!birthDay.value || !birthMonth.value || !birthYear.value) return ''
  const d = String(birthDay.value).padStart(2, '0')
  const m = String(birthMonth.value).padStart(2, '0')
  return `${birthYear.value}-${m}-${d}`
})
const formattedBirthDate = computed(() => {
  const b = profileData.value?.birthDate
  if (!b) return null
  const [y, m, d] = b.split('-').map(Number)
  return `${d}/${m}/${y}`
})

async function loadProfile() {
  try {
    const res = await api.get('/user/me')
    profileData.value = res.data
  } catch {}
}

function openBirthDateModal() {
  const b = profileData.value?.birthDate
  if (b) {
    const [y, m, d] = b.split('-').map(Number)
    birthYear.value = y
    birthMonth.value = m
    birthDay.value = d
  } else {
    birthYear.value = ''
    birthMonth.value = ''
    birthDay.value = ''
  }
  birthDateError.value = ''
  showBirthDateModal.value = true
}

async function saveBirthDate() {
  if (!birthDateStr.value) return
  birthDateSaving.value = true
  birthDateError.value = ''
  try {
    await api.put('/user/birth-date', { birthDate: birthDateStr.value })
    profileData.value = { ...profileData.value, birthDate: birthDateStr.value }
    showBirthDateModal.value = false
  } catch (e) {
    birthDateError.value = e.response?.data?.message || t('common.error')
  } finally {
    birthDateSaving.value = false
  }
}

async function checkForUpdate() {
  updateChecking.value = true
  updateInfo.value = null
  try {
    updateInfo.value = await fetchUpdateInfo()
  } catch {}
  updateChecking.value = false
}

function openUpdateUrl() {
  const url = updateInfo.value?.downloadUrl
  if (!url) return
  if (Capacitor.isNativePlatform()) {
    window.open(url, '_system')
  } else {
    window.open(url, '_blank')
  }
}

onMounted(() => {
  loadNotificationsState()
  loadProfile()
  checkForUpdate()
})
</script>

<template>
  <div class="settings page">
    <LoaderOverlay :show="uploadingAvatar" :text="t('settings.uploadingImage')" />
    <LoaderOverlay :show="deleting" :text="t('settings.deletingAccount')" />
    <LoaderOverlay :show="supportLoading" :text="t('settings.openingSupport')" />
    <!-- Header -->
    <header class="top-bar">
      <button class="back-btn" @click="router.replace('/home')"><ChevronRight :size="22" /></button>
      <span class="top-title">{{ t('settings.title') }}</span>
      <div style="width:40px"></div>
    </header>

    <div class="scroll-area">

      <!-- 1. Profile Card -->
      <div class="profile-card glass-card">
        <div class="profile-card-inner">
          <div class="avatar-wrap" :class="{ 'avatar-wrap-featured': user?.isFeatured }" @click="showAvatarPicker = true">
            <img v-if="isImageUrl(auth.avatar)" :src="ensureAbsoluteUrl(auth.avatar)" class="avatar-img" referrerpolicy="no-referrer" />
            <div v-else-if="isEmoji(auth.avatar)" class="avatar-circle" :style="{ background: auth.avatarColor }">
              <span class="av-emoji">{{ auth.avatar }}</span>
            </div>
            <div v-else class="avatar-circle" :style="{ background: auth.avatarColor }">
              <span class="av-letter">{{ user?.name?.[0]?.toUpperCase() }}</span>
            </div>
            <Crown v-if="user?.isFeatured" class="avatar-crown-settings" :size="20" fill="currentColor" stroke-width="1" />
            <div class="edit-badge"><Pencil :size="12" /></div>
          </div>
          <div class="profile-details">
            <div class="profile-name">{{ user?.name }}</div>
            <span class="profile-gender-badge">{{ genderLabel[user?.gender] ?? user?.gender }}</span>
          </div>
        </div>
      </div>

      <!-- كود الاتصال - بطاقة منفصلة -->
      <div class="profile-code-card glass-card" @click="copyCode">
        <div class="profile-code-icon-wrap">
          <Hash :size="22" />
        </div>
        <div class="profile-code-text">
          <span class="profile-code-title">{{ t('settings.contactCode') }}</span>
          <span class="profile-code-value">{{ user?.uniqueCode }}</span>
        </div>
        <button type="button" class="profile-code-copy-btn" :title="copiedCode ? t('common.copied') : t('common.copy')" @click.stop="copyCode">
          <Copy v-if="!copiedCode" :size="18" stroke-width="2" />
          <span v-else class="copied-text">{{ t('common.copiedShort') }}</span>
        </button>
      </div>

      <!-- تاريخ الميلاد -->
      <div class="profile-code-card glass-card birth-date-card" @click="openBirthDateModal">
        <div class="profile-code-icon-wrap">
          <Calendar :size="22" />
        </div>
        <div class="profile-code-text">
          <span class="profile-code-title">{{ t('settings.birthDate') }}</span>
          <span class="profile-code-value">{{ formattedBirthDate ?? t('settings.birthDateNotSet') }}</span>
        </div>
        <ChevronRight :size="20" class="link-arrow" />
      </div>

      <!-- Privacy badge -->
      <div class="privacy-badge-wrap">
        <PrivacyBadge />
      </div>

      <!-- Support Chat - بارز -->
      <div class="support-card glass-card">
        <button class="support-row" :disabled="supportLoading" @click="openSupportChat">
          <div class="support-icon-wrap">
            <MessageCircle :size="22" />
          </div>
          <div class="support-text">
            <span class="support-title">{{ t('settings.supportChat') }}</span>
            <span class="support-desc">{{ t('settings.supportDesc') }}</span>
          </div>
          <ChevronRight :size="20" class="link-arrow" />
        </button>
      </div>

      <!-- 2. Permissions -->
      <div class="section-label">{{ t('settings.permissions') }}</div>
      <div class="links-group glass-card">
        <button class="link-row" :disabled="mediaPermLoading" @click="requestMediaPerms">
          <div class="link-icon-wrap perm-icon"><Camera :size="20" /><Mic :size="14" class="mic-overlay" /></div>
          <div class="link-text-col">
            <span>{{ t('settings.cameraMicPermissions') }}</span>
            <span class="link-desc">{{ t('settings.cameraMicDesc') }}</span>
          </div>
          <span v-if="mediaPermMessage" class="perm-feedback" :class="mediaPermSuccess ? 'success' : 'error'">{{ mediaPermMessage }}</span>
          <ChevronRight v-else :size="18" class="link-arrow" />
        </button>
      </div>

      <!-- 3. Settings Links -->
      <div class="section-label">{{ t('settings.general') }}</div>
      <div class="links-group glass-card">
        <button class="link-row" @click="localeStore.toggleLocale(i18n)">
          <Globe :size="20" class="link-icon" />
          <span>{{ t('settings.language') }}</span>
          <span class="theme-badge">{{ localeStore.locale === 'ar' ? 'عربي' : 'English' }}</span>
        </button>
        <button class="link-row theme-toggle-row" @click="theme.toggleTheme">
          <Sun v-if="!theme.isLight" :size="20" class="link-icon" />
          <Moon v-else :size="20" class="link-icon" />
          <span>{{ theme.isLight ? t('settings.darkMode') : t('settings.lightMode') }}</span>
          <span class="theme-badge">{{ theme.isLight ? t('settings.dark') : t('settings.light') }}</span>
        </button>
        <div class="notif-buttons-row">
          <span class="notif-label"><Bell :size="20" class="link-icon" /> {{ t('settings.notifications') }}</span>
          <template v-if="isNative">
            <div class="notif-btns">
              <button
                class="notif-btn enable"
                :class="{ active: notificationsEnabled }"
                :disabled="notificationsEnabled"
                @click="enableNotifications"
              >
                {{ t('settings.enable') }}
              </button>
              <button
                class="notif-btn disable"
                :class="{ active: !notificationsEnabled }"
                :disabled="!notificationsEnabled"
                @click="disableNotifications"
              >
                {{ t('settings.disable') }}
              </button>
            </div>
          </template>
          <span v-else class="notif-web-msg">{{ t('settings.notifWebOnly') }}</span>
        </div>
        <RouterLink to="/notifications" class="link-row">
          <Bell :size="20" class="link-icon" />
          <span>{{ t('settings.notificationCenter') }}</span>
          <ChevronRight :size="18" class="link-arrow" />
        </RouterLink>
        <RouterLink to="/connection-history" class="link-row">
          <Send :size="20" class="link-icon" />
          <span>{{ t('connectionHistory.title') }}</span>
          <ChevronRight :size="18" class="link-arrow" />
        </RouterLink>
        <RouterLink v-if="user?.isFeatured" to="/saved-codes" class="link-row">
          <BookmarkPlus :size="20" class="link-icon" />
          <span>{{ t('home.savedCodes') }}</span>
          <ChevronRight :size="18" class="link-arrow" />
        </RouterLink>
        <RouterLink to="/privacy" class="link-row">
          <Shield :size="20" class="link-icon" />
          <span>{{ t('settings.privacyPolicy') }}</span>
          <ChevronRight :size="18" class="link-arrow" />
        </RouterLink>
      </div>

      <!-- 4. App / Update -->
      <div class="section-label">{{ t('settings.app') }}</div>
      <div v-if="updateInfo?.hasUpdate && updateInfo?.downloadUrl" class="support-card glass-card update-available-card">
        <button class="support-row" @click="openUpdateUrl">
          <div class="support-icon-wrap update-icon-wrap">
            <Download :size="22" />
          </div>
          <div class="support-text">
            <span class="support-title">{{ t('settings.updateAvailable') }}</span>
            <span class="support-desc">{{ t('settings.updateAvailableDesc') }}</span>
          </div>
          <ChevronRight :size="20" class="link-arrow" />
        </button>
      </div>
      <div v-if="isNative" class="links-group glass-card">
        <button class="link-row" :disabled="updateChecking" @click="checkForUpdate">
          <RefreshCw :size="20" class="link-icon" :class="{ 'spin': updateChecking }" />
          <span>{{ updateChecking ? t('settings.checkingUpdate') : t('settings.checkForUpdate') }}</span>
          <ChevronRight v-if="!updateChecking" :size="18" class="link-arrow" />
        </button>
      </div>
      <div class="about-card glass-card">
        <div class="about-inner">
          <img :src="logoImg" alt="NexChat" class="about-logo-img" />
          <div class="about-text">
            <div class="about-name">NexChat</div>
            <div class="about-tagline text-muted text-sm">{{ t('settings.tagline') }}</div>
            <span class="ver-badge">v1.0.1</span>
          </div>
        </div>
      </div>

      <!-- 5. Account Actions -->
      <div class="section-label">{{ t('settings.account') }}</div>
      <div class="actions-group">
        <button class="logout-btn" @click="openLogoutConfirm">
          <LogOut :size="20" />
          <span>{{ t('home.logout') }}</span>
        </button>
        <button class="delete-account-btn" @click="openDeleteConfirm">
          <Trash2 :size="20" />
          <span>{{ t('settings.deleteAccount') }}</span>
        </button>
      </div>
    </div>

    <!-- Logout Confirm Dialog -->
    <Transition name="modal">
      <div v-if="showLogoutConfirm" class="modal-overlay delete-overlay" @click.self="showLogoutConfirm = false">
        <div class="delete-dialog glass-card">
          <div class="delete-dialog-icon"><LogOut :size="48" stroke-width="2" /></div>
          <h3 class="delete-dialog-title">{{ t('home.logoutConfirm') }}</h3>
          <p class="delete-dialog-text">{{ t('home.logoutConfirmText') }}</p>
          <div class="delete-dialog-actions">
            <button class="btn-ghost" @click="showLogoutConfirm = false">{{ t('common.cancel') }}</button>
            <button class="logout-confirm-btn" @click="confirmLogout">{{ t('home.logout') }}</button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Delete Confirm Dialog 1 - Warnings -->
    <Transition name="modal">
      <div v-if="showDeleteConfirm" class="modal-overlay delete-overlay" @click.self="showDeleteConfirm = false">
        <div class="delete-dialog glass-card">
          <div class="delete-dialog-icon">⚠️</div>
          <h3 class="delete-dialog-title">{{ t('settings.deleteAccountWarning') }}</h3>
          <p class="delete-dialog-text">
            {{ t('settings.deleteAccountText') }}
          </p>
          <ul class="delete-dialog-list">
            <li>{{ t('settings.deleteAccountList1') }}</li>
            <li>{{ t('settings.deleteAccountList2') }}</li>
            <li>{{ t('settings.deleteAccountList3') }}</li>
          </ul>
          <p class="delete-dialog-warn">{{ t('settings.deleteAccountConfirm') }}</p>
          <div class="delete-dialog-actions">
            <button class="btn-ghost" @click="showDeleteConfirm = false">{{ t('common.cancel') }}</button>
            <button class="delete-confirm-btn" @click="proceedToPassword">{{ t('settings.yesDelete') }}</button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Delete Confirm Dialog 2 - Password -->
    <Transition name="modal">
      <div v-if="showDeletePassword" class="modal-overlay delete-overlay" @click.self="showDeletePassword = false">
        <div class="delete-dialog glass-card">
          <h3 class="delete-dialog-title">{{ t('settings.confirmDelete') }}</h3>
          <p class="delete-dialog-text">{{ t('settings.enterPasswordToDelete') }}</p>
          <input
            v-model="deletePassword"
            type="password"
            class="input-field"
            :placeholder="t('settings.password')"
            @keyup.enter="confirmDelete"
          />
          <div v-if="deleteError" class="error-toast">
            <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
            <span>{{ deleteError }}</span>
          </div>
          <div class="delete-dialog-actions">
            <button class="btn-ghost" @click="showDeletePassword = false" :disabled="deleting">{{ t('common.cancel') }}</button>
            <button class="delete-confirm-btn" @click="confirmDelete" :disabled="deleting">
              {{ deleting ? t('settings.deleting') : t('settings.deletePermanently') }}
            </button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Birth Date Edit Modal -->
    <Transition name="modal">
      <div v-if="showBirthDateModal" class="modal-overlay" @click.self="showBirthDateModal = false">
        <div class="picker-sheet glass-card">
          <div class="sheet-handle"></div>
          <div class="picker-hdr">
            <span class="picker-title">{{ t('settings.editBirthDate') }}</span>
            <button class="close-x" @click="showBirthDateModal = false"><X :size="18" /></button>
          </div>
          <div class="date-boxes-wrap">
            <div class="date-boxes">
              <select v-model="birthDay" class="date-box" :aria-label="t('register.day')">
                <option value="" disabled>{{ t('register.day') }}</option>
                <option v-for="d in validDays" :key="d" :value="d">{{ d }}</option>
              </select>
              <select v-model="birthMonth" class="date-box" :aria-label="t('register.month')">
                <option value="" disabled>{{ t('register.month') }}</option>
                <option v-for="m in months" :key="m" :value="m">{{ m }}</option>
              </select>
              <select v-model="birthYear" class="date-box" :aria-label="t('register.year')">
                <option value="" disabled>{{ t('register.year') }}</option>
                <option v-for="y in years" :key="y" :value="y">{{ y }}</option>
              </select>
            </div>
            <span class="field-hint">{{ t('register.birthDateHint') }}</span>
            <div v-if="birthDateError" class="error-toast">
              <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
              <span>{{ birthDateError }}</span>
            </div>
            <button
              class="upload-btn"
              :disabled="birthDateSaving || !birthDateStr"
              @click="saveBirthDate"
            >
              {{ birthDateSaving ? t('common.loading') : t('settings.saveBirthDate') }}
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
            <span class="picker-title">{{ t('settings.chooseAvatar') }}</span>
            <button class="close-x" @click="showAvatarPicker = false"><X :size="18" /></button>
          </div>

          <div class="picker-tabs">
            <button class="ptab" :class="{ active: avatarTab === 'preset' }" @click="avatarTab = 'preset'"><Image :size="16" /> {{ t('settings.preset') }}</button>
            <button class="ptab" :class="{ active: avatarTab === 'upload' }" @click="avatarTab = 'upload'"><Upload :size="16" /> {{ t('settings.uploadImage') }}</button>
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
              <img v-if="isImageUrl(auth.avatar)" :src="ensureAbsoluteUrl(auth.avatar)" class="prev-img" referrerpolicy="no-referrer" />
              <div v-else class="prev-empty">
                <Image :size="44" style="color: var(--text-muted)" />
                <span class="text-muted text-sm">{{ t('settings.noImage') }}</span>
              </div>
            </div>
            <input ref="avatarFileInput" type="file" accept="image/*" style="display:none" @change="handleAvatarUpload" />
            <button class="upload-btn" :disabled="uploadingAvatar" @click="avatarFileInput.click()">
              {{ uploadingAvatar ? t('settings.uploading') : t('settings.chooseImage') }}
            </button>
            <div class="text-muted text-sm" style="text-align:center">{{ t('settings.maxSize') }}</div>
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
  flex-shrink: 0;
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
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  gap: var(--spacing-sm);
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  padding: 0 var(--spacing) calc(40px + var(--safe-bottom));
}
.scroll-area > * {
  flex-shrink: 0;
}

/* Section label */
.section-label {
  color: var(--text-muted);
  font-size: 12px;
  font-weight: 500;
  padding: 4px 0 0;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

/* Profile card */
.profile-card {
  overflow: hidden;
  padding: 0;
}

.profile-card-inner {
  align-items: center;
  display: flex;
  gap: 16px;
  padding: var(--spacing);
}

.avatar-wrap {
  cursor: pointer;
  flex-shrink: 0;
  height: 64px;
  position: relative;
  width: 64px;
}
.avatar-wrap.avatar-wrap-featured::after {
  content: '';
  position: absolute;
  inset: -2px;
  border-radius: 50%;
  pointer-events: none;
  border: 2px solid rgba(255, 215, 0, 0.6);
  opacity: 1;
  box-shadow: 0 0 12px rgba(255, 215, 0, 0.3);
}
.avatar-crown-settings {
  position: absolute;
  top: -4px;
  right: -4px;
  color: #FFD700;
  filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3));
  z-index: 1;
}
[data-theme="light"] .avatar-wrap.avatar-wrap-featured::after,
html.light .avatar-wrap.avatar-wrap-featured::after {
  border-color: rgba(255, 115, 0, 0.6);
  box-shadow: 0 0 12px rgba(255, 115, 0, 0.3);
}
[data-theme="light"] .avatar-crown-settings,
html.light .avatar-crown-settings {
  color: #FF7300;
  filter: drop-shadow(0 1px 2px rgba(255, 115, 0, 0.2));
}
.avatar-img,
.avatar-circle {
  border: 2px solid var(--border);
  border-radius: 50%;
  height: 64px;
  width: 64px;
}
.avatar-img { object-fit: cover; display: block; }
.avatar-circle {
  align-items: center;
  display: flex;
  justify-content: center;
}
.av-letter { color: white; font-size: 24px; font-weight: 700; }
.av-emoji { font-size: 32px; line-height: 1; }

.edit-badge {
  align-items: center;
  background: var(--primary);
  border-radius: 50%;
  bottom: 0;
  color: white;
  display: flex;
  height: 22px;
  justify-content: center;
  position: absolute;
  inset-inline-end: 0;
  width: 22px;
  z-index: 2;
}

.profile-details {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.profile-name {
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
}

.profile-gender-badge {
  display: inline-block;
  font-size: 12px;
  font-weight: 600;
  color: var(--primary);
  background: rgba(108, 99, 255, 0.15);
  padding: 4px 10px;
  border-radius: var(--radius-full);
  width: fit-content;
}

/* كود الاتصال - بطاقة منفصلة مثل دردشة الدعم */
.profile-code-card {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: var(--spacing);
  overflow: hidden;
  border: 1px solid rgba(108, 99, 255, 0.25);
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.08) 0%, rgba(108, 99, 255, 0.02) 100%);
  cursor: pointer;
  transition: background 0.2s;
}
.profile-code-card:active { background: rgba(108, 99, 255, 0.12); }

.profile-code-icon-wrap {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  border-radius: var(--radius-sm);
  background: rgba(108, 99, 255, 0.2);
  color: var(--primary);
  flex-shrink: 0;
}

.profile-code-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  flex: 1;
  min-width: 0;
}

.profile-code-title {
  font-size: 16px;
  font-weight: 700;
  color: var(--text-primary);
}

.profile-code-value {
  font-size: 14px;
  font-weight: 600;
  letter-spacing: 1.5px;
  color: var(--primary);
}

.profile-code-copy-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  min-width: 40px;
  padding: 0;
  background: rgba(108, 99, 255, 0.15);
  border: 1px solid rgba(108, 99, 255, 0.3);
  border-radius: var(--radius-sm);
  color: var(--primary);
  cursor: pointer;
  transition: background 0.2s, color 0.2s;
}
.profile-code-copy-btn:active { background: rgba(108, 99, 255, 0.25); }
.copied-text { color: var(--success); font-size: 12px; font-weight: 600; }

.privacy-badge-wrap {
  width: 100%;
}

/* Support card - بارز ومرتب */
.support-card {
  overflow: hidden;
  padding: 0;
  border: 1px solid rgba(108,99,255,0.25);
  background: linear-gradient(135deg, rgba(108,99,255,0.08) 0%, rgba(108,99,255,0.02) 100%);
}
.support-row {
  align-items: center;
  background: none;
  border: none;
  color: inherit;
  cursor: pointer;
  display: flex;
  font: inherit;
  gap: 14px;
  padding: var(--spacing);
  text-align: start;
  width: 100%;
  transition: background 0.2s;
}
.support-row:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.support-row:active { background: rgba(108,99,255,0.08); }
.support-icon-wrap {
  align-items: center;
  background: rgba(108,99,255,0.2);
  border-radius: var(--radius-sm);
  color: var(--primary);
  display: flex;
  flex-shrink: 0;
  height: 44px;
  justify-content: center;
  width: 44px;
}
.support-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  flex: 1;
  min-width: 0;
}
.support-title {
  font-size: 16px;
  font-weight: 700;
  color: var(--text-primary);
}
.support-desc {
  font-size: 13px;
  color: var(--text-muted);
}
.support-row .link-arrow { margin-inline-start: auto; }

.update-available-card {
  border-color: rgba(0, 212, 255, 0.35);
  background: linear-gradient(135deg, rgba(0, 212, 255, 0.1) 0%, rgba(0, 212, 255, 0.03) 100%);
}
.update-available-card .support-row:active { background: rgba(0, 212, 255, 0.12); }
.update-icon-wrap {
  background: rgba(0, 212, 255, 0.25) !important;
  color: #00D4FF !important;
}
@keyframes spin { to { transform: rotate(360deg); } }
.link-icon.spin { animation: spin 0.8s linear infinite; }

/* Links group */
.links-group {
  overflow: hidden;
  padding: 0;
}
.link-row {
  align-items: center;
  background: none;
  border: none;
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  font: inherit;
  gap: 12px;
  padding: var(--spacing);
  text-align: start;
  text-decoration: none;
  transition: background 0.2s;
  width: 100%;
}
.link-row:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.link-row:active { background: var(--bg-card-hover); }
.link-icon { color: var(--text-muted); flex-shrink: 0; }
.link-arrow { color: var(--text-muted); margin-inline-start: auto; }
.theme-toggle-row { justify-content: flex-start; }
.theme-badge {
  margin-inline-start: auto;
  background: rgba(108,99,255,0.15);
  color: var(--primary);
  font-size: 12px;
  font-weight: 600;
  padding: 4px 10px;
  border-radius: var(--radius-full);
}
.theme-badge.muted {
  background: rgba(255,255,255,0.08);
  color: var(--text-muted);
}
.link-icon-wrap {
  align-items: center;
  display: flex;
  flex-shrink: 0;
  justify-content: center;
}
.perm-icon {
  background: rgba(108,99,255,0.15);
  border-radius: var(--radius-sm);
  color: var(--primary);
  height: 40px;
  position: relative;
  width: 40px;
}
.perm-icon .mic-overlay {
  bottom: 4px;
  position: absolute;
  right: 4px;
}
.link-text-col {
  display: flex;
  flex-direction: column;
  gap: 2px;
  flex: 1;
  min-width: 0;
}
.link-desc {
  font-size: 12px;
  color: var(--text-muted);
}
.perm-feedback {
  font-size: 12px;
  max-width: 160px;
  text-align: left;
}
.perm-feedback.success { color: var(--success); }
.perm-feedback.error { color: var(--danger); }
.toggle-row { justify-content: flex-start; }

/* Notification enable/disable buttons */
.notif-buttons-row {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: var(--spacing);
  border-bottom: 1px solid var(--border);
}
.notif-label {
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 15px;
  color: var(--text-secondary);
}
.notif-btns {
  display: flex;
  gap: 10px;
}
.notif-btn {
  flex: 1;
  min-height: 40px;
  border-radius: var(--radius-sm);
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: 0.2s;
  border: 1px solid var(--border);
}
.notif-btn.enable {
  background: rgba(108, 99, 255, 0.15);
  color: var(--primary);
  border-color: rgba(108, 99, 255, 0.3);
}
.notif-btn.enable:not(:disabled):active { background: rgba(108, 99, 255, 0.25); }
.notif-btn.enable.active,
.notif-btn.enable:disabled {
  background: var(--primary);
  color: white;
  border-color: var(--primary);
  cursor: default;
}
.notif-btn.disable {
  background: rgba(255, 255, 255, 0.05);
  color: var(--text-muted);
}
.notif-btn.disable:not(:disabled):active { background: rgba(255, 255, 255, 0.1); }
.notif-btn.disable.active,
.notif-btn.disable:disabled {
  background: rgba(255, 255, 255, 0.08);
  color: var(--text-muted);
  cursor: default;
}
.notif-web-msg {
  font-size: 13px;
  color: var(--text-muted);
}

/* About */
.about-card { overflow: hidden; padding: var(--spacing); }
.about-inner {
  align-items: center;
  display: flex;
  gap: var(--spacing);
}
.about-logo-img {
  height: 48px;
  width: auto;
  object-fit: contain;
  flex-shrink: 0;
}
.about-text { flex: 1; min-width: 0; }
.about-name { font-size: 16px; font-weight: 700; margin-bottom: 2px; }
.about-tagline { margin-bottom: 8px; }
.ver-badge {
  background: rgba(108,99,255,0.15);
  border: 1px solid rgba(108,99,255,0.2);
  border-radius: var(--radius-full);
  color: var(--primary);
  font-size: 11px;
  font-weight: 600;
  padding: 2px 10px;
}

/* Actions group */
.actions-group {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-sm);
}
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
  min-height: var(--touch-min);
  padding: 0 var(--spacing);
  transition: background 0.2s;
}
.logout-btn:active { background: rgba(255,101,132,0.18); }

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
  min-height: var(--touch-min);
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
.delete-dialog-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 48px;
  color: var(--primary);
  margin-bottom: 8px;
}
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
.logout-confirm-btn {
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
.logout-confirm-btn:active { opacity: 0.9; }

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
  font-family: 'Cairo', sans-serif;
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
  font-family: 'Cairo', sans-serif;
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

/* Birth date card & modal */
.birth-date-card .link-arrow { margin-inline-start: auto; }
.date-boxes-wrap {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 0 var(--spacing) calc(32px + var(--safe-bottom));
}
.date-boxes {
  display: grid;
  grid-template-columns: 1fr 1.5fr 1fr;
  gap: 10px;
}
.date-box {
  appearance: none;
  -webkit-appearance: none;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  color: var(--text-primary);
  cursor: pointer;
  font-family: 'Cairo', sans-serif;
  font-size: 15px;
  font-weight: 500;
  min-height: 48px;
  padding: 0 12px;
  text-align: center;
  transition: border-color 0.2s, background 0.2s;
}
.date-box:focus {
  outline: none;
  border-color: var(--primary);
}
.date-box option {
  background: var(--bg-card);
  color: var(--text-primary);
}
.field-hint { font-size: 12px; color: var(--text-muted); }
.error-toast {
  align-items: center;
  background: rgba(255, 101, 132, 0.15);
  border: 1px solid rgba(255, 101, 132, 0.3);
  border-radius: var(--radius-sm);
  color: var(--danger);
  display: flex;
  font-size: 13px;
  gap: 8px;
  padding: 10px 12px;
}
.error-toast-icon { flex-shrink: 0; }
</style>
