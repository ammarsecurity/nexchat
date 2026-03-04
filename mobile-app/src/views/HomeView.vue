<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { Settings, LogOut, Zap, Globe, Users, UserCircle, UsersRound, Phone, PhoneOff, PhoneCall, Check, X, AlertCircle, Bell, BookmarkPlus, Trash2, Crown } from 'lucide-vue-next'
import BannerStrip from '../components/BannerStrip.vue'
import AppFooter from '../components/AppFooter.vue'
import HomeNavBar from '../components/HomeNavBar.vue'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { useAuthStore } from '../stores/auth'
import { useI18n } from 'vue-i18n'
import { useMatchingStore } from '../stores/matching'
import { useChatStore } from '../stores/chat'
import { matchingHub, startHub, ensureConnected } from '../services/signalr'
import { requestMediaPermissions } from '../utils/mediaPermissions'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { requestPermissionAndRegister } from '../services/notifications'
import api from '../services/api'

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

const router = useRouter()
const auth = useAuthStore()
const matching = useMatchingStore()
const chat = useChatStore()
const { t } = useI18n()

const codeInput = ref('')
const codeError = ref('')
const copied = ref(false)
const loading = ref(false)
const savedCodes = ref([])
const savedCodesLoading = ref(false)
const showAddCodeModal = ref(false)
const newCodeInput = ref('')
const newCodeLabel = ref('')
const addCodeError = ref('')
const waitingForAccept = ref(false)
const showLogoutConfirm = ref(false)
const notifPromptLoading = ref(false)
const onlineCount = ref(Math.floor(Math.random() * 200) + 50)
let connectionTimeoutId = null

const user = computed(() => auth.user)
const avatarLetter = computed(() => user.value?.name?.[0]?.toUpperCase() || '?')
const isFeatured = computed(() => user.value?.isFeatured ?? false)

function matchFoundHandler() {
  clearConnectionTimeout()
  waitingForAccept.value = false
  loading.value = false
}

onMounted(async () => {
  requestMediaPermissions()

  await startHub(matchingHub)

  matchingHub.off('SearchCancelled')
  matchingHub.off('CodeError')
  matchingHub.off('ConnectionRequestSent')
  matchingHub.off('ConnectionDeclined')
  matchingHub.off('ConnectionCancelled')

  matchingHub.on('MatchFound', matchFoundHandler)

  matchingHub.on('SearchCancelled', () => {
    matching.setIdle()
  })

  matchingHub.on('CodeError', (msg) => {
    codeError.value = msg
    loading.value = false
    waitingForAccept.value = false
    clearConnectionTimeout()
  })

  matchingHub.on('ConnectionRequestSent', () => {
    waitingForAccept.value = true
    startConnectionTimeout()
  })

  matchingHub.on('ConnectionDeclined', () => {
    clearConnectionTimeout()
    waitingForAccept.value = false
    loading.value = false
    codeError.value = t('home.requestDeclined')
  })

  matchingHub.on('ConnectionCancelled', () => {
    clearConnectionTimeout()
    waitingForAccept.value = false
    loading.value = false
  })

  setInterval(() => {
    onlineCount.value = Math.max(20, onlineCount.value + Math.floor(Math.random() * 6) - 3)
  }, 5000)

  if (auth.user?.isFeatured) fetchSavedCodes()
})

async function fetchSavedCodes() {
  if (!auth.user?.isFeatured) return
  savedCodesLoading.value = true
  try {
    const { data } = await api.get('/user/saved-codes')
    savedCodes.value = data ?? []
  } catch {
    savedCodes.value = []
  } finally {
    savedCodesLoading.value = false
  }
}

function openAddCodeModal() {
  showAddCodeModal.value = true
  newCodeInput.value = ''
  newCodeLabel.value = ''
  addCodeError.value = ''
}

function closeAddCodeModal() {
  showAddCodeModal.value = false
}

async function addSavedCode() {
  const code = newCodeInput.value.trim().toUpperCase()
  if (!code || !code.startsWith('NX-') || code.length !== 7) {
    addCodeError.value = t('home.codeFormatError')
    return
  }
  addCodeError.value = ''
  try {
    await api.post('/user/saved-codes', { code, label: newCodeLabel.value.trim() || null })
    closeAddCodeModal()
    await fetchSavedCodes()
  } catch (e) {
    addCodeError.value = e.userMessage ?? t('common.error')
  }
}

async function removeSavedCode(code) {
  try {
    await api.delete(`/user/saved-codes/${encodeURIComponent(code)}`)
    await fetchSavedCodes()
  } catch {}
}

async function connectBySavedCode(code) {
  codeInput.value = code
  codeError.value = ''
  loading.value = true
  waitingForAccept.value = false
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('ConnectByCode', code)
  } catch {
    loading.value = false
    codeError.value = t('home.connectionError')
  }
}

function clearConnectionTimeout() {
  if (connectionTimeoutId) {
    clearTimeout(connectionTimeoutId)
    connectionTimeoutId = null
  }
}

function startConnectionTimeout() {
  clearConnectionTimeout()
  connectionTimeoutId = setTimeout(async () => {
    connectionTimeoutId = null
    waitingForAccept.value = false
    loading.value = false
    codeError.value = t('home.timeoutError')
    try {
      await ensureConnected(matchingHub)
      await matchingHub.invoke('CancelConnectionRequest')
    } catch {}
  }, 60000)
}

async function startRandom() {
  loading.value = true
  matching.setSearching()
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('StartSearching', matching.genderFilter)
    if (matching.status !== 'matched') {
      router.push('/matching')
    }
  } finally {
    loading.value = false
  }
}

async function connectByCode() {
  if (!codeInput.value.trim()) return
  codeError.value = ''
  const code = codeInput.value.trim().toUpperCase()
  if (!code.startsWith('NX-') || code.length !== 7) {
    codeError.value = t('home.codeFormatError')
    return
  }
  loading.value = true
  waitingForAccept.value = false
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('ConnectByCode', code)
  } catch {
    loading.value = false
    codeError.value = t('home.connectionError')
  }
}

async function cancelConnectionRequest() {
  clearConnectionTimeout()
  waitingForAccept.value = false
  loading.value = false
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('CancelConnectionRequest')
  } catch {}
}

function copyCode() {
  navigator.clipboard.writeText(user.value.uniqueCode)
  copied.value = true
  setTimeout(() => copied.value = false, 2000)
}

onUnmounted(() => {
  clearConnectionTimeout()
  matchingHub.off('MatchFound', matchFoundHandler)
  matchingHub.off('SearchCancelled')
  matchingHub.off('CodeError')
  matchingHub.off('ConnectionRequestSent')
  matchingHub.off('ConnectionDeclined')
  matchingHub.off('ConnectionCancelled')
})

function openLogoutConfirm() {
  showLogoutConfirm.value = true
}

function confirmLogout() {
  showLogoutConfirm.value = false
  matchingHub.stop()
  auth.logout()
  router.replace('/login')
}

async function enableNotifications() {
  notifPromptLoading.value = true
  try {
    await requestPermissionAndRegister()
    auth.dismissNotificationPrompt()
  } finally {
    notifPromptLoading.value = false
  }
}

function dismissNotificationPrompt() {
  auth.dismissNotificationPrompt()
}

const genderFilters = computed(() => [
  { value: 'all', label: t('home.filterAll'), Icon: Globe, color: '#7C75FF', bg: 'rgba(124, 117, 255, 0.15)' },
  { value: 'male', label: t('home.filterMale'), Icon: UserCircle, color: '#3B82F6', bg: 'rgba(59, 130, 246, 0.15)' },
  { value: 'female', label: t('home.filterFemale'), Icon: UsersRound, color: '#EC4899', bg: 'rgba(236, 72, 153, 0.15)' }
])
</script>

<template>
  <div class="home page auth-pattern">
    <LoaderOverlay
      :show="loading"
      :text="waitingForAccept ? t('home.waitingForAccept') : t('home.connecting')"
    />
    <!-- Header مميز -->
    <header class="header">
      <div class="header-inner">
        <div class="user-row">
          <div class="avatar-wrap" :class="{ 'avatar-wrap-featured': isFeatured }">
            <div class="avatar" :style="{ background: auth.avatarColor }">
              <img v-if="isImageAvatar(auth.avatar)" :src="ensureAbsoluteUrl(auth.avatar)" class="avatar-img" referrerpolicy="no-referrer" />
              <span v-else-if="auth.avatar">{{ auth.avatar }}</span>
              <span v-else>{{ avatarLetter }}</span>
            </div>
            <Crown v-if="isFeatured" class="avatar-crown-home" :size="20" stroke-width="2" />
          </div>
          <div class="user-meta">
            <span class="user-name">{{ user?.name }}</span>
          </div>
        </div>
        <div class="header-actions">
          <RouterLink to="/settings" class="nav-btn" :aria-label="t('home.settings')">
            <Settings :size="20" stroke-width="2" />
          </RouterLink>
          <button class="nav-btn" @click="openLogoutConfirm" :aria-label="t('home.logout')">
            <LogOut :size="20" stroke-width="2" />
          </button>
        </div>
      </div>
    </header>

    <!-- Cancel waiting (when user is requester) - shown above loader -->
    <Transition name="fade">
      <div v-if="waitingForAccept" class="cancel-wait-wrap">
        <button class="cancel-wait-btn" @click="cancelConnectionRequest">
          <PhoneOff :size="18" />
          <span>{{ t('home.cancelRequest') }}</span>
        </button>
      </div>
    </Transition>

    <!-- Logout Confirm Dialog -->
    <Transition name="modal">
      <div v-if="showLogoutConfirm" class="logout-overlay" @click.self="showLogoutConfirm = false">
        <div class="logout-dialog glass-card">
          <div class="logout-dialog-icon"><LogOut :size="48" stroke-width="2" /></div>
          <h3 class="logout-dialog-title">{{ t('home.logoutConfirm') }}</h3>
          <p class="logout-dialog-text">{{ t('home.logoutConfirmText') }}</p>
          <div class="logout-dialog-actions">
            <button class="btn-ghost" @click="showLogoutConfirm = false">{{ t('common.cancel') }}</button>
            <button class="logout-confirm-btn" @click="confirmLogout">{{ t('home.logout') }}</button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Notification Enable Prompt (after login) -->
    <Transition name="modal">
      <div v-if="auth.shouldPromptNotifications" class="logout-overlay" @click.self="dismissNotificationPrompt">
        <div class="logout-dialog glass-card notif-prompt-dialog">
          <div class="logout-dialog-icon"><Bell :size="48" stroke-width="2" /></div>
          <h3 class="logout-dialog-title">{{ t('home.enableNotifications') }}</h3>
          <p class="logout-dialog-text">
            {{ t('home.enableNotificationsText') }}
          </p>
          <div class="logout-dialog-actions">
            <button class="btn-ghost" :disabled="notifPromptLoading" @click="dismissNotificationPrompt">{{ t('home.later') }}</button>
            <button class="logout-confirm-btn notif-enable-btn" :disabled="notifPromptLoading" @click="enableNotifications">
              {{ notifPromptLoading ? t('home.enabling') : t('home.enableNow') }}
            </button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Online indicator -->
    <div class="list-section">
      <div class="list-row">
        <div class="list-row-icon">
          <Users :size="20" stroke-width="2" />
          <span class="status-dot"></span>
        </div>
        <div class="list-row-content">
          <span class="list-count">{{ onlineCount }}</span>
          <span class="list-label">{{ t('home.onlineNow') }}</span>
        </div>
      </div>
    </div>

    <!-- CTA + Filter - unified section -->
    <div class="cta-filter-card">
      <div class="main-cta-wrap">
        <button class="main-cta-circle" :disabled="loading" @click="startRandom">
          <Zap :size="32" class="cta-icon" />
          <span class="cta-text">{{ t('home.startRandom') }}</span>
        </button>
      </div>
      <div class="segment-wrap">
        <span class="segment-label">{{ t('home.filterLabel') }}</span>
        <div class="segment-control">
        <button
          v-for="f in genderFilters"
          :key="f.value"
          class="segment-btn"
          :class="{ active: matching.genderFilter === f.value }"
          :style="matching.genderFilter === f.value ? { '--seg-color': f.color, '--seg-bg': f.bg } : {}"
          @click="matching.genderFilter = f.value"
        >
          <span class="segment-icon" :class="{ active: matching.genderFilter === f.value }">
            <component :is="f.Icon" :size="20" stroke-width="2" />
          </span>
          <span class="segment-text">{{ f.label }}</span>
        </button>
      </div>
    </div>
    </div>

    <!-- Saved Codes (featured users only) -->
    <Transition name="fade">
      <div v-if="isFeatured" class="saved-codes-section">
        <div class="saved-codes-header">
          <span class="saved-codes-title">{{ t('home.savedCodes') }}</span>
          <button class="add-code-btn" @click="openAddCodeModal" :aria-label="t('home.addCode')">
            <BookmarkPlus :size="20" stroke-width="2" />
            <span>{{ t('home.addCode') }}</span>
          </button>
        </div>
        <div v-if="savedCodesLoading" class="saved-codes-loading">{{ t('common.loading') }}</div>
        <div v-else-if="savedCodes.length" class="saved-codes-list">
          <button
            v-for="item in savedCodes"
            :key="item.code"
            class="saved-code-item"
            @click="connectBySavedCode(item.code)"
          >
            <span class="saved-code-value">{{ item.code }}</span>
            <span v-if="item.label" class="saved-code-label">{{ item.label }}</span>
            <button class="saved-code-delete" @click.stop="removeSavedCode(item.code)" :aria-label="t('common.delete')">
              <Trash2 :size="16" stroke-width="2" />
            </button>
          </button>
        </div>
        <div v-else class="saved-codes-empty">{{ t('home.noSavedCodes') }}</div>
      </div>
    </Transition>

    <!-- Add Code Modal -->
    <Transition name="modal">
      <div v-if="showAddCodeModal" class="logout-overlay" @click.self="closeAddCodeModal">
        <div class="add-code-modal glass-card">
          <h3 class="add-code-title">{{ t('home.addCode') }}</h3>
          <input
            v-model="newCodeInput"
            class="code-input add-code-input"
            :placeholder="t('home.enterUserCode')"
            maxlength="7"
            @input="newCodeInput = newCodeInput.toUpperCase()"
          />
          <input
            v-model="newCodeLabel"
            class="code-input add-code-label-input"
            :placeholder="t('home.codeLabelPlaceholder')"
            maxlength="50"
          />
          <div v-if="addCodeError" class="error-toast">{{ addCodeError }}</div>
          <div class="add-code-actions">
            <button class="btn-ghost" @click="closeAddCodeModal">{{ t('common.cancel') }}</button>
            <button class="logout-confirm-btn add-code-submit" @click="addSavedCode">{{ t('home.addCode') }}</button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Divider -->
    <div class="divider">
      <span class="divider-txt">{{ t('home.orConnectByCode') }}</span>
    </div>

    <!-- Code input - زر الاتصال داخل الـ input -->
    <div class="code-section">
      <div class="code-input-wrap">
        <input
          v-model="codeInput"
          class="code-input"
          :placeholder="t('home.enterUserCode')"
          maxlength="7"
          @input="codeInput = codeInput.toUpperCase()"
          @keyup.enter="connectByCode"
        />
        <button
          class="code-submit"
          :class="{ disabled: !codeInput.trim() || loading }"
          :disabled="!codeInput.trim() || loading"
          :aria-label="t('home.connect')"
          @click="connectByCode"
        >
          <PhoneCall :size="22" stroke-width="2" />
        </button>
      </div>
      <div v-if="codeError" class="error-toast">
        <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
        <span>{{ codeError }}</span>
      </div>
    </div>

    <div class="home-bottom">
      <BannerStrip placement="home" />
      <AppFooter />
    </div>

    <HomeNavBar :loading="loading" @launch="startRandom" />
  </div>
</template>

<style scoped>
.home {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  min-height: 100%;
  padding-bottom: calc(90px + var(--safe-bottom));
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
}

.home-bottom {
  display: flex;
  flex-direction: column;
  padding-top: 8px;
}

/* Header مميز - تصميم بارز */
.header {
  flex-shrink: 0;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 16px;
  background: linear-gradient(180deg, rgba(108, 99, 255, 0.12) 0%, rgba(108, 99, 255, 0.04) 50%, transparent 100%);
  border-bottom: 1px solid rgba(108, 99, 255, 0.15);
}

.header-inner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 16px;
  background: var(--bg-card);
  border: 1px solid rgba(108, 99, 255, 0.2);
  border-radius: 16px;
  box-shadow: 0 4px 20px rgba(108, 99, 255, 0.08), 0 0 0 1px rgba(255, 255, 255, 0.03) inset;
}

.user-row {
  display: flex;
  align-items: center;
  gap: 14px;
  flex: 1;
  min-width: 0;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.user-row:active { opacity: 0.9; }

.avatar-wrap {
  position: relative;
  flex-shrink: 0;
}
.avatar-wrap::after {
  content: '';
  position: absolute;
  inset: -2px;
  border-radius: 50%;
  border: 2px solid rgba(108, 99, 255, 0.35);
  opacity: 0.5;
  pointer-events: none;
}
.avatar-wrap.avatar-wrap-featured::after {
  border: 2px solid rgba(255, 215, 0, 0.6);
  opacity: 1;
  box-shadow: 0 0 12px rgba(255, 215, 0, 0.3);
}
.avatar-crown-home {
  position: absolute;
  top: -4px;
  right: -4px;
  color: #FFD700;
  filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3));
  z-index: 1;
}

.avatar {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  font-weight: 700;
  overflow: hidden;
  border: 2px solid rgba(108, 99, 255, 0.3);
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.2);
}
.avatar-img { width: 100%; height: 100%; object-fit: cover; }

.user-meta {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
  flex: 1;
  overflow: hidden;
}
.user-name {
  font-size: 18px;
  font-weight: 700;
  color: var(--text-primary);
  letter-spacing: -0.3px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.header-actions {
  display: flex;
  gap: 6px;
  flex-shrink: 0;
}

.nav-btn {
  width: 42px;
  height: 42px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(108, 99, 255, 0.08);
  border: 1px solid rgba(108, 99, 255, 0.2);
  color: var(--text-secondary);
  cursor: pointer;
  border-radius: 12px;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.2s, color 0.2s, border-color 0.2s;
}
.nav-btn:active { background: rgba(108, 99, 255, 0.2); color: var(--primary); border-color: rgba(108, 99, 255, 0.4); }
.nav-btn:hover { color: var(--primary); }

/* List section - online indicator */
.list-section {
  padding: 0 var(--spacing);
  margin-bottom: 20px;
}

.list-row {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 14px 18px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
  transition: border-color 0.2s, box-shadow 0.2s;
}

.list-row-icon {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  border-radius: 12px;
  background: rgba(108, 99, 255, 0.1);
  color: var(--primary);
  flex-shrink: 0;
}

.status-dot {
  position: absolute;
  bottom: 4px;
  right: 4px;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--success);
  border: 2px solid var(--bg-card);
  animation: status-pulse 2s ease-in-out infinite;
}

@keyframes status-pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.7; transform: scale(1.1); }
}

.list-row-content {
  display: flex;
  align-items: baseline;
  gap: 6px;
  min-width: 0;
}

.list-count {
  font-size: 18px;
  font-weight: 700;
  color: var(--primary);
  font-family: 'Cairo', sans-serif;
  letter-spacing: -0.5px;
}

.list-label {
  font-size: 14px;
  color: var(--text-secondary);
  font-weight: 500;
}

/* CTA + Filter - unified card */
.cta-filter-card {
  margin: 0 var(--spacing) 24px;
  padding: 24px var(--spacing);
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 16px;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.06);
  position: relative;
  overflow: hidden;
  flex-shrink: 0;
  min-height: 280px;
}
.cta-filter-card::before {
  content: '';
  position: absolute;
  inset: 0;
  opacity: 0.4;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='40' height='40' viewBox='0 0 40 40'%3E%3Ccircle cx='8' cy='8' r='1' fill='%236C63FF'/%3E%3Ccircle cx='24' cy='8' r='1' fill='%23FF6584'/%3E%3Ccircle cx='8' cy='24' r='1' fill='%23FF6584'/%3E%3Ccircle cx='24' cy='24' r='1' fill='%236C63FF'/%3E%3Ccircle cx='16' cy='16' r='0.5' fill='%236C63FF' opacity='0.6'/%3E%3C/svg%3E");
  background-size: 40px 40px;
  background-repeat: repeat;
  pointer-events: none;
}
.cta-filter-card::after {
  content: '';
  position: absolute;
  inset: 0;
  background: radial-gradient(ellipse 80% 50% at 50% 0%, rgba(108, 99, 255, 0.08) 0%, transparent 60%);
  pointer-events: none;
}
.cta-filter-card > * {
  position: relative;
  z-index: 1;
}

/* Main CTA - circular button with animation */
.main-cta-wrap {
  padding: 0 0 20px;
  display: flex;
  justify-content: center;
}

.main-cta-circle {
  width: 160px;
  height: 160px;
  border-radius: 50%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  background: linear-gradient(145deg, #7C75FF 0%, var(--primary) 50%, #FF6584 100%);
  border: none;
  color: white;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  box-shadow:
    0 0 0 3px rgba(108, 99, 255, 0.2),
    0 6px 24px rgba(108, 99, 255, 0.4),
    inset 0 1px 0 rgba(255, 255, 255, 0.25);
  animation: cta-pulse 2.5s ease-in-out infinite;
  transition: transform 0.2s, box-shadow 0.2s;
}
.main-cta-circle:active:not(:disabled) {
  transform: scale(0.95);
  animation: none;
}
.main-cta-circle:disabled {
  opacity: 0.6;
  cursor: not-allowed;
  animation: none;
}

@keyframes cta-pulse {
  0%, 100% {
    box-shadow:
      0 0 0 3px rgba(108, 99, 255, 0.2),
      0 6px 24px rgba(108, 99, 255, 0.4),
      inset 0 1px 0 rgba(255, 255, 255, 0.25);
    transform: scale(1);
  }
  50% {
    box-shadow:
      0 0 0 6px rgba(108, 99, 255, 0.15),
      0 8px 32px rgba(108, 99, 255, 0.5),
      inset 0 1px 0 rgba(255, 255, 255, 0.3);
    transform: scale(1.03);
  }
}

.cta-icon { flex-shrink: 0; }
.cta-text { line-height: 1.2; text-align: center; max-width: 120px; font-size: 12px; }

/* Segmented control */
.segment-wrap {
  padding: 0;
}

.segment-label {
  display: block;
  font-size: 13px;
  color: var(--text-muted);
  margin-bottom: 10px;
  padding: 0 4px;
  font-weight: 500;
}

.segment-control {
  display: flex;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 6px;
  gap: 6px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
}

.segment-btn {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 44px;
  padding: 0 4px;
  background: transparent;
  border: none;
  border-radius: 10px;
  color: var(--text-secondary);
  font-size: 14px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: all 0.25s ease;
}

.segment-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 10px;
  color: var(--text-muted);
  transition: all 0.25s ease;
}

.segment-btn.active .segment-icon {
  background: var(--seg-bg, rgba(124, 117, 255, 0.15));
  color: var(--seg-color);
}

.segment-text {
  font-weight: 500;
}

.segment-btn.active {
  background: var(--seg-bg, rgba(124, 117, 255, 0.12));
  color: var(--seg-color);
  font-weight: 600;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
}

.segment-btn.active .segment-text {
  color: var(--seg-color);
}

.segment-btn:active:not(.active) { opacity: 0.75; }

/* Saved codes (featured users) */
.saved-codes-section {
  padding: 0 var(--spacing) 20px;
}
.saved-codes-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
}
.saved-codes-title {
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
}
.add-code-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  background: linear-gradient(135deg, rgba(255, 215, 0, 0.2), rgba(255, 165, 0, 0.15));
  border: 1px solid rgba(255, 215, 0, 0.4);
  border-radius: 12px;
  color: #E6B800;
  font-size: 13px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.add-code-btn:active { opacity: 0.9; }
.saved-codes-loading {
  font-size: 14px;
  color: var(--text-muted);
  padding: 16px;
  text-align: center;
}
.saved-codes-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.saved-code-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 12px;
  text-align: start;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: border-color 0.2s, background 0.2s;
}
.saved-code-item:active { background: var(--bg-card-hover); }
.saved-code-value {
  font-size: 15px;
  font-weight: 700;
  letter-spacing: 1px;
  color: var(--primary);
  flex: 1;
  min-width: 0;
}
.saved-code-label {
  font-size: 13px;
  color: var(--text-secondary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100px;
}
.saved-code-delete {
  padding: 6px;
  background: rgba(255, 101, 132, 0.15);
  border: none;
  border-radius: 8px;
  color: var(--danger);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.saved-code-delete:active { opacity: 0.8; }
.saved-codes-empty {
  font-size: 14px;
  color: var(--text-muted);
  padding: 20px;
  text-align: center;
  background: var(--bg-card);
  border: 1px dashed var(--border);
  border-radius: 12px;
}

/* Add code modal */
.add-code-modal {
  margin: var(--spacing);
  max-width: 340px;
  padding: 24px;
  width: 100%;
}
.add-code-title {
  font-size: 18px;
  font-weight: 700;
  margin: 0 0 16px;
  text-align: center;
}
.add-code-input, .add-code-label-input {
  width: 100%;
  margin-bottom: 12px;
  padding: 14px 16px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: 12px;
  color: var(--text-primary);
  font-size: 16px;
  font-family: 'Cairo', sans-serif;
  outline: none;
}
.add-code-input { letter-spacing: 2px; text-align: center; }
.add-code-label-input { letter-spacing: 0; }
.add-code-modal .error-toast { margin-bottom: 12px; }
.add-code-actions {
  display: flex;
  gap: 12px;
  margin-top: 8px;
}
.add-code-submit { background: var(--primary) !important; }

/* Divider */
.divider {
  padding: 0 var(--spacing) 16px;
}
.divider-txt {
  font-size: 13px;
  color: var(--text-muted);
  display: block;
  text-align: center;
}

/* Code section - زر الاتصال داخل الـ input */
.code-section {
  padding: 0 var(--spacing) 24px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.code-input-wrap {
  position: relative;
  display: flex;
  align-items: center;
  min-height: 52px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  overflow: hidden;
  transition: border-color 0.2s, box-shadow 0.2s;
}
.code-input-wrap:focus-within {
  border-color: var(--primary);
  box-shadow: 0 0 0 2px rgba(108, 99, 255, 0.2);
}

.code-input {
  flex: 1;
  min-height: 50px;
  padding-inline-start: 20px;
  padding-inline-end: 60px;
  background: transparent;
  border: none;
  color: var(--text-primary);
  font-size: 16px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  letter-spacing: 2px;
  text-align: center;
  outline: none;
  -webkit-appearance: none;
  appearance: none;
}
.code-input::placeholder { color: var(--text-muted); }

.code-submit {
  position: absolute;
  top: 4px;
  inset-inline-end: 4px;
  width: 44px;
  height: 44px;
  min-width: 44px;
  min-height: 44px;
  padding: 0;
  border-radius: 50%;
  background: linear-gradient(145deg, #7C75FF 0%, var(--primary) 50%, #5B54E8 100%);
  border: none;
  color: white;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  box-shadow: 0 2px 10px rgba(108, 99, 255, 0.4);
  transition: transform 0.2s, opacity 0.2s, box-shadow 0.2s;
  display: flex;
  align-items: center;
  justify-content: center;
}
.code-submit.disabled {
  opacity: 0.5;
  background: var(--bg-card-hover);
  color: var(--text-muted);
  box-shadow: none;
  cursor: not-allowed;
}
.code-submit:not(.disabled) {
  animation: call-btn-pulse 2.5s ease-in-out infinite;
}
.code-submit:not(.disabled) svg {
  animation: call-icon-glow 2.5s ease-in-out infinite;
}
.code-submit:active:not(.disabled) {
  transform: scale(0.95);
  animation: none;
}
.code-submit:active:not(.disabled) svg {
  animation: none;
}

@keyframes call-btn-pulse {
  0%, 100% {
    box-shadow: 0 4px 12px rgba(108, 99, 255, 0.35);
    transform: scale(1);
  }
  50% {
    box-shadow: 0 6px 20px rgba(108, 99, 255, 0.5), 0 0 24px rgba(255, 101, 132, 0.25);
    transform: scale(1.03);
  }
}

@keyframes call-icon-glow {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.85; }
}

/* Logout confirm dialog */
.logout-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.5);
  z-index: 200;
}
.logout-dialog {
  margin: var(--spacing);
  max-width: 360px;
  padding: var(--spacing);
  width: 100%;
}
.logout-dialog-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary);
  margin-bottom: 8px;
}
.logout-dialog-title { font-size: 18px; font-weight: 700; margin-bottom: 12px; text-align: center; }
.logout-dialog-text { font-size: 14px; color: var(--text-secondary); margin-bottom: 16px; text-align: center; }
.logout-dialog-actions { display: flex; gap: 12px; }
.logout-confirm-btn {
  background: var(--danger);
  border: none;
  border-radius: var(--radius-sm);
  color: white;
  cursor: pointer;
  flex: 1;
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
  font-weight: 600;
  min-height: 44px;
  padding: 0;
}
.logout-confirm-btn:active { opacity: 0.9; }
.notif-enable-btn { background: var(--primary) !important; }
.notif-enable-btn:active { opacity: 0.9; }

.modal-enter-active, .modal-leave-active { transition: opacity 0.25s; }
.modal-enter-from, .modal-leave-to { opacity: 0; }

/* Incoming request dialog */
.request-dialog {
  margin: var(--spacing);
  max-width: 360px;
  padding: var(--spacing);
  width: 100%;
}
.request-dialog-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary);
  margin-bottom: 8px;
}
.request-dialog-title { font-size: 18px; font-weight: 700; margin-bottom: 12px; text-align: center; }
.request-dialog-text { font-size: 14px; color: var(--text-secondary); margin-bottom: 20px; text-align: center; }
.request-dialog-actions {
  display: flex;
  gap: 12px;
}
.btn-decline {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 48px;
  padding: 0 16px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}
.btn-decline:active { opacity: 0.9; }
.btn-accept {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 48px;
  padding: 0 16px;
  background: var(--primary);
  border: none;
  border-radius: var(--radius-sm);
  color: white;
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}
.btn-accept:active { opacity: 0.9; }

/* Cancel wait button - above loader overlay */
.cancel-wait-wrap {
  position: fixed;
  bottom: calc(48px + var(--safe-bottom));
  left: 50%;
  transform: translateX(-50%);
  z-index: 10001;
}
.cancel-wait-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 12px 24px;
  background: rgba(0, 0, 0, 0.7);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 24px;
  color: white;
  font-size: 14px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}
.cancel-wait-btn:active { opacity: 0.9; }
</style>
