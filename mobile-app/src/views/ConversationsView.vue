<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import { useRouter } from 'vue-router'
import { ChevronRight, MessageCircle, Search, Pin, MoreVertical, Users, UsersRound } from 'lucide-vue-next'
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

const router = useRouter()
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
  return d.toLocaleDateString(locale === 'ar' ? 'ar-SA' : 'en-US') + ' ' + d.toLocaleTimeString(locale === 'ar' ? 'ar-SA' : 'en-US', { hour: '2-digit', minute: '2-digit', hour12: true })
}

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

function getUnreadCount(c) {
  const n = c?.unreadCount ?? c?.UnreadCount ?? 0
  return typeof n === 'number' ? n : parseInt(n, 10) || 0
}

watch(filter, fetchConversations, { immediate: true })

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
        <button class="new-chat-btn" @click="goToCreateGroup" :aria-label="t('conversations.newGroup')" :title="t('conversations.newGroup')">
          <UsersRound :size="22" />
        </button>
        <button class="new-chat-btn" @click="goToContacts" :aria-label="t('conversations.newChat')" :title="t('conversations.newChat')">
          <Users :size="22" />
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
        <Search :size="18" class="search-icon" />
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
          <div class="item-avatar" :class="{ 'avatar-group': c.isGroup ?? c.IsGroup }" :style="{ background: (c.partnerAvatar ?? c.PartnerAvatar) && !isImageAvatar(c.partnerAvatar ?? c.PartnerAvatar) ? 'var(--primary)' : 'var(--bg-elevated)' }">
            <CachedAvatar v-if="(c.partnerAvatar ?? c.PartnerAvatar) && isImageAvatar(c.partnerAvatar ?? c.PartnerAvatar)" :url="c.partnerAvatar ?? c.PartnerAvatar" img-class="avatar-img" />
            <Users v-else-if="c.isGroup ?? c.IsGroup" :size="22" class="avatar-group-icon" />
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
                  <Pin :size="12" />
                </span>
                <button
                  v-if="c.partnerId ?? c.PartnerId"
                  class="context-btn"
                  @click.stop="openContextMenu(c, $event)"
                  :aria-label="t('common.cancel')"
                >
                  <MoreVertical :size="18" />
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
  overflow: hidden;
  padding-bottom: var(--safe-bottom);
  font-family: 'Cairo', sans-serif;
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
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  text-align: center;
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
.header-actions { display: flex; gap: 8px; }
.new-chat-btn { color: var(--primary); }

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
  gap: 8px;
  padding: 12px var(--spacing) 8px;
  flex-shrink: 0;
}

.filter-btn {
  flex: 1;
  padding: 10px 12px;
  font-size: 13px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  border-radius: 12px;
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
  padding: 0 var(--spacing) 12px;
  flex-shrink: 0;
}

.search-input-wrap {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 14px;
  min-height: 44px;
  border-radius: 12px;
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
  padding: 12px 0;
  border: none;
  background: transparent;
  color: var(--text-primary);
  font-size: 14px;
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
  gap: 10px;
  padding-bottom: 24px;
}

.conv-item {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 14px 16px;
  cursor: pointer;
  border-radius: 14px;
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
  width: 48px;
  height: 48px;
  min-width: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 18px;
  color: white;
  flex-shrink: 0;
  position: relative;
  overflow: hidden;
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
  gap: 2px;
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
  font-size: 15px;
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
  padding: 2px 8px;
  border-radius: 6px;
  background: rgba(108, 99, 255, 0.15);
  color: var(--primary);
  font-size: 12px;
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
  gap: 8px;
  flex-shrink: 0;
}

.item-time {
  font-size: 12px;
  color: var(--text-muted);
  font-family: 'Cairo', sans-serif;
}

.unread-badge-inline {
  min-width: 22px;
  height: 22px;
  padding: 0 6px;
  background: #25D366;
  color: white;
  font-size: 12px;
  font-weight: 700;
  font-family: 'Cairo', sans-serif;
  border-radius: 11px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.item-preview {
  font-size: 13px;
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
  min-width: var(--touch-min);
  min-height: var(--touch-min);
  padding: 4px;
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
  width: 24px;
  height: 24px;
  border-radius: 6px;
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

@media (max-width: 360px) {
  .conv-item {
    padding: 12px var(--spacing);
    gap: 12px;
  }
  .item-avatar {
    width: 44px;
    height: 44px;
    min-width: 44px;
    font-size: 16px;
  }
  .item-name { font-size: 14px; }
  .item-time { font-size: 12px; }
  .item-preview { font-size: 12px; }
}
</style>
