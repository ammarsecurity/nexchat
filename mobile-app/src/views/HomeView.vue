<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { Settings, LogOut, Zap, Globe, User, Users, Phone, PhoneOff, Check, X } from 'lucide-vue-next'
import BannerStrip from '../components/BannerStrip.vue'
import AppFooter from '../components/AppFooter.vue'
import HomeNavBar from '../components/HomeNavBar.vue'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { useAuthStore } from '../stores/auth'
import { useMatchingStore } from '../stores/matching'
import { useChatStore } from '../stores/chat'
import { matchingHub, startHub, ensureConnected } from '../services/signalr'
import { requestMediaPermissions } from '../utils/mediaPermissions'
import { ensureAbsoluteUrl } from '../utils/imageUrl'

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

const router = useRouter()
const auth = useAuthStore()
const matching = useMatchingStore()
const chat = useChatStore()

const codeInput = ref('')
const codeError = ref('')
const copied = ref(false)
const loading = ref(false)
const waitingForAccept = ref(false)
const incomingRequest = ref(null)
const showLogoutConfirm = ref(false)
const onlineCount = ref(Math.floor(Math.random() * 200) + 50)
let connectionTimeoutId = null

const user = computed(() => auth.user)
const avatarLetter = computed(() => user.value?.name?.[0]?.toUpperCase() || '?')

onMounted(async () => {
  requestMediaPermissions()

  await startHub(matchingHub)

  matchingHub.off('MatchFound')
  matchingHub.off('SearchCancelled')
  matchingHub.off('CodeError')
  matchingHub.off('ConnectionRequestSent')
  matchingHub.off('IncomingConnectionRequest')
  matchingHub.off('ConnectionDeclined')
  matchingHub.off('ConnectionCancelled')

  matchingHub.on('MatchFound', (data) => {
    clearConnectionTimeout()
    waitingForAccept.value = false
    loading.value = false
    const sessionId = data.sessionId ?? data.SessionId
    const partner = data.partner ?? data.Partner
    chat.setSession(sessionId, partner)
    matching.setMatched()
    router.push(`/chat/${sessionId}`)
  })

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

  matchingHub.on('IncomingConnectionRequest', (data) => {
    incomingRequest.value = {
      requesterId: data.requesterId ?? data.RequesterId,
      requesterName: data.requesterName ?? data.RequesterName,
      requesterGender: data.requesterGender ?? data.RequesterGender,
      requesterAvatar: data.requesterAvatar ?? data.RequesterAvatar
    }
  })

  matchingHub.on('ConnectionDeclined', () => {
    clearConnectionTimeout()
    waitingForAccept.value = false
    loading.value = false
    codeError.value = 'تم رفض الطلب'
  })

  matchingHub.on('ConnectionCancelled', () => {
    clearConnectionTimeout()
    waitingForAccept.value = false
    loading.value = false
  })

  setInterval(() => {
    onlineCount.value = Math.max(20, onlineCount.value + Math.floor(Math.random() * 6) - 3)
  }, 5000)
})

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
    codeError.value = 'انتهت مهلة الانتظار'
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
    codeError.value = 'الكود يجب أن يكون بالشكل NX-XXXX'
    return
  }
  loading.value = true
  waitingForAccept.value = false
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('ConnectByCode', code)
  } catch {
    loading.value = false
    codeError.value = 'حدث خطأ في الاتصال'
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

async function acceptConnectionRequest() {
  if (!incomingRequest.value) return
  const requesterId = incomingRequest.value.requesterId
  incomingRequest.value = null
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('AcceptConnectionRequest', requesterId)
  } catch {
    codeError.value = 'حدث خطأ في قبول الطلب'
  }
}

function declineConnectionRequest() {
  if (!incomingRequest.value) return
  const requesterId = incomingRequest.value.requesterId
  incomingRequest.value = null
  ensureConnected(matchingHub).then(() => {
    matchingHub.invoke('DeclineConnectionRequest', requesterId).catch(() => {})
  })
}

function copyCode() {
  navigator.clipboard.writeText(user.value.uniqueCode)
  copied.value = true
  setTimeout(() => copied.value = false, 2000)
}

onUnmounted(() => {
  clearConnectionTimeout()
  matchingHub.off('MatchFound')
  matchingHub.off('SearchCancelled')
  matchingHub.off('CodeError')
  matchingHub.off('ConnectionRequestSent')
  matchingHub.off('IncomingConnectionRequest')
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

const genderFilters = [
  { value: 'all', label: 'الكل', Icon: Globe },
  { value: 'male', label: 'ذكور', Icon: User },
  { value: 'female', label: 'إناث', Icon: Users }
]
</script>

<template>
  <div class="home page auth-pattern">
    <LoaderOverlay
      :show="loading"
      :text="waitingForAccept ? 'بانتظار موافقة الطرف الآخر...' : 'جاري الاتصال...'"
    />
    <!-- Native-style header -->
    <header class="header">
      <div class="user-row" @click="copyCode">
        <div class="avatar avatar-sm" :style="{ background: auth.avatarColor }">
          <img v-if="isImageAvatar(auth.avatar)" :src="ensureAbsoluteUrl(auth.avatar)" class="avatar-img" referrerpolicy="no-referrer" />
          <span v-else-if="auth.avatar">{{ auth.avatar }}</span>
          <span v-else>{{ avatarLetter }}</span>
        </div>
        <div class="user-meta">
          <span class="user-name">{{ user?.name }}</span>
          <span class="user-code">{{ user?.uniqueCode }}</span>
          <span v-if="copied" class="copy-feedback">تم النسخ!</span>
        </div>
      </div>
      <div class="header-actions">
        <RouterLink to="/settings" class="nav-btn" aria-label="الإعدادات">
          <Settings :size="22" stroke-width="2" />
        </RouterLink>
        <button class="nav-btn" @click="openLogoutConfirm" aria-label="تسجيل الخروج">
          <LogOut :size="22" stroke-width="2" />
        </button>
      </div>
    </header>

    <!-- Incoming Connection Request Dialog -->
    <Transition name="modal">
      <div v-if="incomingRequest" class="logout-overlay" @click.self="declineConnectionRequest">
        <div class="request-dialog glass-card">
          <div class="request-dialog-icon"><Phone :size="48" stroke-width="2" /></div>
          <h3 class="request-dialog-title">طلب اتصال</h3>
          <p class="request-dialog-text">
            <strong>{{ incomingRequest.requesterName }}</strong> يريد الاتصال بك
          </p>
          <div class="request-dialog-actions">
            <button class="btn-decline" @click="declineConnectionRequest">
              <X :size="20" />
              <span>رفض</span>
            </button>
            <button class="btn-accept" @click="acceptConnectionRequest">
              <Check :size="20" />
              <span>قبول</span>
            </button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Cancel waiting (when user is requester) - shown above loader -->
    <Transition name="fade">
      <div v-if="waitingForAccept" class="cancel-wait-wrap">
        <button class="cancel-wait-btn" @click="cancelConnectionRequest">
          <PhoneOff :size="18" />
          <span>إلغاء الطلب</span>
        </button>
      </div>
    </Transition>

    <!-- Logout Confirm Dialog -->
    <Transition name="modal">
      <div v-if="showLogoutConfirm" class="logout-overlay" @click.self="showLogoutConfirm = false">
        <div class="logout-dialog glass-card">
          <div class="logout-dialog-icon"><LogOut :size="48" stroke-width="2" /></div>
          <h3 class="logout-dialog-title">تسجيل الخروج</h3>
          <p class="logout-dialog-text">هل أنت متأكد من تسجيل الخروج؟</p>
          <div class="logout-dialog-actions">
            <button class="btn-ghost" @click="showLogoutConfirm = false">إلغاء</button>
            <button class="logout-confirm-btn" @click="confirmLogout">تسجيل الخروج</button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Online indicator - native list style -->
    <div class="list-section">
      <div class="list-row">
        <span class="status-dot"></span>
        <span class="list-label">{{ onlineCount }} متصل الآن</span>
      </div>
    </div>

    <!-- Main CTA - native full-width pill -->
    <div class="main-cta-wrap">
      <button class="main-cta" :disabled="loading" @click="startRandom">
        <Zap :size="24" class="cta-icon" />
        <span>ابدأ محادثة عشوائية</span>
      </button>
    </div>

    <!-- Segmented control - iOS/Android style -->
    <div class="segment-wrap">
      <span class="segment-label">فلتر المطابقة</span>
      <div class="segment-control">
        <button
          v-for="f in genderFilters"
          :key="f.value"
          class="segment-btn"
          :class="{ active: matching.genderFilter === f.value }"
          @click="matching.genderFilter = f.value"
        >
          <component :is="f.Icon" :size="18" stroke-width="2" />
          <span>{{ f.label }}</span>
        </button>
      </div>
    </div>

    <!-- Divider -->
    <div class="divider">
      <span class="divider-txt">أو اتصل بكود</span>
    </div>

    <!-- Code input - native form style -->
    <div class="code-section">
      <input
        v-model="codeInput"
        class="code-input"
        placeholder="NX-A3B9"
        maxlength="7"
        @input="codeInput = codeInput.toUpperCase()"
        @keyup.enter="connectByCode"
      />
      <button
        class="code-submit"
        :class="{ disabled: !codeInput.trim() || loading }"
        :disabled="loading"
        @click="connectByCode"
      >
        اتصل
      </button>
      <p v-if="codeError" class="code-err">{{ codeError }}</p>
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

/* Native header - compact, full-width */
.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 8px) var(--spacing) 12px;
  background: var(--bg-primary);
  flex-shrink: 0;
}

.user-row {
  display: flex;
  align-items: center;
  gap: 12px;
  flex: 1;
  min-width: 0;
  padding: 4px 0;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.user-row:active { opacity: 0.8; }

.avatar {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  font-weight: 700;
  flex-shrink: 0;
  overflow: hidden;
}
.avatar-img { width: 100%; height: 100%; object-fit: cover; }

.user-meta {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.user-name { font-size: 17px; font-weight: 600; color: var(--text-primary); }
.user-code { font-size: 13px; color: var(--primary); font-weight: 600; letter-spacing: 1px; }
.copy-feedback { font-size: 12px; color: var(--success); }

.header-actions {
  display: flex;
  gap: 4px;
  flex-shrink: 0;
}

.nav-btn {
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: none;
  color: var(--text-secondary);
  cursor: pointer;
  border-radius: 10px;
  -webkit-tap-highlight-color: transparent;
}
.nav-btn:active { background: var(--bg-card); color: var(--text-primary); }
.nav-btn:hover { color: var(--text-primary); }

/* List section - native list style */
.list-section {
  padding: 0 var(--spacing);
  margin-bottom: 20px;
}

.list-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  background: var(--bg-card);
  border-radius: 12px;
}

.status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--success);
  flex-shrink: 0;
  animation: pulse 2s ease-in-out infinite;
}
@keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.5} }

.list-label { font-size: 15px; color: var(--text-secondary); }

/* Main CTA - native full-width pill */
.main-cta-wrap {
  padding: 0 var(--spacing) 20px;
}

.main-cta {
  width: 100%;
  min-height: 56px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  background: var(--primary);
  border: none;
  border-radius: 16px;
  color: white;
  font-size: 17px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  box-shadow: 0 4px 14px rgba(108, 99, 255, 0.4);
}
.main-cta:active { transform: scale(0.98); opacity: 0.95; }

.cta-icon { flex-shrink: 0; }

/* Segmented control */
.segment-wrap {
  padding: 0 var(--spacing) 24px;
}

.segment-label {
  display: block;
  font-size: 13px;
  color: var(--text-muted);
  margin-bottom: 8px;
  padding: 0 4px;
}

.segment-control {
  display: flex;
  background: var(--bg-card);
  border-radius: 12px;
  padding: 4px;
  gap: 4px;
}

.segment-btn {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  min-height: 40px;
  padding: 0 12px;
  background: transparent;
  border: none;
  border-radius: 10px;
  color: var(--text-secondary);
  font-size: 14px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: all 0.2s ease;
}
.segment-btn.active {
  background: var(--bg-primary);
  color: var(--primary);
  font-weight: 600;
  box-shadow: 0 1px 3px rgba(0,0,0,0.2);
}
.segment-btn:active:not(.active) { opacity: 0.8; }

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

/* Code section - native input style */
.code-section {
  padding: 0 var(--spacing) 24px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.code-input {
  width: 100%;
  min-height: 48px;
  padding: 0 16px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 12px;
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
.code-input:focus { border-color: var(--primary); }

.code-submit {
  min-height: 48px;
  padding: 0 20px;
  background: var(--primary);
  border: none;
  border-radius: 12px;
  color: white;
  font-size: 16px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.code-submit:active:not(.disabled) { opacity: 0.9; }
.code-submit.disabled { opacity: 0.4; cursor: not-allowed; }

.code-err {
  font-size: 13px;
  color: var(--danger);
  margin: 0;
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
