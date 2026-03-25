<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import { useRouter } from 'vue-router'
import { ChevronRight, MessageCircle, Search, Pin, MoreVertical, Users, UsersRound, Mail } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import CachedAvatar from '../components/CachedAvatar.vue'
import { useLocaleStore } from '../stores/locale'
import { useConversationsListStore } from '../stores/conversationsList'
import { useConversationStore } from '../stores/conversation'
import { useAuthStore } from '../stores/auth'
import { useNetworkStore } from '../stores/network'
import { conversationHub, startHub } from '../services/signalr'
import { loadConversationsListFromCache, saveConversationsList } from '../services/cache'
import { formatGregorianDateTime } from '../utils/formatTime'
import { useMessageRequestsStore } from '../stores/messageRequests'

const router = useRouter()
const msgReqStore = useMessageRequestsStore()
const network = useNetworkStore()
const route = useRoute()
const { t } = useI18n()
const localeStore = useLocaleStore()
const listStore = useConversationsListStore()
const convStore = useConversationStore()
const auth = useAuthStore()

const ready = ref(false)
const conversations = computed(() => listStore.list)
const filter = ref('all')
const searchQuery = ref('')
const needPhone = ref(false)

/** عدد طلبات المراسلة الواردة المعلقة — للشارة بجانب أيقونة البريد */
const pendingMessageRequestsCount = computed(() => msgReqStore.pendingCount)
const messageRequestsBadgeText = computed(() => {
  const n = pendingMessageRequestsCount.value
  if (n <= 0) return ''
  return n > 99 ? '99+' : String(n)
})
const messageRequestsButtonLabel = computed(() => {
  const base = t('conversations.messageRequests')
  const n = pendingMessageRequestsCount.value
  return n > 0 ? `${base} (${n})` : base
})

const filteredList = computed(() => {
  let list = conversations.value
  if (searchQuery.value.trim()) {
    const q = searchQuery.value.trim().toLowerCase()
    list = list.filter(c =>
      (c.partnerName ?? c.PartnerName ?? '').toLowerCase().includes(q) ||
      (c.partnerPhone ?? c.PartnerPhone ?? '').includes(q) ||
      (c.partnerUniqueCode ?? c.PartnerUniqueCode ?? '').toLowerCase().includes(q)
    )
  }
  return list
})

function goToCreateGroup() {
  router.push('/conversations/create-group')
}

async function fetchConversations() {
  const cached = await loadConversationsListFromCache()
  if (cached?.length) listStore.setList(cached)
  ready.value = true

  needPhone.value = false
  if (!network.isOnline) return
  try {
    const { data } = await api.get('/conversations', {
      params: { filter: filter.value, search: searchQuery.value || undefined },
      skipGlobalLoader: true
    })
    const list = data ?? []
    listStore.setList(list)
    await saveConversationsList(list)
  } catch (e) {
    if (e.response?.status === 400 && e.response?.data?.message?.includes('رقم الهاتف')) {
      needPhone.value = true
    }
  }
}

function openContextMenu(conv, e) {
  e?.stopPropagation()
  const id = conv?.id ?? conv?.Id
  if (id) router.push(`/conversations/${id}/options`)
}

function formatTime(ts) {
  if (!ts) return ''
  const d = new Date(ts)
  const now = new Date()
  const diff = now - d
  const locale = localeStore.locale
  if (diff < 60000) return t('connectionHistory.now')
  if (diff < 3600000) return t('connectionHistory.minutesAgo', { n: Math.floor(diff / 60000) })
  if (diff < 86400000) return t('connectionHistory.hoursAgo', { n: Math.floor(diff / 3600000) })
  return formatGregorianDateTime(d, locale)
}

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

function getUnreadCount(c) {
  const n = c?.unreadCount ?? c?.UnreadCount ?? 0
  return typeof n === 'number' ? n : parseInt(n, 10) || 0
}

watch(filter, fetchConversations, { immediate: true })

watch(
  () => route.path,
  (path) => {
    if (path === '/conversations') msgReqStore.fetchPendingCount()
  }
)

watch([() => route.query.open, ready], ([openId, isReady]) => {
  if (!openId || !isReady) return
  nextTick(() => router.replace(`/conversation/${openId}`))
})

async function handleListUpdated(payload) {
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
  if (updated) await saveConversationsList(listStore.list)
  if (!updated) await fetchConversations()
}

onMounted(async () => {
  msgReqStore.fetchPendingCount()
  convStore.clearConversation()
  try {
    await startHub(conversationHub)
    conversationHub.on('ConversationListUpdated', handleListUpdated)
  } catch (_) {}
})

onUnmounted(() => {
  conversationHub.off('ConversationListUpdated', handleListUpdated)
})

function goToConversation(c) {
  const id = c.id ?? c.Id
  if (id) router.push(`/conversation/${id}`)
}

function goToContacts() {
  router.push('/contacts')
}

function goToMessageRequests() {
  router.push('/message-requests')
}

function goBack() {
  router.replace('/home')
}
</script>

<template>
  <div class="conversations page auth-pattern">
    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('conversations.title') }}</span>
      <div class="header-actions">
        <button
          class="new-chat-btn new-chat-btn-badge-wrap"
          @click="goToMessageRequests"
          :aria-label="messageRequestsButtonLabel"
          :title="messageRequestsButtonLabel"
        >
          <Mail :size="18" />
          <span v-if="messageRequestsBadgeText" class="header-btn-badge">{{ messageRequestsBadgeText }}</span>
        </button>
        <button class="new-chat-btn" @click="goToCreateGroup" :aria-label="t('conversations.newGroup')" :title="t('conversations.newGroup')">
          <UsersRound :size="18" />
        </button>
        <button class="new-chat-btn" @click="goToContacts" :aria-label="t('conversations.newChat')" :title="t('conversations.newChat')">
          <Users :size="18" />
        </button>
      </div>
    </header>

    <div v-if="needPhone" class="need-phone-banner">
      <span>{{ t('conversations.needPhone') }}</span>
      <button class="link-btn" @click="router.push('/complete-profile')">{{ t('completeProfile.completeNow') }}</button>
    </div>

    <div class="filters-wrap">
      <button
        v-for="f in ['all', 'unread', 'archived']"
        :key="f"
        class="filter-btn"
        :class="{ active: filter === f }"
        @click="filter = f"
      >
        {{ f === 'all' ? t('conversations.filterAll') : f === 'unread' ? t('conversations.filterUnread') : t('conversations.filterArchived') }}
      </button>
    </div>

    <div class="search-wrap">
      <div class="search-input-wrap">
        <Search :size="16" class="search-icon" />
        <input
          v-model="searchQuery"
          type="text"
          class="search-input"
          :placeholder="t('conversations.searchPlaceholder')"
        />
      </div>
    </div>

    <div class="scroll-area">
      <div v-if="!filteredList.length" class="empty-state">
        <MessageCircle :size="48" class="empty-icon" />
        <p>{{ t('conversations.empty') }}</p>
        <button class="btn-gradient" @click="goToContacts">{{ t('conversations.newChat') }}</button>
      </div>
      <div v-else class="conv-list">
        <div
          v-for="c in filteredList"
          :key="c.id ?? c.Id"
          class="conv-item"
          :class="{ unread: getUnreadCount(c) > 0, 'is-group': c.isGroup ?? c.IsGroup }"
          @click="goToConversation(c)"
          @contextmenu.prevent="openContextMenu(c, $event)"
        >
          <div
            class="item-avatar"
            :class="{
              'avatar-group': c.isGroup ?? c.IsGroup,
              'avatar-elevated-bg': !(c.isGroup ?? c.IsGroup) && !(c.partnerAvatar ?? c.PartnerAvatar)
            }"
            :style="{ background: (c.partnerAvatar ?? c.PartnerAvatar) && !isImageAvatar(c.partnerAvatar ?? c.PartnerAvatar) ? 'var(--primary)' : 'var(--bg-elevated)' }"
          >
            <CachedAvatar v-if="(c.partnerAvatar ?? c.PartnerAvatar) && isImageAvatar(c.partnerAvatar ?? c.PartnerAvatar)" :url="c.partnerAvatar ?? c.PartnerAvatar" img-class="avatar-img" />
            <Users v-else-if="c.isGroup ?? c.IsGroup" :size="16" class="avatar-group-icon" />
            <span v-else>{{ (c.partnerName ?? c.PartnerName)?.[0]?.toUpperCase() || '?' }}</span>
          </div>
          <div class="item-content">
            <div class="item-row item-row-name">
              <span class="item-name">{{ c.partnerName ?? c.PartnerName ?? '—' }}</span>
              <span class="item-meta-row">
                <span v-if="c.isGroup ?? c.IsGroup" class="group-badge">{{ t('groups.groupLabel') }}</span>
                <span v-if="getUnreadCount(c) > 0" class="unread-badge-inline">{{ getUnreadCount(c) > 99 ? '99+' : getUnreadCount(c) }}</span>
                <span class="item-time">{{ formatTime(c.lastMessageAt ?? c.LastMessageAt) }}</span>
              </span>
            </div>
            <div class="item-row">
              <span class="item-preview">{{ (c.lastMessagePreview ?? c.LastMessagePreview) || '—' }}</span>
              <span class="item-actions">
                <span v-if="c.isPinned ?? c.IsPinned" class="pin-badge" :title="t('conversations.pin')">
                  <Pin :size="10" />
                </span>
                <button
                  v-if="c.partnerId ?? c.PartnerId"
                  class="context-btn"
                  @click.stop="openContextMenu(c, $event)"
                  :aria-label="t('common.cancel')"
                >
                  <MoreVertical :size="15" />
                </button>
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

  </div>
</template>

<style scoped>
.conversations {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  min-width: 0;
  width: 100%;
  max-width: 100%;
  overflow: hidden;
  padding-bottom: var(--safe-bottom);
  font-family: 'Cairo', sans-serif;
  box-sizing: border-box;
}

.top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 12px;
  flex-shrink: 0;
  gap: 12px;
}

.top-title {
  flex: 1;
  min-width: 0;
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  text-align: center;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.back-btn, .new-chat-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  min-width: 40px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.back-btn:active, .new-chat-btn:active { background: var(--bg-card-hover); }
.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}
.new-chat-btn { color: var(--primary); }
.new-chat-btn-badge-wrap {
  position: relative;
}
.header-btn-badge {
  position: absolute;
  top: -5px;
  inset-inline-end: -5px;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  box-sizing: border-box;
  font-size: 10px;
  font-weight: 700;
  line-height: 1;
  text-align: center;
  color: white;
  background: #f97316;
  border-radius: 9px;
  font-family: 'Cairo', sans-serif;
  font-variant-numeric: tabular-nums;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.08);
  pointer-events: none;
}

.need-phone-banner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding: 12px var(--spacing);
  background: rgba(255, 193, 7, 0.15);
  font-size: 14px;
  font-family: 'Cairo', sans-serif;
  color: var(--text-primary);
}

.link-btn {
  background: none;
  border: none;
  color: var(--primary);
  text-decoration: underline;
  cursor: pointer;
  font-family: 'Cairo', sans-serif;
}

.filters-wrap {
  display: flex;
  gap: 6px;
  padding: 8px var(--spacing) 6px;
  flex-shrink: 0;
}

.filter-btn {
  flex: 1;
  min-height: 34px;
  padding: 6px 8px;
  font-size: 12px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--bg-card);
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.filter-btn.active {
  background: rgba(108, 99, 255, 0.15);
  border-color: rgba(108, 99, 255, 0.4);
  color: var(--primary);
}

.search-wrap {
  padding: 0 var(--spacing) 8px;
  flex-shrink: 0;
}

.search-input-wrap {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 10px;
  min-height: 36px;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--bg-card);
}

.search-icon {
  color: var(--text-tertiary);
  flex-shrink: 0;
}

.search-input {
  flex: 1;
  min-width: 0;
  padding: 8px 0;
  border: none;
  background: transparent;
  color: var(--text-primary);
  font-size: 13px;
  font-family: 'Cairo', sans-serif;
  outline: none;
}

.search-input::placeholder {
  color: var(--text-muted);
}

.scroll-area {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  padding: 0 var(--spacing);
  -webkit-overflow-scrolling: touch;
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 48px 24px;
  color: var(--text-muted);
  text-align: center;
  font-family: 'Cairo', sans-serif;
}

.empty-state p {
  font-size: 15px;
  margin-bottom: 8px;
}

.empty-icon {
  opacity: 0.4;
  margin-bottom: 16px;
}

.conv-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding-bottom: 20px;
}

.conv-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  cursor: pointer;
  border-radius: 10px;
  position: relative;
  border: 1px solid var(--border);
  background: var(--bg-card);
  -webkit-tap-highlight-color: transparent;
}

.conv-item:active { background: var(--bg-card-hover); }

.conv-item.is-group {
  border-inline-start: 3px solid var(--primary);
  background: rgba(108, 99, 255, 0.06);
}

.conv-item.is-group:active {
  background: rgba(108, 99, 255, 0.1);
}

.conv-item.unread .item-name { font-weight: 700; }

.item-avatar {
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
  flex-shrink: 0;
  position: relative;
  overflow: hidden;
}

/* حرف الاسم على خلفية فاتحة: في المود الفاتح لا يستخدم أبيض */
[data-theme="light"] .item-avatar.avatar-elevated-bg,
html.light .item-avatar.avatar-elevated-bg {
  color: var(--primary);
}

.avatar-img {
  width: 100%;
  height: 100%;
  border-radius: 50%;
  object-fit: cover;
}

.item-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.item-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.item-row-name {
  min-width: 0;
}
.item-name {
  font-weight: 600;
  font-size: 13px;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  flex: 1;
  min-width: 0;
}

.group-badge {
  display: inline-flex;
  align-items: center;
  padding: 0 5px;
  border-radius: 4px;
  background: rgba(108, 99, 255, 0.15);
  color: var(--primary);
  font-size: 10px;
  font-weight: 700;
  flex-shrink: 0;
  font-family: 'Cairo', sans-serif;
}

.item-avatar.avatar-group {
  background: rgba(108, 99, 255, 0.2) !important;
}

.avatar-group-icon {
  color: var(--primary);
  flex-shrink: 0;
}

.item-meta-row {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.item-time {
  font-size: 10px;
  color: var(--text-muted);
  font-family: 'Cairo', sans-serif;
}

.unread-badge-inline {
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  background: #25D366;
  color: white;
  font-size: 10px;
  font-weight: 700;
  font-family: 'Cairo', sans-serif;
  border-radius: 8px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.item-preview {
  font-size: 11px;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  flex: 1;
  min-width: 0;
  font-family: 'Cairo', sans-serif;
}

.context-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 32px;
  min-height: 32px;
  padding: 2px;
  background: none;
  border: none;
  color: var(--text-tertiary);
  cursor: pointer;
  flex-shrink: 0;
  -webkit-tap-highlight-color: transparent;
}

.item-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.pin-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  border-radius: 4px;
  background: rgba(108, 99, 255, 0.15);
  color: var(--primary);
  flex-shrink: 0;
}

.btn-gradient {
  padding: 12px 24px;
  background: var(--primary);
  border: none;
  border-radius: 12px;
  color: white;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  margin-top: 16px;
}

/* شريط العنوان: شاشات ضيقة (مثلاً ~240–360px) */
@media (max-width: 420px) {
  .top-bar {
    padding: calc(var(--safe-top) + 8px) 8px 8px;
    gap: 6px;
  }
  .top-title {
    font-size: 15px;
  }
  .header-actions {
    gap: 4px;
  }
  .top-bar .back-btn,
  .top-bar .new-chat-btn {
    width: 32px !important;
    height: 32px !important;
    min-width: 32px !important;
    min-height: 32px !important;
    border-radius: 8px;
  }
  .top-bar .back-btn :deep(svg),
  .top-bar .new-chat-btn :deep(svg) {
    width: 16px !important;
    height: 16px !important;
  }
  .header-btn-badge {
    min-width: 16px;
    height: 16px;
    font-size: 9px;
    padding: 0 4px;
    top: -4px;
    inset-inline-end: -4px;
  }
}

@media (max-width: 320px) {
  .top-bar {
    padding: calc(var(--safe-top) + 6px) 6px 6px;
    gap: 4px;
  }
  .top-title {
    font-size: 14px;
  }
  .header-actions {
    gap: 2px;
  }
  .top-bar .back-btn,
  .top-bar .new-chat-btn {
    width: 30px !important;
    height: 30px !important;
    min-width: 30px !important;
    min-height: 30px !important;
  }
  .top-bar .back-btn :deep(svg),
  .top-bar .new-chat-btn :deep(svg) {
    width: 15px !important;
    height: 15px !important;
  }
}

@media (max-width: 360px) {
  .filters-wrap {
    padding: 6px var(--spacing) 4px;
    gap: 4px;
  }
  .filter-btn {
    min-height: 32px;
    padding: 5px 6px;
    font-size: 11px;
    border-radius: 8px;
  }
  .search-wrap {
    padding-bottom: 6px;
  }
  .search-input-wrap {
    min-height: 34px;
    padding: 0 8px;
    border-radius: 8px;
  }
  .search-input {
    font-size: 12px;
    padding: 6px 0;
  }
  .conv-item {
    padding: 7px 8px;
    gap: 7px;
  }
  .item-avatar {
    width: 34px;
    height: 34px;
    min-width: 34px;
    font-size: 13px;
  }
  .item-name { font-size: 12px; }
  .item-time { font-size: 9px; }
  .item-preview { font-size: 10px; }
}
</style>
