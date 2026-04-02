<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { Settings, LogOut, Zap, Globe, UserCircle, UsersRound, Phone, PhoneOff, PhoneCall, Check, X, AlertCircle, Bell, BookmarkPlus, Crown, ChevronRight, MessageCircle, Hash } from 'lucide-vue-next'
import BannerStrip from '../components/BannerStrip.vue'
import AppFooter from '../components/AppFooter.vue'
import HomeNavBar from '../components/HomeNavBar.vue'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { useAuthStore } from '../stores/auth'
import { useI18n } from 'vue-i18n'
import { useMatchingStore } from '../stores/matching'
import { useChatStore } from '../stores/chat'
import { useConversationsListStore } from '../stores/conversationsList'
import { useConversationStore } from '../stores/conversation'
import { matchingHub, conversationHub, startHub, ensureConnected, stopHub } from '../services/signalr'
import { requestMediaPermissions } from '../utils/mediaPermissions'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { publicUrl } from '../utils/publicUrl'
import { requestPermissionAndRegister, scheduleRegistrationRetry } from '../services/notifications'
import api from '../services/api'
import { getCodeConnectFeaturesEnabled } from '../services/siteContentFlags'

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

const router = useRouter()
const auth = useAuthStore()
const matching = useMatchingStore()
const chat = useChatStore()
const listStore = useConversationsListStore()
const convStore = useConversationStore()
const { t } = useI18n()

const codeInput = ref('')
const codeError = ref('')
const copied = ref(false)
const loading = ref(false)
const waitingForAccept = ref(false)
const showLogoutConfirm = ref(false)
const profileBannerDismissed = ref(false)
const notifPromptLoading = ref(false)
const randomChatEnabled = ref(true)
const randomChatSettingLoaded = ref(false)
const codeConnectEnabled = ref(true)
const codeConnectLoaded = ref(false)
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
  scheduleRegistrationRetry()

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

  try {
    await startHub(conversationHub)
    api.get('/conversations', { params: { filter: 'all' } }).then(({ data }) => {
      listStore.setList(data ?? [])
    }).catch(() => {})
    conversationHub.on('ConversationListUpdated', handleConversationListUpdated)
  } catch {}

  Promise.all([
    api.get('SiteContent/random_chat_enabled', { skipGlobalLoader: true })
      .then(({ data }) => {
        randomChatEnabled.value = (data?.content ?? 'true') === 'true'
      })
      .catch(() => {}),
    getCodeConnectFeaturesEnabled(api).then((enabled) => {
      codeConnectEnabled.value = enabled
    })
  ]).finally(() => {
    randomChatSettingLoaded.value = true
    codeConnectLoaded.value = true
  })
})

async function handleConversationListUpdated(payload) {
  const convId = payload?.conversationId ?? payload?.ConversationId
  if (!convId) return
  const preview = payload?.lastMessagePreview ?? payload?.LastMessagePreview ?? ''
  const at = payload?.lastMessageAt ?? payload?.LastMessageAt
  const senderId = String(payload?.senderId ?? payload?.SenderId ?? '')
  const currentId = String(auth.user?.id ?? '')
  const isViewing = String(convStore.conversationId ?? '') === String(convId)
  const isFromMe = senderId && currentId && senderId === currentId
  const shouldIncrementUnread = !isFromMe && !isViewing
  const updated = listStore.updateConversation(convId, {
    lastMessagePreview: preview,
    lastMessageAt: at,
    LastMessagePreview: preview,
    LastMessageAt: at
  }, shouldIncrementUnread)
  if (!updated) {
    api.get('/conversations', { params: { filter: 'all' } }).then(({ data: res }) => {
      listStore.setList(res ?? [])
    }).catch(() => {})
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
  conversationHub.off('ConversationListUpdated', handleConversationListUpdated)
})

function openLogoutConfirm() {
  showLogoutConfirm.value = true
}

function confirmLogout() {
  showLogoutConfirm.value = false
  stopHub(matchingHub)
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

/** بطاقة بديل فقط (دردشة عشوائية معطّلة + ميزة الكود معطّلة): نوسّط المحتوى ونملأ المسافة بين الهيدر والفوتر */
const homePrimaryCompact = computed(
  () =>
    randomChatSettingLoaded.value &&
    !randomChatEnabled.value &&
    codeConnectLoaded.value &&
    !codeConnectEnabled.value
)
</script>

<template>
  <div class="home page auth-pattern">
    <LoaderOverlay
      :show="loading"
      :text="waitingForAccept ? t('home.waitingForAccept') : t('home.connecting')"
    />
    <!-- مودال إكمال الملف للمستخدمين القدامى -->
    <Transition name="modal">
      <div v-if="auth.needsProfileContact && !profileBannerDismissed" class="logout-overlay" @click.self="profileBannerDismissed = true">
        <div class="logout-dialog glass-card profile-complete-modal">
          <div class="logout-dialog-icon"><Globe :size="48" stroke-width="2" /></div>
          <h3 class="logout-dialog-title">{{ t('completeProfile.bannerTitle') }}</h3>
          <p class="logout-dialog-text">{{ t('completeProfile.bannerText') }}</p>
          <div class="logout-dialog-actions">
            <button class="btn-ghost" @click="profileBannerDismissed = true">{{ t('completeProfile.dismiss') }}</button>
            <RouterLink to="/complete-profile" class="logout-confirm-btn profile-complete-btn" @click="profileBannerDismissed = true">{{ t('completeProfile.completeNow') }}</RouterLink>
          </div>
        </div>
      </div>
    </Transition>
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
            <Crown v-if="isFeatured" class="avatar-crown-home" :size="20" fill="currentColor" stroke-width="1" />
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

    <div class="home-scroll-body">
      <!-- CTA + Filter - unified section (hidden until API loaded, then by setting) -->
      <div
        class="home-primary"
        :class="{ 'home-primary--compact': homePrimaryCompact }"
      >
        <div v-if="randomChatSettingLoaded && randomChatEnabled" class="cta-filter-card">
          <div class="main-cta-wrap">
            <button class="main-cta-circle" :disabled="loading" @click="startRandom">
              <Vue3Lottie
                :animation-link="publicUrl('json/chat.json')"
                :height="88"
                :width="88"
                :speed="0.85"
                :loop="true"
                :auto-play="true"
                class="cta-circle-lottie"
              />
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

        <!-- Replacement card when random chat is disabled (only after API loaded) -->
        <div v-if="randomChatSettingLoaded && !randomChatEnabled && codeConnectLoaded" class="cta-replacement-card">
          <div class="cta-replacement-lottie">
            <Vue3Lottie
              :animation-link="publicUrl('json/chat.json')"
              :height="80"
              :width="120"
              :speed="0.7"
              :loop="true"
              :auto-play="true"
            />
          </div>
          <template v-if="codeConnectEnabled">
            <h3 class="cta-replacement-title">{{ t('home.connectWithCodeTitle') }}</h3>
            <p class="cta-replacement-desc">{{ t('home.connectWithCodeDesc') }}</p>
          </template>
          <template v-else>
            <h3 class="cta-replacement-title">{{ t('home.randomOffNoCodeTitle') }}</h3>
            <p class="cta-replacement-desc">{{ t('home.randomOffNoCodeDesc') }}</p>
          </template>
          <RouterLink to="/conversations" class="cta-replacement-btn">
            <MessageCircle :size="20" stroke-width="2" />
            <span>{{ t('home.goToConversations') }}</span>
          </RouterLink>
        </div>

        <template v-if="codeConnectLoaded && codeConnectEnabled">
          <section class="code-connect-card" aria-labelledby="code-connect-heading">
            <div class="code-connect-card__accent" aria-hidden="true" />
            <div class="code-connect-card__body">
              <h2 id="code-connect-heading" class="code-connect-card__heading">
                {{ t('home.orConnectByCode') }}
              </h2>

              <RouterLink to="/saved-codes" class="saved-codes-tile">
                <div class="saved-codes-tile__icon-wrap" aria-hidden="true">
                  <BookmarkPlus :size="22" stroke-width="2" />
                </div>
                <div class="saved-codes-tile__text">
                  <span class="saved-codes-tile__title">{{ t('home.savedCodes') }}</span>
                  <span class="saved-codes-tile__sub">{{ t('home.savedCodesTileHint') }}</span>
                </div>
                <ChevronRight :size="20" stroke-width="2" class="saved-codes-tile__chev" />
              </RouterLink>

              <div class="code-connect-divider" role="presentation">
                <span class="code-connect-divider__line" />
                <span class="code-connect-divider__dot" />
                <span class="code-connect-divider__line" />
              </div>

              <div class="code-section">
                <label class="code-field-label" for="home-user-code-input">{{ t('home.enterUserCode') }}</label>
                <div class="code-input-wrap">
                  <span class="code-input-prefix" aria-hidden="true">
                    <Hash :size="20" stroke-width="2" />
                  </span>
                  <input
                    id="home-user-code-input"
                    v-model="codeInput"
                    class="code-input"
                    type="text"
                    inputmode="text"
                    autocomplete="off"
                    autocapitalize="characters"
                    :placeholder="t('home.enterUserCode')"
                    maxlength="7"
                    @input="codeInput = codeInput.toUpperCase()"
                    @keyup.enter="connectByCode"
                  />
                  <button
                    type="button"
                    class="code-submit"
                    :class="{ disabled: !codeInput.trim() || loading }"
                    :disabled="!codeInput.trim() || loading"
                    :aria-label="t('home.connect')"
                    @click="connectByCode"
                  >
                    <PhoneCall :size="22" stroke-width="2" />
                  </button>
                </div>
                <div v-if="codeError" class="error-toast code-error-toast">
                  <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
                  <span>{{ codeError }}</span>
                </div>
              </div>
            </div>
          </section>
        </template>
      </div>

      <div class="home-bottom">
        <BannerStrip placement="home" />
        <AppFooter />
        <!-- مساحة في التدفق تحت الفوتر؛ padding على الأب وحده لا يكفي في بعض WebView مع margin-top:auto -->
        <div class="home-nav-spacer" aria-hidden="true" />
      </div>
    </div>

    <HomeNavBar :loading="loading" :random-chat-enabled="randomChatSettingLoaded && randomChatEnabled" @launch="startRandom" />
  </div>
</template>

<style scoped>
.home {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  min-height: 100%;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
}

/* يملأ المسافة تحت الهيدر: المحتوى الرئيسي ثم الفوتر مثبت أسفل المنطقة عند وجود فراغ */
.home-scroll-body {
  flex: 1 1 auto;
  display: flex;
  flex-direction: column;
  width: 100%;
  min-height: 0;
}

/* عنصر بارتفاع ثابت داخل .home-bottom تحت AppFooter — يدفع «NexChat» فوق الناف الثابت */
.home-nav-spacer {
  flex-shrink: 0;
  width: 100%;
  height: var(--home-nav-clearance);
  min-height: var(--home-nav-clearance);
  pointer-events: none;
}

.home-primary {
  display: flex;
  flex-direction: column;
  width: 100%;
  flex: 0 0 auto;
}

.home-primary.home-primary--compact {
  flex: 1 1 auto;
  justify-content: center;
  padding-block: 20px;
}

.home-bottom {
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 100%;
  padding-top: 8px;
  flex-shrink: 0;
  margin-top: auto;
  box-sizing: border-box;
}

.profile-complete-modal .logout-dialog-icon { color: var(--primary); }
.profile-complete-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--primary) !important;
  text-decoration: none;
  color: white;
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
  margin-top: 5px;
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
  color: rgba(255, 115, 0, 1);
  filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3));
  z-index: 1;
}

/* Light mode - تاج وإطار بلون #FF7300 */
[data-theme="light"] .avatar-wrap.avatar-wrap-featured::after,
html.light .avatar-wrap.avatar-wrap-featured::after {
  border-color: rgba(255, 115, 0, 0.6);
  box-shadow: 0 0 12px rgba(255, 115, 0, 0.3);
}
[data-theme="light"] .avatar-crown-home,
html.light .avatar-crown-home {
  color: #FF7300;
  filter: drop-shadow(0 1px 2px rgba(255, 115, 0, 0.2));
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

/* CTA + Filter - unified card */
.cta-filter-card {
  margin: 10px var(--spacing) 24px;
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

/* Replacement card when random chat is disabled */
.cta-replacement-card {
  margin: 10px var(--spacing) 24px;
  padding: 24px var(--spacing);
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 16px;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.06);
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  text-align: center;
}
.cta-replacement-lottie {
  display: flex;
  justify-content: center;
  align-items: center;
  margin: -8px 0 0;
}
.cta-replacement-title {
  margin: 0;
  font-size: 1.1rem;
  font-weight: 600;
  color: var(--text-primary);
}
.cta-replacement-desc {
  margin: 0;
  font-size: 0.9rem;
  color: var(--text-secondary);
  line-height: 1.4;
}
.cta-replacement-btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 12px 20px;
  background: var(--primary);
  color: white;
  border-radius: 12px;
  font-weight: 600;
  text-decoration: none;
  -webkit-tap-highlight-color: transparent;
  transition: opacity 0.2s, transform 0.2s;
}
.cta-replacement-btn:active {
  opacity: 0.9;
  transform: scale(0.98);
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

/* ——— بطاقة الاتصال بالكود (موحّدة مع أسلوب الصفحة) ——— */
.code-connect-card {
  position: relative;
  margin: 8px var(--spacing) 20px;
  border-radius: 20px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  box-shadow:
    0 4px 24px rgba(0, 0, 0, 0.06),
    0 1px 0 rgba(255, 255, 255, 0.04) inset;
  overflow: hidden;
}

[data-theme="light"] .code-connect-card {
  box-shadow: 0 4px 20px rgba(108, 99, 255, 0.08);
}

.code-connect-card__accent {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 3px;
  background: linear-gradient(90deg, #6C63FF 0%, #FF6584 50%, #00D4FF 100%);
  opacity: 0.9;
}

.code-connect-card__body {
  position: relative;
  z-index: 1;
  padding: 18px 16px 20px;
  background: radial-gradient(ellipse 120% 80% at 50% -20%, rgba(108, 99, 255, 0.09) 0%, transparent 55%);
}

.code-connect-card__heading {
  margin: 0 0 14px;
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
  text-align: center;
  letter-spacing: 0.02em;
}

.saved-codes-tile {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 14px 14px;
  border-radius: 16px;
  text-decoration: none;
  -webkit-tap-highlight-color: transparent;
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.08) 0%, rgba(255, 101, 132, 0.05) 100%);
  border: 1px solid rgba(108, 99, 255, 0.18);
  transition: transform 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease;
}
.saved-codes-tile:active {
  transform: scale(0.99);
  border-color: rgba(108, 99, 255, 0.35);
}

.saved-codes-tile__icon-wrap {
  flex-shrink: 0;
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 14px;
  background: rgba(108, 99, 255, 0.15);
  color: var(--primary);
  box-shadow: 0 2px 8px rgba(108, 99, 255, 0.2);
}

.saved-codes-tile__text {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
  text-align: start;
}

.saved-codes-tile__title {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
}

.saved-codes-tile__sub {
  font-size: 12px;
  color: var(--text-muted);
  line-height: 1.35;
}

.saved-codes-tile__chev {
  flex-shrink: 0;
  color: var(--text-muted);
  opacity: 0.85;
}

.code-connect-divider {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 16px 0 14px;
  padding: 0 4px;
}

.code-connect-divider__line {
  flex: 1;
  height: 1px;
  background: linear-gradient(
    90deg,
    transparent,
    var(--border) 20%,
    var(--border) 80%,
    transparent
  );
  opacity: 0.9;
}

.code-connect-divider__dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--primary), #FF6584);
  opacity: 0.75;
  flex-shrink: 0;
}

/* حقل إدخال الكود */
.code-section {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 0;
}

.code-field-label {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-muted);
  padding-inline-start: 4px;
  margin: 0;
}

.code-input-wrap {
  position: relative;
  display: flex;
  align-items: stretch;
  min-height: 54px;
  background: var(--bg-primary);
  border: 1px solid var(--border);
  border-radius: 16px;
  overflow: hidden;
  transition: border-color 0.2s, box-shadow 0.2s;
}
.code-input-wrap:focus-within {
  border-color: var(--primary);
  box-shadow: 0 0 0 3px rgba(108, 99, 255, 0.18);
}

.code-input-prefix {
  display: flex;
  align-items: center;
  justify-content: center;
  padding-inline-start: 14px;
  padding-inline-end: 6px;
  color: var(--text-muted);
  flex-shrink: 0;
  opacity: 0.85;
}

.code-input {
  flex: 1;
  min-width: 0;
  min-height: 52px;
  padding-block: 0;
  padding-inline-start: 0;
  padding-inline-end: 58px;
  background: transparent;
  border: none;
  color: var(--text-primary);
  font-size: 17px;
  font-weight: 700;
  font-family: ui-monospace, 'Cairo', monospace;
  letter-spacing: 0.12em;
  text-align: start;
  outline: none;
  -webkit-appearance: none;
  appearance: none;
}
.code-input::placeholder {
  color: var(--text-muted);
  font-weight: 500;
  letter-spacing: 0.04em;
}

.code-submit {
  position: absolute;
  top: 50%;
  inset-inline-end: 6px;
  transform: translateY(-50%);
  width: 44px;
  height: 44px;
  min-width: 44px;
  min-height: 44px;
  padding: 0;
  border-radius: 50%;
  background: linear-gradient(145deg, #7C75FF 0%, var(--primary) 55%, #5B54E8 100%);
  border: none;
  color: white;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  box-shadow: 0 4px 14px rgba(108, 99, 255, 0.35);
  transition: transform 0.15s ease, opacity 0.2s, box-shadow 0.2s;
  display: flex;
  align-items: center;
  justify-content: center;
}
.code-submit.disabled {
  opacity: 0.45;
  background: var(--bg-card-hover);
  color: var(--text-muted);
  box-shadow: none;
  cursor: not-allowed;
  transform: translateY(-50%);
}
.code-submit:active:not(.disabled) {
  transform: translateY(-50%) scale(0.94);
}

.code-error-toast {
  margin-top: 4px;
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
