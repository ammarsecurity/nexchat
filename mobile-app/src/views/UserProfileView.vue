<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronRight, Copy, MessageCircle, Crown, UserPlus, Check } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import CachedAvatar from '../components/CachedAvatar.vue'
import {
  createPrivateConversationOrRequest,
  goToMessageRequestsOutgoingNotice,
  validate409AsSuccess
} from '../utils/conversationOrMessageRequest'
import { useMessageRequestsStore } from '../stores/messageRequests'

const msgReqStore = useMessageRequestsStore()

// المسار الافتراضي من الحوار: إضافة كجهة اتصال ثم فتح المحادثة. البديل: طلب مراسلة فقط (يُعرض في صفحة طلبات المراسلة لدى المستقبل).
const route = useRoute()
const router = useRouter()
const { t } = useI18n()

const userId = computed(() => route.params.userId)
const profile = ref(null)
const loading = ref(true)
const error = ref(false)
const copiedCode = ref(false)
const copiedPhone = ref(false)
const startingChat = ref(false)
const addingContact = ref(false)
const conversationIdFromState = ref(null)
const showChatGateModal = ref(false)
const chatGateBusy = ref(false)
const chatGateError = ref('')
const chatGateSuccess = ref('')

const formattedPhone = computed(() => {
  const phone = profile.value?.phoneNumber ?? profile.value?.PhoneNumber
  if (!phone || typeof phone !== 'string') return null
  const digits = phone.replace(/\D/g, '')
  if (!digits.length) return null
  if (digits.length <= 4) return `+${digits}`
  return `+${digits.slice(0, 3)} ${digits.slice(3).replace(/(\d{3})(?=\d)/g, '$1 ').trim()}`
})

const genderLabel = computed(() => ({
  male: t('profile.genderMale'),
  female: t('profile.genderFemale'),
  other: t('profile.genderOther')
}))

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

function goBack() {
  if (conversationIdFromState.value) router.replace(`/conversation/${conversationIdFromState.value}`)
  else router.replace('/conversations')
}

async function fetchProfile() {
  if (!userId.value) return
  loading.value = true
  error.value = false
  try {
    const { data } = await api.get(`/user/profile/${userId.value}`, { skipGlobalLoader: true })
    profile.value = data
  } catch {
    profile.value = null
    error.value = true
  } finally {
    loading.value = false
  }
}

async function copyCode() {
  const code = profile.value?.uniqueCode ?? profile.value?.UniqueCode
  if (!code) return
  try {
    await navigator.clipboard.writeText(code)
    copiedCode.value = true
    setTimeout(() => { copiedCode.value = false }, 2000)
  } catch {}
}

async function copyPhone() {
  const phone = profile.value?.phoneNumber ?? profile.value?.PhoneNumber
  if (!phone) return
  try {
    await navigator.clipboard.writeText(phone.startsWith('+') ? phone : `+${phone}`)
    copiedPhone.value = true
    setTimeout(() => { copiedPhone.value = false }, 2000)
  } catch {}
}

const isContact = computed(() => profile.value?.isContact ?? profile.value?.IsContact ?? false)

function closeChatGateModal() {
  if (chatGateBusy.value) return
  showChatGateModal.value = false
  chatGateError.value = ''
  chatGateSuccess.value = ''
}

async function openChat() {
  const convId = conversationIdFromState.value
  if (convId) {
    router.replace(`/conversation/${convId}`)
    return
  }
  if (!profile.value?.id && !profile.value?.Id) return
  const id = profile.value.id ?? profile.value.Id
  if (isContact.value) {
    startingChat.value = true
    try {
      const r = await createPrivateConversationOrRequest(id)
      if (r.kind === 'conversation' && r.conversationId) {
        router.replace(`/conversation/${r.conversationId}`)
      } else {
        await msgReqStore.fetchPendingCount()
        goToMessageRequestsOutgoingNotice(router)
      }
    } catch (e) {
      window.alert(e.userMessage ?? e.response?.data?.message ?? t('common.error'))
    } finally {
      startingChat.value = false
    }
    return
  }
  chatGateError.value = ''
  chatGateSuccess.value = ''
  showChatGateModal.value = true
}

async function confirmAddAndChat() {
  if (!userId.value || !profile.value) return
  const id = profile.value.id ?? profile.value.Id
  chatGateBusy.value = true
  chatGateError.value = ''
  chatGateSuccess.value = ''
  try {
    await api.post(`/contacts/by-user/${userId.value}`, {}, { skipGlobalLoader: true })
    profile.value = { ...profile.value, isContact: true, IsContact: true }
    const r = await createPrivateConversationOrRequest(id)
    showChatGateModal.value = false
    if (r.kind === 'conversation' && r.conversationId) {
      router.replace(`/conversation/${r.conversationId}`)
    } else {
      await msgReqStore.fetchPendingCount()
      goToMessageRequestsOutgoingNotice(router)
    }
  } catch (e) {
    chatGateError.value = e.userMessage ?? e.response?.data?.message ?? t('common.error')
  } finally {
    chatGateBusy.value = false
  }
}

async function sendMessageRequestOnly() {
  if (!profile.value) return
  const id = profile.value.id ?? profile.value.Id
  chatGateBusy.value = true
  chatGateError.value = ''
  chatGateSuccess.value = ''
  try {
    await api.post('/message-requests', { targetUserId: id }, {
      skipGlobalLoader: true,
      ...validate409AsSuccess
    })
    showChatGateModal.value = false
    await msgReqStore.fetchPendingCount()
    goToMessageRequestsOutgoingNotice(router)
  } catch (e) {
    chatGateError.value = e.userMessage ?? e.response?.data?.message ?? t('common.error')
  } finally {
    chatGateBusy.value = false
  }
}

async function addAsContact() {
  if (!userId.value) return
  addingContact.value = true
  try {
    await api.post(`/contacts/by-user/${userId.value}`)
    if (profile.value) {
      profile.value = { ...profile.value, isContact: true, IsContact: true }
    }
  } catch {
    addingContact.value = false
  }
  addingContact.value = false
}

onMounted(() => {
  const state = window.history.state || {}
  conversationIdFromState.value = state.conversationId ?? null
  fetchProfile()
})
</script>

<template>
  <div class="user-profile page auth-pattern">
    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('profile.title') }}</span>
      <span class="top-placeholder" aria-hidden="true"></span>
    </header>

    <div class="scroll-area">
      <template v-if="loading">
        <div class="profile-skeleton">
          <div class="skeleton-avatar"></div>
          <div class="skeleton-name"></div>
          <div class="skeleton-code"></div>
        </div>
      </template>

      <template v-else-if="error || !profile">
        <div class="empty-state">
          <p>{{ t('profile.notFound') }}</p>
          <button class="btn-gradient" @click="goBack">{{ t('common.back') }}</button>
        </div>
      </template>

      <template v-else>
        <!-- Hero: صورة + اسم + حالة واحدة -->
        <section class="profile-hero">
          <div
            class="profile-avatar-wrap"
            :class="{ 'profile-avatar-featured': profile.isFeatured ?? profile.IsFeatured }"
          >
            <div
              v-if="(profile.avatar ?? profile.Avatar) && isImageAvatar(profile.avatar ?? profile.Avatar)"
              class="profile-avatar profile-avatar-img"
            >
              <CachedAvatar
                :url="profile.avatar ?? profile.Avatar"
                img-class="avatar-img"
              />
            </div>
            <div
              v-else
              class="profile-avatar profile-avatar-letter"
              :style="{ background: 'var(--primary)' }"
            >
              {{ (profile.name ?? profile.Name)?.[0]?.toUpperCase() || '?' }}
            </div>
            <Crown
              v-if="profile.isFeatured ?? profile.IsFeatured"
              class="profile-crown"
              :size="24"
              fill="currentColor"
              stroke-width="1"
            />
          </div>
          <h1 class="profile-name">{{ profile.name ?? profile.Name ?? '—' }}</h1>
          <p class="profile-subtitle">
            {{ genderLabel[(profile.gender ?? profile.Gender)?.toLowerCase()] ?? (profile.gender ?? profile.Gender) ?? '—' }}
            <span v-if="profile.isOnline ?? profile.IsOnline" class="profile-subtitle-dot" aria-hidden="true">·</span>
            <span v-if="profile.isOnline ?? profile.IsOnline" class="profile-subtitle-online">{{ t('profile.online') }}</span>
            <span v-else class="profile-subtitle-offline">{{ t('profile.offline') }}</span>
          </p>
        </section>

        <!-- كود الاتصال -->
        <section class="profile-block">
          <h2 class="profile-block-title">{{ t('settings.contactCode') }}</h2>
          <div class="profile-code-row glass-card" @click="copyCode">
            <span class="profile-code-value">{{ profile.uniqueCode ?? profile.UniqueCode ?? '—' }}</span>
            <button
              type="button"
              class="profile-code-copy"
              :title="copiedCode ? t('common.copied') : t('common.copy')"
              @click.stop="copyCode"
            >
              <Copy v-if="!copiedCode" :size="18" stroke-width="2" />
              <span v-else class="profile-copied-text">{{ t('common.copiedShort') }}</span>
            </button>
          </div>
        </section>

        <!-- رقم الهاتف -->
        <section class="profile-block">
          <h2 class="profile-block-title">{{ t('profile.phone') }}</h2>
          <div
            v-if="formattedPhone"
            class="profile-code-row glass-card"
            @click="copyPhone"
          >
            <span class="profile-code-value profile-phone-value">{{ formattedPhone }}</span>
            <button
              type="button"
              class="profile-code-copy"
              :title="copiedPhone ? t('common.copied') : t('common.copy')"
              @click.stop="copyPhone"
            >
              <Copy v-if="!copiedPhone" :size="18" stroke-width="2" />
              <span v-else class="profile-copied-text">{{ t('common.copiedShort') }}</span>
            </button>
          </div>
          <div v-else class="profile-code-row glass-card profile-phone-empty">
            <span class="profile-phone-placeholder">{{ t('profile.phoneNotSet') }}</span>
          </div>
        </section>

        <!-- إضافة كجهة اتصال (إذا لم يكن في جهاتك) -->
        <section v-if="!isContact" class="profile-block profile-block-action">
          <button
            class="profile-add-contact-btn"
            :disabled="addingContact"
            @click="addAsContact"
          >
            <UserPlus v-if="!addingContact" :size="20" />
            <span v-else class="profile-btn-dot">...</span>
            <span>{{ addingContact ? t('common.loading') : t('profile.addAsContact') }}</span>
          </button>
        </section>
        <section v-else class="profile-block profile-block-contact-badge">
          <div class="profile-contact-badge">
            <Check :size="18" />
            <span>{{ t('profile.addedToContacts') }}</span>
          </div>
        </section>

        <!-- زر المحادثة -->
        <section class="profile-block profile-block-action">
          <button
            class="profile-chat-btn"
            :disabled="startingChat"
            @click="openChat"
          >
            <MessageCircle :size="20" />
            <span>{{ startingChat ? t('common.loading') : (conversationIdFromState ? t('profile.openChat') : t('profile.startChat')) }}</span>
          </button>
        </section>
      </template>
    </div>

    <div
      v-if="showChatGateModal"
      class="modal-backdrop"
      role="dialog"
      aria-modal="true"
      @click.self="closeChatGateModal"
    >
      <div class="modal-sheet glass-card">
        <p class="modal-text">{{ t('profile.chatGateMessage') }}</p>
        <p v-if="chatGateError" class="modal-error">{{ chatGateError }}</p>
        <p v-if="chatGateSuccess" class="modal-success">{{ chatGateSuccess }}</p>
        <div class="modal-actions">
          <button
            type="button"
            class="modal-btn modal-btn-primary"
            :disabled="chatGateBusy"
            @click="confirmAddAndChat"
          >
            {{ chatGateBusy && !chatGateSuccess ? t('common.loading') : t('profile.chatGateAddAndChat') }}
          </button>
          <button
            type="button"
            class="modal-btn modal-btn-secondary"
            :disabled="chatGateBusy"
            @click="sendMessageRequestOnly"
          >
            {{ t('profile.chatGateSendRequestOnly') }}
          </button>
          <button type="button" class="modal-btn modal-btn-ghost" :disabled="chatGateBusy" @click="closeChatGateModal">
            {{ t('common.cancel') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.user-profile {
  background: var(--bg-primary);
  height: 100%;
  min-height: 100vh;
  min-height: 100dvh;
  overflow: hidden;
  padding-bottom: var(--safe-bottom);
  font-family: 'Cairo', sans-serif;
  display: flex;
  flex-direction: column;
}

.scroll-area {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  padding: 0 20px 32px;
  -webkit-overflow-scrolling: touch;
  max-width: 400px;
  margin: 0 auto;
  width: 100%;
}

.top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 12px;
  flex-shrink: 0;
}

.back-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.top-title {
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
  text-align: center;
}

.top-placeholder {
  width: 40px;
}

/* Skeleton */
.profile-skeleton {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 32px 0;
  gap: 16px;
}

.skeleton-avatar {
  width: 96px;
  height: 96px;
  border-radius: 50%;
  background: var(--bg-elevated);
  animation: skeleton-pulse 1.2s ease-in-out infinite;
}

.skeleton-name {
  width: 140px;
  height: 22px;
  border-radius: 6px;
  background: var(--bg-elevated);
  animation: skeleton-pulse 1.2s ease-in-out infinite;
}

.skeleton-code {
  width: 100%;
  max-width: 280px;
  height: 52px;
  border-radius: 12px;
  background: var(--bg-elevated);
  animation: skeleton-pulse 1.2s ease-in-out infinite;
}

@keyframes skeleton-pulse {
  0%, 100% { opacity: 0.6; }
  50% { opacity: 1; }
}

.empty-state {
  padding: 48px 24px;
  text-align: center;
  color: var(--text-muted);
}

.empty-state p {
  margin-bottom: 20px;
  font-size: 16px;
}

.btn-gradient {
  padding: 14px 28px;
  background: var(--primary);
  border: none;
  border-radius: 14px;
  color: white;
  font-weight: 600;
  font-size: 16px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

/* Hero */
.profile-hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 32px 0 28px;
  gap: 10px;
}

.profile-avatar-wrap {
  position: relative;
}

.profile-avatar {
  width: 96px;
  height: 96px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  color: white;
  font-size: 36px;
  font-weight: 700;
  border: 2px solid var(--bg-elevated);
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.08);
}

.profile-avatar-img .avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.profile-avatar-featured .profile-avatar {
  border-color: rgba(255, 197, 61, 0.5);
}

.profile-crown {
  position: absolute;
  bottom: -2px;
  left: 50%;
  transform: translateX(-50%);
  color: #e5b82e;
  filter: drop-shadow(0 1px 1px rgba(0, 0, 0, 0.2));
}

.profile-name {
  font-size: 22px;
  font-weight: 700;
  color: var(--text-primary);
  margin: 0;
  text-align: center;
  letter-spacing: -0.02em;
  line-height: 1.25;
}

.profile-subtitle {
  margin: 0;
  font-size: 13px;
  color: var(--text-tertiary);
  font-family: 'Cairo', sans-serif;
  text-align: center;
}

.profile-subtitle-dot {
  margin: 0 6px;
  opacity: 0.6;
}

.profile-subtitle-online {
  color: var(--text-secondary);
}

.profile-subtitle-offline {
  color: var(--text-tertiary);
}

/* Block: كود الاتصال */
.profile-block {
  margin-bottom: 24px;
}

.profile-block-title {
  font-size: 11px;
  font-weight: 600;
  color: var(--text-tertiary);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  margin: 0 0 8px 0;
  padding: 0 4px;
}

.profile-code-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 14px 16px;
  border-radius: 12px;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.15s ease;
}

.profile-code-row:active {
  background: var(--bg-elevated);
}

.profile-code-value {
  font-size: 16px;
  font-weight: 600;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  letter-spacing: 0.04em;
}

.profile-code-copy {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border: none;
  border-radius: 10px;
  background: transparent;
  color: var(--text-tertiary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.15s ease, color 0.15s ease;
}

.profile-code-copy:active {
  background: rgba(108, 99, 255, 0.12);
  color: var(--primary);
}

.profile-copied-text {
  font-size: 12px;
  font-weight: 600;
  color: var(--primary);
}

.profile-phone-value {
  letter-spacing: 0.02em;
}

.profile-phone-empty {
  cursor: default;
}

.profile-phone-empty:active {
  background: var(--bg-card);
}

.profile-phone-placeholder {
  font-size: 15px;
  color: var(--text-tertiary);
  font-weight: 500;
}

.profile-block-action {
  margin-bottom: 0;
  margin-top: 8px;
}

.profile-chat-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  width: 100%;
  padding: 15px 20px;
  border: none;
  border-radius: 12px;
  background: var(--primary);
  color: white;
  font-size: 16px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: opacity 0.2s ease, transform 0.06s ease;
  box-shadow: 0 2px 10px rgba(108, 99, 255, 0.25);
}

.profile-chat-btn:active:not(:disabled) {
  transform: scale(0.99);
}

.profile-chat-btn:disabled {
  opacity: 0.75;
  cursor: not-allowed;
}

.profile-add-contact-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  width: 100%;
  padding: 14px 20px;
  border: 1px solid var(--primary);
  border-radius: 12px;
  background: rgba(108, 99, 255, 0.08);
  color: var(--primary);
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.profile-add-contact-btn:active:not(:disabled) {
  background: rgba(108, 99, 255, 0.15);
}

.profile-add-contact-btn:disabled {
  opacity: 0.75;
  cursor: not-allowed;
}

.profile-btn-dot {
  font-size: 14px;
}

.profile-block-contact-badge {
  margin-bottom: 0;
  margin-top: 4px;
}

.profile-contact-badge {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 12px 20px;
  border-radius: 12px;
  background: rgba(34, 197, 94, 0.12);
  color: #16a34a;
  font-size: 14px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
}

.profile-contact-badge svg {
  flex-shrink: 0;
}

.modal-backdrop {
  position: fixed;
  inset: 0;
  z-index: 200;
  background: rgba(0, 0, 0, 0.45);
  display: flex;
  align-items: flex-end;
  justify-content: center;
  padding: 24px;
  padding-bottom: max(24px, var(--safe-bottom));
}

.modal-sheet {
  width: 100%;
  max-width: 400px;
  padding: 20px;
  border-radius: 16px;
  margin-bottom: 8px;
}

.modal-text {
  margin: 0 0 16px;
  font-size: 15px;
  line-height: 1.5;
  color: var(--text-primary);
  text-align: center;
}

.modal-error {
  margin: 0 0 12px;
  font-size: 14px;
  color: var(--danger);
  text-align: center;
}

.modal-success {
  margin: 0 0 12px;
  font-size: 14px;
  color: #16a34a;
  text-align: center;
}

.modal-actions {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.modal-btn {
  width: 100%;
  padding: 14px 16px;
  border-radius: 12px;
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  border: none;
  cursor: pointer;
}

.modal-btn:disabled {
  opacity: 0.7;
  cursor: not-allowed;
}

.modal-btn-primary {
  background: var(--primary);
  color: white;
}

.modal-btn-secondary {
  background: rgba(108, 99, 255, 0.12);
  color: var(--primary);
  border: 1px solid var(--primary);
}

.modal-btn-ghost {
  background: transparent;
  color: var(--text-secondary);
}
</style>
