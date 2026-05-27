<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { Globe, UserCircle, UsersRound, PhoneOff, PhoneCall, AlertCircle, Bell, BookmarkPlus, Crown, ChevronLeft, ChevronRight, MessageCircle, Hash, Copy } from 'lucide-vue-next'
import { useLocaleStore } from '../stores/locale'
import BannerStrip from '../components/BannerStrip.vue'
import AppFooter from '../components/AppFooter.vue'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { useAuthStore } from '../stores/auth'
import { useI18n } from 'vue-i18n'
import { useMatchingStore } from '../stores/matching'
import { useChatStore } from '../stores/chat'
import { useConversationsListStore } from '../stores/conversationsList'
import { useConversationStore } from '../stores/conversation'
import { useNotificationsStore } from '../stores/notifications'
import { matchingHub, conversationHub, startHub, ensureConnected, stopHub } from '../services/signalr'
import { requestMediaPermissions } from '../utils/mediaPermissions'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { publicUrl } from '../utils/publicUrl'
import { requestPermissionAndRegister, scheduleRegistrationRetry } from '../services/notifications'
import api from '../services/api'
import { getCodeConnectFeaturesEnabled, getShortFilmsEnabled } from '../services/siteContentFlags'
import { formatConversationListPreview } from '../utils/shortFilmShare'

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

const router = useRouter()
const auth = useAuthStore()
const matching = useMatchingStore()
const chat = useChatStore()
const listStore = useConversationsListStore()
const convStore = useConversationStore()
const notificationsStore = useNotificationsStore()
const { t } = useI18n()
const localeStore = useLocaleStore()

const codeInput = ref('')
const codeError = ref('')
const copied = ref(false)
const loading = ref(false)
const waitingForAccept = ref(false)
const profileBannerDismissed = ref(false)
const notifPromptLoading = ref(false)
const randomChatEnabled = ref(true)
const randomChatSettingLoaded = ref(false)
const codeConnectEnabled = ref(true)
const codeConnectLoaded = ref(false)
const shortFilmsEnabled = ref(true)
const shortFilmsLoaded = ref(false)
let connectionTimeoutId = null

const user = computed(() => auth.user)
const avatarLetter = computed(() => user.value?.name?.[0]?.toUpperCase() || '?')
const isFeatured = computed(() => user.value?.isFeatured ?? false)

function matchFoundHandler() {
  clearConnectionTimeout()
  waitingForAccept.value = false
  loading.value = false
}

function onNotifEvent(e) {
  if (e?.detail) notificationsStore.add(e.detail)
}

onMounted(async () => {
  notificationsStore.load()
  window.addEventListener('nexchat:notification', onNotifEvent)
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
      const list = (data ?? []).map((c) => {
        const raw = c?.lastMessagePreview ?? c?.LastMessagePreview ?? ''
        const formatted = formatConversationListPreview(raw, t('shortFilms.title'))
        if (formatted === raw) return c
        return { ...c, lastMessagePreview: formatted, LastMessagePreview: formatted }
      })
      listStore.setList(list)
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
    }),
    getShortFilmsEnabled(api).then((enabled) => {
      shortFilmsEnabled.value = enabled
    })
  ]).finally(() => {
    randomChatSettingLoaded.value = true
    codeConnectLoaded.value = true
    shortFilmsLoaded.value = true
  })
})

async function handleConversationListUpdated(payload) {
  const convId = payload?.conversationId ?? payload?.ConversationId
  if (!convId) return
  const rawPreview = payload?.lastMessagePreview ?? payload?.LastMessagePreview ?? ''
  const preview = formatConversationListPreview(rawPreview, t('shortFilms.title'))
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
      const list = (res ?? []).map((c) => {
        const raw = c?.lastMessagePreview ?? c?.LastMessagePreview ?? ''
        const formatted = formatConversationListPreview(raw, t('shortFilms.title'))
        if (formatted === raw) return c
        return { ...c, lastMessagePreview: formatted, LastMessagePreview: formatted }
      })
      listStore.setList(list)
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
  window.removeEventListener('nexchat:notification', onNotifEvent)
  clearConnectionTimeout()
  matchingHub.off('MatchFound', matchFoundHandler)
  matchingHub.off('SearchCancelled')
  matchingHub.off('CodeError')
  matchingHub.off('ConnectionRequestSent')
  matchingHub.off('ConnectionDeclined')
  matchingHub.off('ConnectionCancelled')
  conversationHub.off('ConversationListUpdated', handleConversationListUpdated)
})

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
  <div class="home page home--chatloop">
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

    <header class="home-header">
      <h1 class="home-header__title">{{ t('nav.connect') }}</h1>
      <RouterLink
        to="/notifications"
        class="home-header__bell"
        :aria-label="t('settings.notifications')"
      >
        <Bell :size="20" stroke-width="2" />
        <span v-if="notificationsStore.unreadCount > 0" class="home-header__bell-dot" />
      </RouterLink>
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
      <RouterLink
        v-if="user?.id"
        :to="`/profile/${user.id}`"
        class="home-profile"
      >
        <div class="home-profile__avatar-wrap" :class="{ 'home-profile__avatar-wrap--featured': isFeatured }">
          <div class="home-profile__avatar" :style="{ background: auth.avatarColor }">
            <img v-if="isImageAvatar(auth.avatar)" :src="ensureAbsoluteUrl(auth.avatar)" class="avatar-img" referrerpolicy="no-referrer" />
            <span v-else-if="auth.avatar">{{ auth.avatar }}</span>
            <span v-else>{{ avatarLetter }}</span>
          </div>
          <Crown v-if="isFeatured" class="home-profile__crown" :size="14" fill="currentColor" stroke-width="1.5" />
        </div>
        <div class="home-profile__meta">
          <span class="home-profile__greeting">{{ t('home.greeting') }}</span>
          <span class="home-profile__name">{{ user?.name }}</span>
        </div>
        <button
          v-if="user?.uniqueCode"
          type="button"
          class="home-profile__code"
          dir="ltr"
          @click.prevent="copyCode"
        >
          <Hash :size="13" stroke-width="2" />
          <span>{{ user.uniqueCode }}</span>
          <Copy :size="13" stroke-width="2" />
          <span v-if="copied" class="home-profile__copied">{{ t('common.copiedShort') }}</span>
        </button>
      </RouterLink>

      <div
        class="home-primary"
        :class="{ 'home-primary--compact': homePrimaryCompact }"
      >
        <article class="home-hub">
          <div v-if="randomChatSettingLoaded && randomChatEnabled" class="home-hub__block">
            <button class="home-start" :disabled="loading" @click="startRandom">
              <span class="home-start__icon">
                <Vue3Lottie
                  :animation-link="publicUrl('json/chat.json')"
                  :height="52"
                  :width="52"
                  :speed="0.85"
                  :loop="true"
                  :auto-play="true"
                />
              </span>
              <span class="home-start__text">
                <span class="home-start__title">{{ t('home.startRandom') }}</span>
                <span class="home-start__sub">{{ t('matching.secureSearch') }}</span>
              </span>
              <component :is="localeStore.isRtl ? ChevronLeft : ChevronRight" :size="22" stroke-width="2" class="home-start__arrow" />
            </button>

            <div class="home-segment" role="tablist" :aria-label="t('home.filterLabel')">
              <button
                v-for="f in genderFilters"
                :key="f.value"
                type="button"
                class="home-segment__btn"
                :class="{ 'home-segment__btn--active': matching.genderFilter === f.value }"
                @click="matching.genderFilter = f.value"
              >
                <component :is="f.Icon" :size="16" stroke-width="2" />
                <span>{{ f.label }}</span>
              </button>
            </div>
          </div>

          <div v-else-if="randomChatSettingLoaded && !randomChatEnabled && codeConnectLoaded" class="home-hub__block home-hub__block--center">
            <div class="home-hub__illus">
              <Vue3Lottie
                :animation-link="publicUrl('json/chat.json')"
                :height="64"
                :width="96"
                :speed="0.7"
                :loop="true"
                :auto-play="true"
              />
            </div>
            <h3 class="home-hub__fallback-title">
              {{ codeConnectEnabled ? t('home.connectWithCodeTitle') : t('home.randomOffNoCodeTitle') }}
            </h3>
            <p class="home-hub__fallback-desc">
              {{ codeConnectEnabled ? t('home.connectWithCodeDesc') : t('home.randomOffNoCodeDesc') }}
            </p>
            <RouterLink to="/conversations" class="home-start home-start--secondary">
              <MessageCircle :size="22" stroke-width="2" />
              <span class="home-start__title">{{ t('home.goToConversations') }}</span>
            </RouterLink>
          </div>

          <template v-if="codeConnectLoaded && codeConnectEnabled">
            <div v-if="randomChatSettingLoaded && randomChatEnabled" class="home-hub__divider" aria-hidden="true">
              <span class="home-hub__divider-line" />
              <span class="home-hub__divider-text">{{ t('home.orConnectByCode') }}</span>
              <span class="home-hub__divider-line" />
            </div>

            <div class="home-code">
              <div class="home-code__field">
                <Hash :size="18" stroke-width="2" class="home-code__hash" />
                <input
                  id="home-user-code-input"
                  v-model="codeInput"
                  class="home-code__input"
                  type="text"
                  inputmode="text"
                  autocomplete="off"
                  autocapitalize="characters"
                  :placeholder="t('home.enterUserCode')"
                  maxlength="7"
                  dir="ltr"
                  @input="codeInput = codeInput.toUpperCase()"
                  @keyup.enter="connectByCode"
                />
                <button
                  type="button"
                  class="home-code__call"
                  :disabled="!codeInput.trim() || loading"
                  :aria-label="t('home.connect')"
                  @click="connectByCode"
                >
                  <PhoneCall :size="20" stroke-width="2" />
                </button>
              </div>
              <div v-if="codeError" class="home-code__error">
                <AlertCircle :size="15" stroke-width="2" />
                <span>{{ codeError }}</span>
              </div>
            </div>
          </template>
        </article>

        <div v-if="(shortFilmsLoaded && shortFilmsEnabled) || (codeConnectLoaded && codeConnectEnabled)" class="home-shortcuts">
          <RouterLink
            v-if="shortFilmsLoaded && shortFilmsEnabled"
            to="/short-films"
            class="home-shortcut"
          >
            <span class="home-shortcut__icon home-shortcut__icon--film">
              <Vue3Lottie
                :animation-link="publicUrl('json/shortFilm.json')"
                :height="32"
                :width="32"
                :speed="1"
                :loop="true"
                :auto-play="true"
              />
            </span>
            <span class="home-shortcut__label">{{ t('shortFilms.title') }}</span>
          </RouterLink>
          <RouterLink
            v-if="codeConnectLoaded && codeConnectEnabled"
            to="/saved-codes"
            class="home-shortcut"
          >
            <span class="home-shortcut__icon">
              <BookmarkPlus :size="22" stroke-width="2" />
            </span>
            <span class="home-shortcut__label">{{ t('home.savedCodes') }}</span>
          </RouterLink>
        </div>
      </div>

      <div class="home-bottom">
        <BannerStrip placement="home" />
        <AppFooter />
        <!-- مساحة في التدفق تحت الفوتر؛ padding على الأب وحده لا يكفي في بعض WebView مع margin-top:auto -->
        <div class="tab-bar-spacer" aria-hidden="true" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.home--chatloop {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  min-height: 100%;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  font-family: 'Cairo', sans-serif;
}

/* يملأ المسافة تحت الهيدر: المحتوى الرئيسي ثم الفوتر مثبت أسفل المنطقة عند وجود فراغ */
.home-scroll-body {
  flex: 1 1 auto;
  display: flex;
  flex-direction: column;
  width: 100%;
  min-height: 0;
}

/* عنصر بارتفاع ثابت داخل .home-bottom تحت AppFooter — يدفع «NexChat» فوق شريط التبويب */
.home-nav-spacer,
.tab-bar-spacer {
  flex-shrink: 0;
  width: 100%;
  height: var(--tab-bar-clearance);
  min-height: var(--tab-bar-clearance);
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

.home-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 10px) var(--spacing) 8px;
  flex-shrink: 0;
  background: var(--bg-primary);
}

.home-header__title {
  margin: 0;
  font-size: 22px;
  font-weight: 800;
  color: var(--text-primary);
  letter-spacing: -0.02em;
}

.home-header__bell {
  position: relative;
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 14px;
  background: var(--bg-card);
  color: var(--text-secondary);
  box-shadow: var(--shadow-sm);
  text-decoration: none;
  -webkit-tap-highlight-color: transparent;
}

.home-header__bell-dot {
  position: absolute;
  top: 8px;
  inset-inline-end: 8px;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #EF4444;
  border: 2px solid var(--bg-card);
}

.home-profile {
  display: flex;
  align-items: center;
  gap: 12px;
  margin: 0 var(--spacing) 16px;
  padding: 4px 2px;
  text-decoration: none;
  color: inherit;
  -webkit-tap-highlight-color: transparent;
}

.home-profile__avatar-wrap { position: relative; flex-shrink: 0; }
.home-profile__avatar-wrap--featured .home-profile__avatar {
  box-shadow: 0 0 0 2px rgba(255, 115, 0, 0.4);
}

.home-profile__avatar {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  font-weight: 700;
  color: #fff;
  overflow: hidden;
  border: 2px solid var(--primary-muted);
}

.home-profile__avatar .avatar-img { width: 100%; height: 100%; object-fit: cover; }
.home-profile__crown { position: absolute; top: -2px; inset-inline-end: -2px; color: #ff7300; z-index: 1; }

.home-profile__meta {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.home-profile__greeting { font-size: 12px; color: var(--text-muted); }
.home-profile__name {
  font-size: 17px;
  font-weight: 800;
  color: var(--text-primary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.home-profile__code {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 8px 10px;
  border: none;
  border-radius: var(--radius-full);
  background: var(--primary-soft);
  color: var(--primary);
  font-family: ui-monospace, 'Cairo', monospace;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.06em;
  cursor: pointer;
  flex-shrink: 0;
  position: relative;
}

.home-profile__copied {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: inherit;
  background: var(--success);
  color: #fff;
  font-family: 'Cairo', sans-serif;
  font-size: 10px;
}

.home-hub {
  margin: 0 var(--spacing) 14px;
  padding: 18px 16px 16px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 28px;
  box-shadow: var(--shadow-md);
}

.home-hub__block--center {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  gap: 8px;
}

.home-hub__illus { margin-bottom: 4px; }

.home-hub__fallback-title {
  margin: 0;
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
}

.home-hub__fallback-desc {
  margin: 0 0 8px;
  font-size: 14px;
  color: var(--text-secondary);
  line-height: 1.45;
}

.home-start {
  display: flex;
  align-items: center;
  gap: 14px;
  width: 100%;
  padding: 14px 16px;
  border: none;
  border-radius: 20px;
  background: linear-gradient(135deg, #3B82F6 0%, #2563EB 100%);
  color: #fff;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  text-decoration: none;
  box-shadow: 0 8px 24px rgba(37, 99, 235, 0.28);
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.2s, box-shadow 0.2s;
}

.home-start:active:not(:disabled) { transform: scale(0.98); }
.home-start:disabled { opacity: 0.65; cursor: not-allowed; }

.home-start--secondary {
  justify-content: center;
  gap: 10px;
  max-width: 100%;
}

.home-start__icon {
  width: 56px;
  height: 56px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.18);
  overflow: hidden;
}

.home-start__text {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
  text-align: start;
}

.home-start__title {
  font-size: 16px;
  font-weight: 700;
  line-height: 1.25;
}

.home-start__sub {
  font-size: 12px;
  font-weight: 500;
  opacity: 0.88;
}

.home-start__arrow {
  flex-shrink: 0;
  opacity: 0.85;
}

.home-segment {
  display: flex;
  gap: 6px;
  margin-top: 14px;
  padding: 4px;
  background: var(--bg-elevated);
  border-radius: 16px;
  border: 1px solid var(--border);
}

.home-segment__btn {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  min-height: 52px;
  padding: 6px 4px;
  border: none;
  border-radius: 12px;
  background: transparent;
  color: var(--text-muted);
  font-family: 'Cairo', sans-serif;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.2s, color 0.2s, box-shadow 0.2s;
}

.home-segment__btn--active {
  background: var(--bg-card);
  color: var(--primary);
  box-shadow: var(--shadow-sm);
}

.home-hub__divider {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 18px 0 14px;
}

.home-hub__divider-line {
  flex: 1;
  height: 1px;
  background: var(--border);
}

.home-hub__divider-text {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-muted);
  white-space: nowrap;
}

.home-code__field {
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 52px;
  padding: 0 6px 0 14px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: var(--radius-xl);
  transition: border-color 0.2s, box-shadow 0.2s;
}

.home-code__field:focus-within {
  border-color: var(--primary);
  box-shadow: 0 0 0 3px var(--primary-soft);
}

.home-code__hash { color: var(--text-muted); flex-shrink: 0; }

.home-code__input {
  flex: 1;
  min-width: 0;
  border: none;
  background: transparent;
  font-family: ui-monospace, 'Cairo', monospace;
  font-size: 16px;
  font-weight: 700;
  letter-spacing: 0.12em;
  color: var(--text-primary);
  outline: none;
}

.home-code__input::placeholder {
  color: var(--text-muted);
  font-weight: 500;
  letter-spacing: 0.04em;
}

.home-code__call {
  width: 42px;
  height: 42px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  border: none;
  border-radius: 50%;
  background: var(--primary);
  color: #fff;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.home-code__call:disabled {
  opacity: 0.4;
  background: var(--bg-card-hover);
  color: var(--text-muted);
  cursor: not-allowed;
}

.home-code__error {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 10px;
  padding: 10px 12px;
  border-radius: 12px;
  background: rgba(244, 67, 54, 0.08);
  color: var(--danger);
  font-size: 13px;
}

.home-shortcuts {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
  margin: 0 var(--spacing) 16px;
}

.home-shortcut {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 96px;
  padding: 14px 10px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 20px;
  box-shadow: var(--shadow-sm);
  text-decoration: none;
  color: inherit;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.15s;
}

.home-shortcut:active { transform: scale(0.98); }

.home-shortcut__icon {
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 14px;
  background: var(--primary-soft);
  color: var(--primary);
  overflow: hidden;
}

.home-shortcut__icon--film { padding: 0; }

.home-shortcut__label {
  font-size: 13px;
  font-weight: 700;
  color: var(--text-primary);
  text-align: center;
  line-height: 1.3;
}

@media (max-width: 360px) {
  .home-profile { flex-wrap: wrap; }
  .home-profile__code { margin-inline-start: auto; }
  .home-shortcuts { grid-template-columns: 1fr; }
  .home-shortcut { min-height: 72px; flex-direction: row; justify-content: flex-start; padding-inline: 16px; }
  .home-shortcut__label { text-align: start; }
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
