<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { Search, Forward } from 'lucide-vue-next'
import ModernPageShell from '../components/ui/ModernPageShell.vue'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { notify } from '../utils/notify'
import CachedAvatar from '../components/CachedAvatar.vue'
import { conversationHub, ensureConnected } from '../services/signalr'
import { createPrivateConversationOrRequest, goToMessageRequestsOutgoingNotice } from '../utils/conversationOrMessageRequest'
import { useMessageRequestsStore } from '../stores/messageRequests'

const router = useRouter()
const msgReqStore = useMessageRequestsStore()
const { t } = useI18n()

const shareMessage = ref(null)
const sourceConversationId = ref(null)
const returnPath = ref(null)
const searchQuery = ref('')
const conversations = ref([])
const contacts = ref([])
const loading = ref(true)
const sending = ref(false)

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

const backTo = computed(() => {
  if (returnPath.value) return returnPath.value
  if (sourceConversationId.value) return `/conversation/${sourceConversationId.value}`
  return '/conversations'
})

const filteredConversations = computed(() => {
  const list = conversations.value.filter((c) => String(c.id ?? c.Id) !== String(sourceConversationId.value))
  const q = searchQuery.value.trim()
  if (!q) return list
  const lower = q.toLowerCase()
  return list.filter(
    (c) =>
      (c.partnerName ?? c.PartnerName ?? '').toLowerCase().includes(lower) ||
      (c.partnerPhone ?? c.PartnerPhone ?? '').includes(q) ||
      (c.partnerUniqueCode ?? c.PartnerUniqueCode ?? '').toLowerCase().includes(lower)
  )
})

const filteredContacts = computed(() => {
  const list = contacts.value
  const q = searchQuery.value.trim()
  if (!q) return list
  const lower = q.toLowerCase()
  return list.filter(
    (c) =>
      (c.name ?? '').toLowerCase().includes(lower) ||
      (c.phoneNumber ?? '').includes(q) ||
      (c.uniqueCode ?? '').toLowerCase().includes(lower)
  )
})

const hasConversations = computed(() => filteredConversations.value.length > 0)
const hasContacts = computed(() => filteredContacts.value.length > 0)
const hasAny = computed(() => hasConversations.value || hasContacts.value)

function goBack() {
  router.replace(backTo.value)
}

async function fetchData() {
  loading.value = true
  try {
    const [convRes, contactRes] = await Promise.all([
      api.get('/conversations', { params: { filter: 'all' } }),
      api.get('/contacts').catch(() => ({ data: [] }))
    ])
    conversations.value = convRes.data ?? []
    contacts.value = contactRes.data ?? []
  } catch {
    conversations.value = []
    contacts.value = []
  } finally {
    loading.value = false
  }
}

async function shareToConversation(targetConvId) {
  const msg = shareMessage.value
  if (!msg || !targetConvId || sending.value) return
  sending.value = true
  try {
    await ensureConnected(conversationHub)
    await conversationHub.invoke('SendMessage', targetConvId, msg.content, msg.type || 'text', null)
    router.replace(`/conversation/${targetConvId}`)
  } catch {
    sending.value = false
  }
}

async function shareToContact(contact) {
  const msg = shareMessage.value
  const contactUserId = contact.contactUserId ?? contact.contactUserId
  if (!msg || !contactUserId || sending.value) return
  sending.value = true
  try {
    const r = await createPrivateConversationOrRequest(contactUserId)
    if (r.kind === 'messageRequest') {
      await msgReqStore.fetchPendingCount()
      goToMessageRequestsOutgoingNotice(router, 'share')
      sending.value = false
      return
    }
    const convId = r.conversationId
    if (!convId) throw new Error('No conversation id')
    await ensureConnected(conversationHub)
    await conversationHub.invoke('SendMessage', convId, msg.content, msg.type || 'text', null)
    router.replace(`/conversation/${convId}`)
  } catch (e) {
    notify.error(e.userMessage ?? e.response?.data?.message ?? t('common.error'))
    sending.value = false
  }
}

onMounted(() => {
  const state = window.history.state || {}
  shareMessage.value = state.shareMessage || null
  sourceConversationId.value = state.sourceConversationId || null
  returnPath.value = state.returnPath || null
  if (!shareMessage.value) {
    goBack()
    return
  }
  fetchData()
})
</script>

<template>
  <ModernPageShell :title="t('conversationChat.shareToConversation')" :back-to="backTo">
    <div class="share-search-wrap">
      <Search :size="14" class="share-search-icon" />
      <input
        v-model="searchQuery"
        type="text"
        class="share-search-input"
        :placeholder="t('conversationChat.shareSearchPlaceholder')"
      />
    </div>

    <div v-if="loading" class="loading-msg">{{ t('common.loading') }}</div>
    <div v-else class="share-sections">
      <section v-if="hasConversations" class="modern-section">
        <h2 class="modern-section-title">{{ t('conversations.title') }}</h2>
        <div class="modern-list">
          <button
            v-for="c in filteredConversations"
            :key="c.id ?? c.Id"
            type="button"
            class="modern-list-row share-item"
            :disabled="sending"
            @click="shareToConversation(c.id ?? c.Id)"
          >
            <div
              class="modern-list-row__avatar"
              :style="{
                background:
                  (c.partnerAvatar ?? c.PartnerAvatar) && !isImageAvatar(c.partnerAvatar ?? c.PartnerAvatar)
                    ? 'var(--primary)'
                    : 'var(--bg-elevated)'
              }"
            >
              <CachedAvatar
                v-if="(c.partnerAvatar ?? c.PartnerAvatar) && isImageAvatar(c.partnerAvatar ?? c.PartnerAvatar)"
                :url="c.partnerAvatar ?? c.PartnerAvatar"
                img-class="avatar-img"
              />
              <span v-else>{{ (c.partnerName ?? c.PartnerName)?.[0]?.toUpperCase() || '?' }}</span>
            </div>
            <span class="modern-list-row__title">{{ c.partnerName ?? c.PartnerName ?? '—' }}</span>
            <Forward :size="16" class="share-arrow" />
          </button>
        </div>
      </section>
      <section v-if="hasContacts" class="modern-section">
        <h2 class="modern-section-title">{{ t('contacts.title') }}</h2>
        <div class="modern-list">
          <button
            v-for="c in filteredContacts"
            :key="c.contactUserId ?? c.id"
            type="button"
            class="modern-list-row share-item"
            :disabled="sending"
            @click="shareToContact(c)"
          >
            <div
              class="modern-list-row__avatar"
              :style="{
                background: c.avatar && !isImageAvatar(c.avatar) ? 'var(--primary)' : 'var(--bg-elevated)'
              }"
            >
              <CachedAvatar v-if="c.avatar && isImageAvatar(c.avatar)" :url="c.avatar" img-class="avatar-img" />
              <span v-else>{{ c.name?.[0]?.toUpperCase() || '?' }}</span>
            </div>
            <span class="modern-list-row__title">{{ c.name ?? '—' }}</span>
            <Forward :size="16" class="share-arrow" />
          </button>
        </div>
      </section>
      <p v-if="!loading && !hasAny" class="share-empty">
        {{ searchQuery.trim() ? t('conversationChat.noSearchResults') : t('conversationChat.noOtherConversations') }}
      </p>
    </div>
  </ModernPageShell>
</template>

<style scoped>
.share-search-wrap {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 14px;
  min-height: 44px;
  margin-bottom: 16px;
  border-radius: var(--radius-lg);
  border: 1px solid var(--border);
  background: var(--bg-card);
  box-shadow: var(--shadow-sm);
}

.share-search-icon {
  color: var(--text-tertiary);
  flex-shrink: 0;
}

.share-search-input {
  flex: 1;
  min-width: 0;
  padding: 10px 0;
  border: none;
  background: transparent;
  color: var(--text-primary);
  font-size: 14px;
  font-family: 'Cairo', sans-serif;
  outline: none;
}

.loading-msg {
  text-align: center;
  padding: 32px;
  color: var(--text-muted);
  font-family: 'Cairo', sans-serif;
}

.share-sections {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.modern-section .modern-section-title {
  margin-bottom: 10px;
}

.share-item {
  width: 100%;
  border: none;
  background: none;
  cursor: pointer;
  font: inherit;
  text-align: inherit;
  -webkit-tap-highlight-color: transparent;
}

.share-item:disabled {
  opacity: 0.6;
  cursor: wait;
}

.share-item .modern-list-row__title {
  flex: 1;
  min-width: 0;
  text-align: start;
}

.share-arrow {
  color: var(--text-tertiary);
  flex-shrink: 0;
}

.share-empty {
  text-align: center;
  padding: 24px;
  color: var(--text-muted);
  font-size: 14px;
  font-family: 'Cairo', sans-serif;
}

.avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}
</style>
