<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Copy, MessageCircle, Crown, UserPlus, Check, Phone, Hash, ChevronLeft, ChevronRight } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../stores/locale'
import api from '../services/api'
import { notify } from '../utils/notify'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { DEFAULT_COVER_URL } from '../utils/defaultCover'
import {
  createPrivateConversationOrRequest,
  goToMessageRequestsOutgoingNotice,
  validate409AsSuccess
} from '../utils/conversationOrMessageRequest'
import { useMessageRequestsStore } from '../stores/messageRequests'
import { useUserAvatarOverridesStore } from '../stores/userAvatarOverrides'

const msgReqStore = useMessageRequestsStore()
const avatarOverrides = useUserAvatarOverridesStore()

// المسار الافتراضي من الحوار: إضافة كجهة اتصال ثم فتح المحادثة. البديل: طلب مراسلة فقط (يُعرض في صفحة طلبات المراسلة لدى المستقبل).
const route = useRoute()
const router = useRouter()
const { t } = useI18n()
const localeStore = useLocaleStore()

const BackIcon = computed(() => (localeStore.isRtl ? ChevronRight : ChevronLeft))

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

/** صورة فورية عند تحديثها من SignalR (صديقك غيّر صورته). */
const profileAvatarDisplay = computed(() => {
  const p = profile.value
  if (!p) return null
  const id = p.id ?? p.Id
  return avatarOverrides.avatarFor(id) ?? (p.avatar ?? p.Avatar)
})

const avatarImgError = ref(false)
const coverImgError = ref(false)

const profileCoverUrl = computed(() => {
  const p = profile.value
  if (!p) return null
  return p.coverImageUrl ?? p.CoverImageUrl ?? null
})

const coverImageSrc = computed(() => {
  if (coverImgError.value) return DEFAULT_COVER_URL
  const url = profileCoverUrl.value
  if (url && isImageUrl(url)) return ensureAbsoluteUrl(url)
  return DEFAULT_COVER_URL
})

watch(profileCoverUrl, () => {
  coverImgError.value = false
})

watch(profileAvatarDisplay, () => {
  avatarImgError.value = false
})

const showProfileAvatarImage = computed(() =>
  profileAvatarDisplay.value &&
  isImageAvatar(profileAvatarDisplay.value) &&
  !avatarImgError.value
)

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
      notify.error(e.userMessage ?? e.response?.data?.message ?? t('common.error'))
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
  <div class="modern-page page user-profile-page">
    <section class="profile-hero">
      <div class="profile-hero__cover">
        <img
          :src="coverImageSrc"
          class="profile-hero__cover-img"
          alt=""
          referrerpolicy="no-referrer"
          @error="coverImgError = true"
        />
        <div class="profile-hero__cover-fade" aria-hidden="true" />
        <header class="profile-hero__nav">
          <button type="button" class="modern-glass-btn profile-hero__back" :aria-label="t('common.back')" @click="goBack">
            <component :is="BackIcon" :size="22" stroke-width="2" />
          </button>
          <h1 class="profile-hero__title">{{ t('profile.title') }}</h1>
          <span class="modern-page__nav-spacer" aria-hidden="true" />
        </header>
      </div>

      <div v-if="loading" class="profile-hero__content">
        <div class="profile-skeleton">
          <div class="skeleton-avatar skeleton-shimmer" />
          <div class="skeleton-name skeleton-shimmer" />
        </div>
      </div>

      <div v-else-if="error || !profile" class="profile-hero__content profile-hero__content--empty">
        <div class="modern-empty">
          <p>{{ t('profile.notFound') }}</p>
          <button class="btn-gradient" style="max-width: 240px" @click="goBack">{{ t('common.back') }}</button>
        </div>
      </div>

      <div v-else class="profile-hero__content">
        <div
          class="profile-avatar-wrap"
          :class="{ 'profile-avatar-featured': profile.isFeatured ?? profile.IsFeatured }"
        >
          <div class="modern-avatar-xl">
            <img
              v-if="showProfileAvatarImage"
              :src="ensureAbsoluteUrl(profileAvatarDisplay)"
              class="avatar-img"
              alt=""
              referrerpolicy="no-referrer"
              @error="avatarImgError = true"
            />
            <span v-else class="avatar-letter">
              {{ (profile.name ?? profile.Name)?.[0]?.toUpperCase() || '?' }}
            </span>
          </div>
          <Crown
            v-if="profile.isFeatured ?? profile.IsFeatured"
            class="profile-crown"
            :size="22"
            fill="currentColor"
            stroke-width="1"
          />
        </div>

        <h2 class="modern-profile-name">{{ profile.name ?? profile.Name ?? '—' }}</h2>
        <p class="modern-profile-sub">
          {{ genderLabel[(profile.gender ?? profile.Gender)?.toLowerCase()] ?? (profile.gender ?? profile.Gender) ?? '—' }}
          <span v-if="profile.isOnline ?? profile.IsOnline"> · {{ t('profile.online') }}</span>
          <span v-else> · {{ t('profile.offline') }}</span>
        </p>

        <div class="modern-meta-row">
          <span v-if="formattedPhone" class="modern-meta-item">
            <Phone :size="15" stroke-width="2" />
            {{ formattedPhone }}
          </span>
          <span v-if="profile.uniqueCode ?? profile.UniqueCode" class="modern-meta-item">
            <Hash :size="15" stroke-width="2" />
            {{ profile.uniqueCode ?? profile.UniqueCode }}
          </span>
        </div>
      </div>
    </section>

    <div v-if="!loading && profile && !error" class="modern-page__scroll profile-scroll">
      <div class="profile-actions">
        <div class="modern-action-row">
          <button
            class="modern-action-btn modern-action-btn--primary"
            :disabled="startingChat"
            @click="openChat"
          >
            <MessageCircle :size="18" stroke-width="2" />
            <span>{{ startingChat ? t('common.loading') : (conversationIdFromState ? t('profile.openChat') : t('profile.startChat')) }}</span>
          </button>
          <button
            v-if="!isContact"
            class="modern-action-btn modern-action-btn--secondary"
            :disabled="addingContact"
            @click="addAsContact"
          >
            <UserPlus :size="18" stroke-width="2" />
            <span>{{ addingContact ? t('common.loading') : t('profile.addAsContact') }}</span>
          </button>
        </div>

        <div v-if="isContact" class="modern-badge-pill profile-contact-pill">
          <Check :size="16" stroke-width="2.5" />
          <span>{{ t('profile.addedToContacts') }}</span>
        </div>
      </div>

      <section class="modern-section">
        <h3 class="modern-section-title">{{ t('settings.contactCode') }}</h3>
        <div class="modern-info-card" @click="copyCode">
          <span class="modern-info-card__value">{{ profile.uniqueCode ?? profile.UniqueCode ?? '—' }}</span>
          <button type="button" class="modern-info-card__copy" @click.stop="copyCode">
            <Copy v-if="!copiedCode" :size="18" stroke-width="2" />
            <span v-else>{{ t('common.copiedShort') }}</span>
          </button>
        </div>
      </section>

      <section class="modern-section">
        <h3 class="modern-section-title">{{ t('profile.phone') }}</h3>
        <div v-if="formattedPhone" class="modern-info-card" @click="copyPhone">
          <span class="modern-info-card__value">{{ formattedPhone }}</span>
          <button type="button" class="modern-info-card__copy" @click.stop="copyPhone">
            <Copy v-if="!copiedPhone" :size="18" stroke-width="2" />
            <span v-else>{{ t('common.copiedShort') }}</span>
          </button>
        </div>
        <div v-else class="modern-info-card">
          <span class="modern-info-card__value profile-phone-empty">{{ t('profile.phoneNotSet') }}</span>
        </div>
      </section>
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
.user-profile-page {
  overflow: hidden;
}

.profile-hero {
  flex-shrink: 0;
  background: var(--bg-primary);
}

.profile-hero__cover {
  height: 168px;
  position: relative;
  overflow: hidden;
  background: #1e3a8a;
}

.profile-hero__cover-img {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  object-position: center;
  display: block;
}

.profile-hero__cover-fade {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    180deg,
    rgba(15, 23, 42, 0.35) 0%,
    rgba(15, 23, 42, 0.08) 45%,
    var(--bg-primary) 100%
  );
  pointer-events: none;
  z-index: 1;
}

.profile-hero__cover::after {
  content: none;
}

.profile-hero__nav {
  position: relative;
  z-index: 2;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: calc(var(--safe-top) + 8px) var(--spacing) 0;
}

.profile-hero__back {
  background: rgba(15, 23, 42, 0.35);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  color: #fff;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
}

.profile-hero__title {
  flex: 1;
  margin: 0;
  font-size: 18px;
  font-weight: 800;
  color: #fff;
  text-align: center;
  text-shadow: 0 1px 6px rgba(0, 0, 0, 0.2);
}

.profile-hero__content {
  display: flex;
  flex-direction: column;
  align-items: center;
  margin-top: -56px;
  padding: 0 var(--spacing) 8px;
  position: relative;
  z-index: 3;
}

.profile-hero__content--empty {
  margin-top: 0;
  padding-top: 24px;
}

.profile-scroll {
  padding-top: 8px;
}

.profile-actions {
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 100%;
  padding-bottom: 8px;
}

.profile-actions .modern-action-row {
  margin-top: 0;
}

.profile-avatar-wrap {
  position: relative;
}

.profile-avatar-featured .modern-avatar-xl {
  border-color: #e5b82e;
}

.modern-avatar-xl {
  background: var(--primary);
}

.modern-avatar-xl .avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.avatar-letter {
  font-size: 40px;
  font-weight: 700;
  color: #fff;
  line-height: 1;
}

.profile-crown {
  position: absolute;
  bottom: 4px;
  inset-inline-end: -4px;
  color: #e5b82e;
  filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.2));
}

.profile-contact-pill {
  margin-top: 12px;
}

.profile-phone-empty {
  color: var(--text-muted);
  font-weight: 500;
}

.profile-skeleton {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 8px 0 24px;
  gap: 16px;
}

.skeleton-avatar {
  width: 112px;
  height: 112px;
  border-radius: 50%;
}

.skeleton-name {
  width: 160px;
  height: 22px;
  border-radius: 8px;
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
