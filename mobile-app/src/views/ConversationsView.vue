<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import { useRouter } from 'vue-router'
import { ChevronRight, MessageCircle, Search, Pin, MoreVertical, Users, UsersRound, Mail, CheckCheck } from 'lucide-vue-next'
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
const markingAllRead = ref(false)

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
const totalUnread = computed(() =>
  conversations.value.reduce((sum, c) => sum + getUnreadCount(c), 0)
)

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

async function markAllRead() {
  if (markingAllRead.value || totalUnread.value <= 0) return
  markingAllRead.value = true
  try {
    await api.put('/conversations/read-all')
    await fetchConversations()
  } finally {
    markingAllRead.value = false
  }
}
</script>

<template>
  <div class="conversations page auth-pattern conversations--wa">
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
        class="mark-all-read-btn"
        :disabled="markingAllRead || totalUnread <= 0"
        :title="t('conversations.markAllRead')"
        @click="markAllRead"
      >
        <CheckCheck :size="15" />
        <span>{{ t('conversations.markAllRead') }}</span>
      </button>
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
              'avatar-elevated-bg': !(c.isGroup ?? c.IsGroup) && !(c.partnerAvatar ?? c.PartnerAvatar),
              'avatar-no-photo': !(c.isGroup ?? c.IsGroup) && !(
                (c.partnerAvatar ?? c.PartnerAvatar) && isImageAvatar(c.partnerAvatar ?? c.PartnerAvatar)
              )
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
/* مظهر القائمة بصفوف وفواصل (كواتساب) مع ألوان NexChat — دون أخضر */
.conversations.conversations--wa {
  --wa-header: var(--bg-secondary);
  --wa-header-text: var(--text-primary);
  --wa-icon-on-header: var(--text-secondary);
  --wa-subbar: var(--bg-primary);
  --wa-search-field: var(--bg-card);
  --wa-search-icon: var(--text-muted);
  --wa-list-bg: var(--bg-primary);
  --wa-row-sep: var(--border);
  --wa-tap: rgba(255, 255, 255, 0.05);
  --wa-accent: var(--primary);
  --wa-filter-active: var(--primary);
  --wa-name: var(--text-primary);
  --wa-preview: var(--text-secondary);
}

html.light .conversations.conversations--wa,
[data-theme="light"] .conversations.conversations--wa {
  --wa-header: var(--bg-card);
  --wa-header-text: var(--text-primary);
  --wa-icon-on-header: var(--text-secondary);
  --wa-subbar: #fff;
  --wa-search-field: var(--bg-card);
  --wa-search-icon: var(--text-muted);
  --wa-list-bg: var(--bg-primary);
  --wa-row-sep: var(--border);
  --wa-tap: rgba(0, 0, 0, 0.04);
  --wa-filter-active: var(--primary);
  --wa-name: var(--text-primary);
  --wa-preview: var(--text-secondary);
}

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

.conversations--wa {
  background: var(--wa-list-bg);
}
.conversations--wa.page.auth-pattern::before {
  opacity: 0.06;
}

.top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 8px) 10px 10px;
  flex-shrink: 0;
  gap: 10px;
  background: var(--wa-header);
  color: var(--wa-header-text);
  border-bottom: 1px solid var(--border);
  box-shadow: none;
}
html.light .conversations--wa .top-bar,
[data-theme="light"] .conversations--wa .top-bar {
  box-shadow: none;
}

.top-title {
  flex: 1;
  min-width: 0;
  font-size: 19px;
  font-weight: 600;
  color: var(--wa-header-text);
  font-family: 'Cairo', sans-serif;
  text-align: center;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  letter-spacing: 0.02em;
}

.back-btn,
.new-chat-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  min-width: 40px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 999px;
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.15s;
}
.conversations--wa .new-chat-btn {
  color: var(--primary);
}
html.light .conversations--wa .back-btn,
html.light .conversations--wa .new-chat-btn,
[data-theme="light"] .conversations--wa .back-btn,
[data-theme="light"] .conversations--wa .new-chat-btn {
  background: var(--bg-secondary);
  border: 1px solid var(--border);
}
html.light .conversations--wa .back-btn,
[data-theme="light"] .conversations--wa .back-btn {
  color: var(--text-secondary);
}
html.light .conversations--wa .new-chat-btn,
[data-theme="light"] .conversations--wa .new-chat-btn {
  color: var(--primary);
}
.back-btn:active,
.new-chat-btn:active {
  background: var(--bg-card-hover);
}
html.light .conversations--wa .back-btn:active,
html.light .conversations--wa .new-chat-btn:active,
[data-theme="light"] .conversations--wa .back-btn:active,
[data-theme="light"] .conversations--wa .new-chat-btn:active {
  background: var(--bg-card-hover);
}
.header-actions {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-shrink: 0;
}
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
  position: relative;
  z-index: 2;
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
  padding: 8px 12px 6px;
  flex-shrink: 0;
  background: var(--wa-subbar);
}
.mark-all-read-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 32px;
  padding: 6px 10px;
  border-radius: 999px;
  border: 1px solid rgba(108, 99, 255, 0.35);
  background: rgba(108, 99, 255, 0.1);
  color: var(--primary);
  font-size: 12px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  flex-shrink: 0;
}
.mark-all-read-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
html.light .conversations--wa .filters-wrap,
[data-theme="light"] .conversations--wa .filters-wrap {
  background: #fff;
  border-bottom: 1px solid var(--wa-row-sep);
}

.filter-btn {
  flex: 1;
  min-height: 32px;
  padding: 6px 10px;
  font-size: 12px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  border-radius: 999px;
  border: none;
  background: var(--bg-card);
  color: var(--wa-icon-on-header, var(--text-secondary));
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.15s, color 0.15s;
}
html.light .conversations--wa .filter-btn,
[data-theme="light"] .conversations--wa .filter-btn {
  background: var(--bg-secondary);
  color: var(--text-secondary);
}

.filter-btn.active {
  background: rgba(108, 99, 255, 0.22);
  color: var(--wa-filter-active);
  box-shadow: 0 0 0 1px rgba(108, 99, 255, 0.4);
}
html.light .conversations--wa .filter-btn.active,
[data-theme="light"] .conversations--wa .filter-btn.active {
  background: rgba(108, 99, 255, 0.12);
  color: var(--wa-filter-active);
  box-shadow: none;
}

.conversations--wa .search-wrap {
  padding: 8px 10px 10px;
  flex-shrink: 0;
  background: var(--wa-subbar);
}
html.light .conversations--wa .search-wrap,
[data-theme="light"] .conversations--wa .search-wrap {
  background: var(--bg-secondary);
}

.search-input-wrap {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 14px;
  min-height: 40px;
  border-radius: 20px;
  border: none;
  background: var(--wa-search-field);
  box-shadow: 0 1px 0 rgba(0, 0, 0, 0.12);
}
html.light .conversations--wa .search-input-wrap,
[data-theme="light"] .conversations--wa .search-input-wrap {
  box-shadow: 0 1px 1px rgba(0, 0, 0, 0.06);
}

.search-icon {
  color: var(--wa-search-icon, var(--text-muted));
  flex-shrink: 0;
}

.search-input {
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
.conversations--wa .search-input {
  color: var(--wa-header-text, var(--text-primary));
}
html.light .conversations--wa .search-input,
[data-theme="light"] .conversations--wa .search-input {
  color: var(--text-primary);
}

.search-input::placeholder {
  color: var(--text-muted);
}
.conversations--wa .search-input::placeholder {
  color: var(--wa-search-icon);
  opacity: 0.9;
}
html.light .conversations--wa .search-input::placeholder,
[data-theme="light"] .conversations--wa .search-input::placeholder {
  color: var(--text-muted);
}

.scroll-area {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  padding: 0;
  background: var(--wa-list-bg, var(--bg-primary));
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
  gap: 0;
  padding-bottom: 12px;
}

.conv-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px 10px 10px;
  min-height: 64px;
  cursor: pointer;
  border-radius: 0;
  position: relative;
  border: none;
  background: transparent;
  border-bottom: 1px solid var(--wa-row-sep, var(--border));
  -webkit-tap-highlight-color: transparent;
}
.conv-item:last-child {
  border-bottom: none;
}
.conversations--wa .conv-item:active {
  background: var(--wa-tap, var(--bg-card-hover));
}

.conversations--wa .conv-item.is-group {
  border-inline-start: 3px solid var(--wa-accent, var(--primary));
  background: transparent;
  padding-inline-start: 7px;
}
.conversations--wa .conv-item.is-group:active {
  background: var(--wa-tap);
}

.conv-item.unread .item-name { font-weight: 700; }

.conversations--wa .conv-item.unread .item-preview {
  color: var(--text-secondary);
  font-weight: 500;
}
html.light .conversations--wa .conv-item.unread .item-preview,
[data-theme="light"] .conversations--wa .conv-item.unread .item-preview {
  color: var(--text-primary);
  font-weight: 500;
}

.item-avatar {
  width: 50px;
  height: 50px;
  min-width: 50px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 16px;
  color: white;
  flex-shrink: 0;
  position: relative;
  overflow: hidden;
}
.conversations--wa .item-avatar {
  width: 52px;
  height: 52px;
  min-width: 52px;
  font-size: 18px;
}

/* دون صورة: إطار ناعم حول الدائرة (box-shadow حتى لا يتغيّر حجم 52px) */
.item-avatar.avatar-no-photo {
  box-shadow:
    0 0 0 1px var(--border),
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.06);
}
html.light .item-avatar.avatar-no-photo,
[data-theme="light"] .item-avatar.avatar-no-photo {
  box-shadow: 0 0 0 1px var(--border);
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
  font-size: 16px;
  line-height: 1.2;
  color: var(--wa-name, var(--text-primary));
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
.conversations--wa .group-badge {
  background: rgba(108, 99, 255, 0.15);
  color: var(--primary);
  font-size: 9px;
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
  font-size: 11px;
  color: var(--wa-preview, var(--text-muted));
  font-family: 'Cairo', sans-serif;
  font-variant-numeric: tabular-nums;
  opacity: 0.9;
}

.unread-badge-inline {
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  background: var(--primary);
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
  font-size: 13px;
  line-height: 1.35;
  color: var(--wa-preview, var(--text-secondary));
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
  color: var(--text-tertiary, var(--text-muted));
  cursor: pointer;
  flex-shrink: 0;
  -webkit-tap-highlight-color: transparent;
}
.conversations--wa .context-btn {
  color: var(--text-muted);
  opacity: 0.9;
}
html.light .conversations--wa .context-btn,
[data-theme="light"] .conversations--wa .context-btn {
  color: var(--text-muted);
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
.conversations--wa .pin-badge {
  background: rgba(108, 99, 255, 0.15);
  color: var(--primary);
  border-radius: 50%;
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
  /* وضع واتساب: لا نصغّر الصور إلى 34px — نبقى أقرب لتجربة WA */
  .conversations--wa .conv-item {
    padding: 9px 10px 9px 8px;
    gap: 8px;
  }
  .conversations--wa .item-avatar {
    width: 48px;
    height: 48px;
    min-width: 48px;
    font-size: 16px;
  }
  .conversations--wa .item-name { font-size: 14px; }
  .conversations--wa .item-time { font-size: 10px; }
  .conversations--wa .item-preview { font-size: 12px; }
}
</style>
