<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, Search, Forward } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import CachedAvatar from '../components/CachedAvatar.vue'
import { conversationHub, ensureConnected } from '../services/signalr'
import { createPrivateConversationOrRequest, goToMessageRequestsOutgoingNotice } from '../utils/conversationOrMessageRequest'
import { useMessageRequestsStore } from '../stores/messageRequests'

const router = useRouter()
const msgReqStore = useMessageRequestsStore()
const { t } = useI18n()

const shareMessage = ref(null)
const sourceConversationId = ref(null)
const searchQuery = ref('')
const conversations = ref([])
const contacts = ref([])
const loading = ref(true)
const sending = ref(false)

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

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
  if (sourceConversationId.value) router.replace(`/conversation/${sourceConversationId.value}`)
  else router.replace('/conversations')
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
    window.alert(e.userMessage ?? e.response?.data?.message ?? t('common.error'))
    sending.value = false
  }
}

onMounted(() => {
  const state = window.history.state || {}
  shareMessage.value = state.shareMessage || null
  sourceConversationId.value = state.sourceConversationId || null
  if (!shareMessage.value) {
    goBack()
    return
  }
  fetchData()
})
</script>

<template>
  <div class="share-message page auth-pattern">
    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('conversationChat.shareToConversation') }}</span>
    </header>

    <div class="share-search-wrap">
      <Search :size="14" class="share-search-icon" />
      <input
        v-model="searchQuery"
        type="text"
        class="share-search-input"
        :placeholder="t('conversationChat.shareSearchPlaceholder')"
      />
    </div>

    <div class="scroll-area">
      <div v-if="loading" class="loading-msg">{{ t('common.loading') }}</div>
      <div v-else class="share-sections">
        <section v-if="hasConversations" class="share-section">
          <h4 class="share-section-title">{{ t('conversations.title') }}</h4>
          <div class="share-list">
            <button
              v-for="c in filteredConversations"
              :key="c.id ?? c.Id"
              class="share-item"
              :disabled="sending"
              @click="shareToConversation(c.id ?? c.Id)"
            >
              <div
                class="share-avatar"
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
              <span class="share-name">{{ c.partnerName ?? c.PartnerName ?? '—' }}</span>
              <Forward :size="14" class="share-arrow" />
            </button>
          </div>
        </section>
        <section v-if="hasContacts" class="share-section">
          <h4 class="share-section-title">{{ t('contacts.title') }}</h4>
          <div class="share-list">
            <button
              v-for="c in filteredContacts"
              :key="c.contactUserId ?? c.id"
              class="share-item"
              :disabled="sending"
              @click="shareToContact(c)"
            >
              <div
                class="share-avatar"
                :style="{
                  background: c.avatar && !isImageAvatar(c.avatar) ? 'var(--primary)' : 'var(--bg-elevated)'
                }"
              >
                <CachedAvatar v-if="c.avatar && isImageAvatar(c.avatar)" :url="c.avatar" img-class="avatar-img" />
                <span v-else>{{ c.name?.[0]?.toUpperCase() || '?' }}</span>
              </div>
              <span class="share-name">{{ c.name ?? '—' }}</span>
              <Forward :size="14" class="share-arrow" />
            </button>
          </div>
        </section>
        <p v-if="!loading && !hasAny" class="share-empty">
          {{ searchQuery.trim() ? t('conversationChat.noSearchResults') : t('conversationChat.noOtherConversations') }}
        </p>
      </div>
    </div>

    <button class="share-cancel-btn" @click="goBack">{{ t('common.cancel') }}</button>
  </div>
</template>

<style scoped>
.share-message {
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
  padding: 0 var(--spacing);
  -webkit-overflow-scrolling: touch;
}

.top-bar {
  display: flex;
  align-items: center;
  gap: 12px;
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
  flex: 1;
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
  text-align: center;
}

.share-search-wrap {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 0 10px;
  min-height: 36px;
  margin: 0 var(--spacing) 10px;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--bg-card);
  flex-shrink: 0;
}

.share-search-icon {
  color: var(--text-tertiary);
  flex-shrink: 0;
}

.share-search-input {
  flex: 1;
  min-width: 0;
  padding: 7px 0;
  border: none;
  background: transparent;
  color: var(--text-primary);
  font-size: 13px;
  font-family: 'Cairo', sans-serif;
  outline: none;
}

.share-sections {
  flex: 1;
  overflow-y: auto;
  padding: 0 var(--spacing);
}

.share-section {
  margin-bottom: 16px;
}

.share-section-title {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-tertiary);
  margin: 0 0 8px 0;
  padding: 0 4px;
  font-family: 'Cairo', sans-serif;
}

.share-list {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.share-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 10px;
  cursor: pointer;
  text-align: right;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.2s, border-color 0.2s;
  width: 100%;
  font-family: 'Cairo', sans-serif;
}

.share-item:active:not(:disabled) {
  background: var(--bg-card-hover);
  border-color: rgba(108, 99, 255, 0.3);
}

.share-item:disabled {
  opacity: 0.7;
  cursor: not-allowed;
}

.share-avatar {
  width: 36px;
  height: 36px;
  min-width: 36px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 14px;
  color: white;
  overflow: hidden;
}

.share-avatar .avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.share-name {
  flex: 1;
  font-weight: 600;
  font-size: 13px;
  color: var(--text-primary);
  text-align: right;
}

.share-arrow {
  color: var(--primary);
  flex-shrink: 0;
}

.share-empty,
.loading-msg {
  text-align: center;
  color: var(--text-muted);
  font-size: 15px;
  padding: 32px 24px;
  margin: 0;
}

.share-cancel-btn {
  flex-shrink: 0;
  margin: 12px var(--spacing);
  padding: 10px 12px;
  min-height: 40px;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--bg-card);
  color: var(--text-primary);
  font-size: 14px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
</style>
