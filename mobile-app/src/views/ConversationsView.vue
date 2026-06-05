<script setup>
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'

const props = defineProps({
  paneMode: { type: Boolean, default: false }
})
import { useRoute, useRouter } from 'vue-router'
import EmptyState from '../components/ui/EmptyState.vue'
import ListSkeleton from '../components/ui/ListSkeleton.vue'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import CachedAvatar from '../components/CachedAvatar.vue'
import { useLocaleStore } from '../stores/locale'
import { useConversationsListStore } from '../stores/conversationsList'
import { useConversationStore } from '../stores/conversation'
import { useAuthStore } from '../stores/auth'
import { useNetworkStore } from '../stores/network'
import { useNotificationsStore } from '../stores/notifications'
import { conversationHub, startHub } from '../services/signalr'
import { loadConversationsListFromCache, saveConversationsList } from '../services/cache'
import { formatGregorianDateTime } from '../utils/formatTime'
import { useMessageRequestsStore } from '../stores/messageRequests'
import StoriesStrip from '../components/StoriesStrip.vue'
import ContactsPanel from '../components/ContactsPanel.vue'
import MessageRequestsPanel from '../components/MessageRequestsPanel.vue'
import { getStoriesEnabled } from '../services/siteContentFlags'
import { useStoriesStore } from '../stores/stories'
import { formatConversationListPreview } from '../utils/shortFilmShare'
import {
  MessageCircle, MessageSquarePlus, Search, Pin, MoreVertical, Users, UsersRound,
  CheckCheck, X, Bell, Check, UserPlus, Mail
} from 'lucide-vue-next'
import { usePullToRefresh } from '../composables/usePullToRefresh'

const router = useRouter()
const msgReqStore = useMessageRequestsStore()
const notificationsStore = useNotificationsStore()
const network = useNetworkStore()
const route = useRoute()
const { t } = useI18n()
const localeStore = useLocaleStore()
const listStore = useConversationsListStore()
const convStore = useConversationStore()
const auth = useAuthStore()
const storiesStore = useStoriesStore()

const ready = ref(false)
const listLoading = ref(true)
const conversations = computed(() => listStore.list)
const filter = ref('all')
const searchQuery = ref('')
const needPhone = ref(false)
const markingAllRead = ref(false)
const storiesEnabled = ref(true)
const fabOpen = ref(false)
const scrollAreaRef = ref(null)
const contactsPanelRef = ref(null)

const mainSection = computed(() => {
  const tab = route.query.tab
  if (tab === 'contacts') return 'contacts'
  if (tab === 'requests') return 'requests'
  return 'chats'
})

const activeConversationId = computed(() => {
  if (!route.path.startsWith('/conversation/')) return null
  return String(route.params.conversationId ?? '')
})

function setMainSection(section) {
  router.replace({
    path: '/conversations',
    query: section === 'chats' ? {} : { tab: section }
  })
}

function openAddContact() {
  contactsPanelRef.value?.openAddModal()
}

/** عدد طلبات المراسلة الواردة المعلقة — للشارة بجانب أيقونة البريد */
const pendingMessageRequestsCount = computed(() => msgReqStore.pendingCount)
const messageRequestsBadgeText = computed(() => {
  const n = pendingMessageRequestsCount.value
  if (n <= 0) return ''
  return n > 99 ? '99+' : String(n)
})
const messageRequestsTabLabel = computed(() => t('conversations.messageRequestsShort'))
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

const pinnedConversations = computed(() =>
  filteredList.value.filter(c => c.isPinned ?? c.IsPinned)
)

const unpinnedConversations = computed(() =>
  filteredList.value.filter(c => !(c.isPinned ?? c.IsPinned))
)

const listWithSections = computed(() => {
  const rows = []
  const pinned = pinnedConversations.value
  const rest = unpinnedConversations.value
  const showPinned = pinned.length > 0 && filter.value !== 'archived'

  if (showPinned) {
    rows.push({ type: 'header', key: 'hdr-pinned', title: t('conversations.pinnedChats'), icon: 'pin' })
    pinned.forEach(c => rows.push({ type: 'conv', key: `p-${c.id ?? c.Id}`, data: c }))
  }

  const allItems = showPinned ? rest : filteredList.value
  if (allItems.length || !filteredList.value.length) {
    rows.push({ type: 'header', key: 'hdr-all', title: t('conversations.allChats'), icon: 'chat' })
    allItems.forEach(c => rows.push({ type: 'conv', key: `a-${c.id ?? c.Id}`, data: c }))
  }
  return rows
})

const headerNotifCount = computed(() => notificationsStore.unreadCount || 0)

function goToCreateGroup() {
  router.push('/conversations/create-group')
}

async function fetchConversations(opts = {}) {
  const background = opts.background === true
  if (!background) listLoading.value = true

  const cached = await loadConversationsListFromCache()
  if (cached?.length && !background) {
    listStore.setList(normalizeConversationsList(cached))
  }

  needPhone.value = false
  if (!network.isOnline) {
    ready.value = true
    if (!background) listLoading.value = false
    return
  }
  try {
    const { data } = await api.get('/conversations', {
      params: { filter: filter.value, search: searchQuery.value || undefined },
      skipGlobalLoader: true
    })
    const list = normalizeConversationsList(data ?? [])
    listStore.setList(list)
    await saveConversationsList(list)
  } catch (e) {
    if (e.response?.status === 400 && e.response?.data?.message?.includes('رقم الهاتف')) {
      needPhone.value = true
    }
  } finally {
    ready.value = true
    if (!background) listLoading.value = false
  }
}

const { pullDistance, refreshing, bind: bindPullRefresh } = usePullToRefresh(() =>
  fetchConversations({ background: true })
)

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

function listPreviewOpts(conv) {
  const type = conv?.lastMessageType ?? conv?.LastMessageType ?? ''
  return { t, type, lastMessageType: type }
}

function normalizeListPreview(conv) {
  const raw = conv?.lastMessagePreview ?? conv?.LastMessagePreview ?? ''
  const formatted = formatConversationListPreview(raw, t('shortFilms.title'), listPreviewOpts(conv))
  if (formatted === raw && !(conv?.lastMessageType ?? conv?.LastMessageType)) return conv
  return {
    ...conv,
    lastMessagePreview: formatted,
    LastMessagePreview: formatted,
    lastMessageType: conv?.lastMessageType ?? conv?.LastMessageType,
    LastMessageType: conv?.lastMessageType ?? conv?.LastMessageType
  }
}

function normalizeConversationsList(list) {
  return (list ?? []).map(normalizeListPreview)
}

function getListPreview(conv) {
  const raw = conv?.lastMessagePreview ?? conv?.LastMessagePreview ?? ''
  const type = conv?.lastMessageType ?? conv?.LastMessageType ?? ''
  const formatted = formatConversationListPreview(raw, t('shortFilms.title'), { t, type, lastMessageType: type })
  if (formatted) return formatted
  if (type === 'video') return t('conversationChat.videoMessage')
  if (type === 'album') return t('conversationChat.albumMessage')
  if (type === 'image') return t('conversationChat.replyPreviewImage')
  if (type === 'audio') return t('conversationChat.voiceMessage')
  return '—'
}

watch(filter, fetchConversations, { immediate: true })

watch(
  () => route.path,
  (path) => {
    if (path === '/conversations') msgReqStore.fetchPendingCount()
  }
)

watch(mainSection, (section) => {
  if (section !== 'requests' && route.query.notice) {
    router.replace({
      path: '/conversations',
      query: section === 'chats' ? {} : { tab: section }
    })
  }
})

watch([() => route.query.open, ready], ([openId, isReady]) => {
  if (!openId || !isReady) return
  nextTick(() => router.replace(`/conversation/${openId}`))
})

async function handleListUpdated(payload) {
  const convId = payload?.conversationId ?? payload?.ConversationId
  if (!convId) return
  const rawPreview = payload?.lastMessagePreview ?? payload?.LastMessagePreview ?? ''
  const msgType = payload?.lastMessageType ?? payload?.LastMessageType ?? ''
  const preview = formatConversationListPreview(rawPreview, t('shortFilms.title'), { t, type: msgType, lastMessageType: msgType })
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
    LastMessageAt: at,
    lastMessageType: msgType,
    LastMessageType: msgType
  }, shouldIncrementUnread)
  if (updated) await saveConversationsList(listStore.list)
  if (!updated) await fetchConversations({ background: true })
}

onMounted(async () => {
  notificationsStore.load()
  const storiesOk = await getStoriesEnabled(api)
  storiesEnabled.value = storiesOk
  if (storiesOk) void storiesStore.fetchFeed()
  msgReqStore.fetchPendingCount()
  convStore.clearConversation()
  try {
    await startHub(conversationHub)
    conversationHub.on('ConversationListUpdated', handleListUpdated)
  } catch (_) {}
  if (scrollAreaRef.value) bindPullRefresh(scrollAreaRef.value)
})

onUnmounted(() => {
  conversationHub.off('ConversationListUpdated', handleListUpdated)
})

function goToConversation(c) {
  const id = c.id ?? c.Id
  if (id) router.push(`/conversation/${id}`)
}

function goToContacts() {
  fabOpen.value = false
  setMainSection('contacts')
}

function toggleFabMenu() {
  fabOpen.value = !fabOpen.value
}

function goToCreateGroupFromFab() {
  fabOpen.value = false
  goToCreateGroup()
}

async function markAllRead() {
  if (markingAllRead.value || totalUnread.value <= 0) return
  markingAllRead.value = true
  try {
    await api.put('/conversations/read-all')
    await fetchConversations({ background: true })
  } finally {
    markingAllRead.value = false
  }
}
</script>

<template>
  <div
    class="conversations conversations--chatloop"
    :class="{ 'conversations--pane': props.paneMode, page: !props.paneMode }"
  >
    <header class="conv-header">
      <h1 class="conv-header__title">{{ t('conversations.title') }}</h1>
      <div class="conv-header__actions">
        <button
          v-if="mainSection === 'contacts'"
          type="button"
          class="conv-header__action-btn"
          :aria-label="t('contacts.addContact')"
          @click="openAddContact"
        >
          <UserPlus :size="20" stroke-width="2" />
        </button>
        <RouterLink to="/notifications" class="conv-header__bell" :aria-label="t('settings.notifications')">
          <Bell :size="20" stroke-width="2" />
          <span v-if="headerNotifCount > 0" class="conv-header__bell-dot" />
        </RouterLink>
      </div>
    </header>

    <div class="conv-main-tabs" :dir="localeStore.htmlDir" role="tablist" :aria-label="t('conversations.title')">
      <button
        type="button"
        class="conv-main-tab"
        :class="{ 'conv-main-tab--active': mainSection === 'chats' }"
        role="tab"
        :aria-selected="mainSection === 'chats'"
        @click="setMainSection('chats')"
      >
        <MessageCircle :size="18" stroke-width="2" />
        <span>{{ t('nav.conversations') }}</span>
      </button>
      <button
        type="button"
        class="conv-main-tab"
        :class="{ 'conv-main-tab--active': mainSection === 'contacts' }"
        role="tab"
        :aria-selected="mainSection === 'contacts'"
        @click="setMainSection('contacts')"
      >
        <Users :size="18" stroke-width="2" />
        <span>{{ t('nav.contacts') }}</span>
      </button>
      <button
        type="button"
        class="conv-main-tab"
        :class="{ 'conv-main-tab--active': mainSection === 'requests' }"
        role="tab"
        :aria-selected="mainSection === 'requests'"
        :aria-label="t('conversations.messageRequests')"
        @click="setMainSection('requests')"
      >
        <span class="conv-main-tab__icon-wrap">
          <Mail :size="18" stroke-width="2" />
          <span v-if="messageRequestsBadgeText" class="conv-main-tab__badge">{{ messageRequestsBadgeText }}</span>
        </span>
        <span class="conv-main-tab__label">{{ messageRequestsTabLabel }}</span>
      </button>
    </div>

    <template v-if="mainSection === 'chats'">
    <div
      ref="scrollAreaRef"
      class="scroll-area"
      :class="{ 'scroll-area--pulling': pullDistance > 0 || refreshing }"
      :style="pullDistance ? { '--pull-offset': `${pullDistance}px` } : undefined"
    >
      <div v-if="pullDistance > 0 || refreshing" class="pull-indicator">
        {{ refreshing ? t('common.loading') : t('conversations.pullRefresh') }}
      </div>

      <div v-if="needPhone" class="need-phone-banner">
        <span>{{ t('conversations.needPhone') }}</span>
        <button class="link-btn" @click="router.push('/complete-profile')">{{ t('completeProfile.completeNow') }}</button>
      </div>

      <div class="hero-card">
        <div class="hero-card__pattern" aria-hidden="true" />
        <div class="hero-card__head">
          <h2 class="hero-card__label">{{ t('stories.allStory') }}</h2>
        </div>

        <StoriesStrip v-if="storiesEnabled" variant="hero" />

        <div class="hero-search">
          <Search :size="18" class="hero-search__icon" aria-hidden="true" />
          <input
            v-model="searchQuery"
            type="search"
            class="hero-search__input"
            :placeholder="t('conversations.searchRecent')"
          />
          <button
            type="button"
            class="hero-search__action"
            :disabled="markingAllRead || totalUnread <= 0"
            :title="t('conversations.markAllRead')"
            :aria-label="t('conversations.markAllRead')"
            @click="markAllRead"
          >
            <CheckCheck :size="18" stroke-width="2" />
          </button>
        </div>
      </div>

      <div
        class="filter-row"
        :dir="localeStore.htmlDir"
        role="tablist"
        :aria-busy="listLoading"
      >
        <button
          v-for="f in ['all', 'unread', 'archived']"
          :key="f"
          type="button"
          class="filter-chip"
          :class="{ 'filter-chip--active': filter === f, 'filter-chip--loading': listLoading }"
          role="tab"
          :aria-selected="filter === f"
          :disabled="listLoading"
          @click="filter = f"
        >
          <Check v-if="filter === f" :size="14" stroke-width="2.5" class="filter-chip__check" />
          <span>{{ f === 'all' ? t('conversations.filterAll') : f === 'unread' ? t('conversations.filterUnread') : t('conversations.filterArchived') }}</span>
          <span v-if="f === 'unread' && totalUnread > 0" class="filter-chip__badge">{{ totalUnread > 99 ? '99+' : totalUnread }}</span>
        </button>
      </div>
      <div
        v-if="listLoading && mainSection === 'chats'"
        class="conv-list-skeleton"
        :aria-label="t('conversations.loadingList')"
        aria-busy="true"
      >
        <div class="conv-skeleton-section skeleton-shimmer" />
        <ListSkeleton :rows="7" />
      </div>
      <EmptyState
        v-else-if="ready && !filteredList.length"
        :title="t('conversations.empty')"
      >
        <template #icon>
          <MessageCircle :size="32" />
        </template>
        <template #action>
          <button class="btn-gradient" @click="goToContacts">{{ t('conversations.newChat') }}</button>
        </template>
      </EmptyState>
      <div v-else-if="filteredList.length" class="chat-sections">
        <template v-for="row in listWithSections" :key="row.key">
          <div v-if="row.type === 'header'" class="section-head">
            <Pin v-if="row.icon === 'pin'" :size="16" stroke-width="2" />
            <MessageCircle v-else :size="16" stroke-width="2" />
            <span>{{ row.title }}</span>
          </div>
          <div
            v-else
            class="conv-item"
            :class="{
              unread: getUnreadCount(row.data) > 0,
              'is-group': row.data.isGroup ?? row.data.IsGroup,
              'conv-item--active': activeConversationId && String(row.data.id ?? row.data.Id) === activeConversationId
            }"
            @click="goToConversation(row.data)"
            @contextmenu.prevent="openContextMenu(row.data, $event)"
          >
            <div
              class="item-avatar"
              :class="{
                'avatar-group': row.data.isGroup ?? row.data.IsGroup,
                'avatar-elevated-bg': !(row.data.isGroup ?? row.data.IsGroup) && !(row.data.partnerAvatar ?? row.data.PartnerAvatar),
                'avatar-no-photo': !(row.data.isGroup ?? row.data.IsGroup) && !(
                  (row.data.partnerAvatar ?? row.data.PartnerAvatar) && isImageAvatar(row.data.partnerAvatar ?? row.data.PartnerAvatar)
                )
              }"
              :style="{ background: (row.data.partnerAvatar ?? row.data.PartnerAvatar) && !isImageAvatar(row.data.partnerAvatar ?? row.data.PartnerAvatar) ? 'var(--primary)' : 'var(--bg-elevated)' }"
            >
              <CachedAvatar v-if="(row.data.partnerAvatar ?? row.data.PartnerAvatar) && isImageAvatar(row.data.partnerAvatar ?? row.data.PartnerAvatar)" :url="row.data.partnerAvatar ?? row.data.PartnerAvatar" img-class="avatar-img" />
              <Users v-else-if="row.data.isGroup ?? row.data.IsGroup" :size="16" class="avatar-group-icon" />
              <span v-else>{{ (row.data.partnerName ?? row.data.PartnerName)?.[0]?.toUpperCase() || '?' }}</span>
            </div>
            <div class="item-content">
              <div class="item-row item-row-name">
                <span class="item-name">{{ row.data.partnerName ?? row.data.PartnerName ?? '—' }}</span>
                <span class="item-time">{{ formatTime(row.data.lastMessageAt ?? row.data.LastMessageAt) }}</span>
              </div>
              <div class="item-row item-row-preview">
                <span class="item-preview">{{ getListPreview(row.data) }}</span>
                <span class="item-meta-col">
                  <span v-if="row.data.isGroup ?? row.data.IsGroup" class="group-badge">{{ t('groups.groupLabel') }}</span>
                  <span v-if="getUnreadCount(row.data) > 0" class="unread-badge-inline">{{ getUnreadCount(row.data) > 99 ? '99+' : getUnreadCount(row.data) }}</span>
                  <button
                    v-if="row.data.partnerId ?? row.data.PartnerId"
                    class="context-btn"
                    @click.stop="openContextMenu(row.data, $event)"
                    :aria-label="t('common.cancel')"
                  >
                    <MoreVertical :size="15" />
                  </button>
                </span>
              </div>
            </div>
          </div>
        </template>
      </div>
    </div>

    <div
      class="conv-fab-wrap"
      :class="{ 'is-open': fabOpen, 'conv-fab-wrap--pane': props.paneMode }"
    >
      <Transition name="fab-menu">
        <div v-if="fabOpen" class="conv-fab-menu" role="menu">
          <button
            type="button"
            class="conv-fab-menu-item"
            role="menuitem"
            @click="goToCreateGroupFromFab"
          >
            <span class="conv-fab-menu-label">{{ t('conversations.newGroup') }}</span>
            <span class="conv-fab-menu-icon conv-fab-menu-icon--group">
              <UsersRound :size="20" />
            </span>
          </button>
          <button
            type="button"
            class="conv-fab-menu-item"
            role="menuitem"
            @click="goToContacts"
          >
            <span class="conv-fab-menu-label">{{ t('conversations.newChat') }}</span>
            <span class="conv-fab-menu-icon conv-fab-menu-icon--chat">
              <MessageCircle :size="20" />
            </span>
          </button>
        </div>
      </Transition>
      <button
        type="button"
        class="conv-fab-main"
        :class="{ 'is-open': fabOpen }"
        :aria-label="fabOpen ? t('common.cancel') : t('conversations.composeMessage')"
        :aria-expanded="fabOpen"
        @click="toggleFabMenu"
      >
        <X v-if="fabOpen" :size="24" stroke-width="2.25" />
        <MessageSquarePlus v-else :size="24" stroke-width="2.25" />
      </button>
    </div>
    </template>

    <div v-else-if="mainSection === 'contacts'" ref="scrollAreaRef" class="scroll-area scroll-area--contacts">
      <ContactsPanel ref="contactsPanelRef" />
    </div>

    <div v-else ref="scrollAreaRef" class="scroll-area scroll-area--contacts">
      <MessageRequestsPanel :initial-notice="route.query.notice" />
    </div>
  </div>
</template>

<style scoped>
/* ——— Chatloop-style conversations ——— */
.conversations--chatloop {
  background: var(--bg-primary);
  font-family: 'Cairo', sans-serif;
}

.conv-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 10px) var(--spacing) 8px;
  flex-shrink: 0;
  background: var(--bg-primary);
}

.conv-header__title {
  margin: 0;
  color: var(--text-primary);
}

.conv-header__actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.conv-header__action-btn {
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--bg-card);
  border: none;
  border-radius: 14px;
  color: var(--primary);
  cursor: pointer;
  box-shadow: var(--shadow-sm);
  -webkit-tap-highlight-color: transparent;
}

.conv-main-tabs {
  display: flex;
  gap: 6px;
  margin: 0 var(--spacing) 12px;
  padding: 4px;
  background: var(--bg-elevated);
  border-radius: 16px;
  border: 1px solid var(--border);
  flex-shrink: 0;
}

.conv-main-tab {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 3px;
  min-height: 48px;
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

.conv-main-tab--active {
  background: var(--bg-card);
  color: var(--primary);
  box-shadow: var(--shadow-sm);
}

.conv-main-tab__icon-wrap {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.conv-main-tab__badge {
  position: absolute;
  top: -5px;
  inset-inline-end: -7px;
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  font-size: 9px;
  font-weight: 700;
  line-height: 16px;
  text-align: center;
  color: #fff;
  background: #EF4444;
  border-radius: var(--radius-full);
  border: 2px solid var(--bg-elevated);
  pointer-events: none;
}

.conv-main-tab--active .conv-main-tab__badge {
  border-color: var(--bg-card);
}

.conv-main-tab__label {
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  line-height: 1.2;
}

.scroll-area--contacts {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  padding-bottom: var(--safe-bottom);
}

.conv-header__bell {
  position: relative;
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--bg-card);
  border-radius: 14px;
  color: var(--text-primary);
  text-decoration: none;
  box-shadow: var(--shadow-sm);
  -webkit-tap-highlight-color: transparent;
}

.conv-header__bell-dot {
  position: absolute;
  top: 10px;
  inset-inline-end: 11px;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #EF4444;
  border: 2px solid var(--bg-card);
}

.hero-card {
  position: relative;
  overflow: hidden;
  isolation: isolate;
  margin: 4px var(--spacing) 10px;
  padding: 10px 12px 10px;
  border-radius: 20px;
  background: linear-gradient(145deg, #1D4ED8 0%, #2563EB 42%, #3B82F6 100%);
  border: 1px solid rgba(255, 255, 255, 0.14);
  box-shadow: 0 8px 24px rgba(37, 99, 235, 0.28);
}

:global(html.light) .hero-card,
:global([data-theme='light']) .hero-card {
  background: linear-gradient(145deg, #2563EB 0%, #3B82F6 48%, #60A5FA 100%);
  border-color: rgba(255, 255, 255, 0.28);
  box-shadow: 0 8px 22px rgba(37, 99, 235, 0.22);
}

.hero-card__pattern {
  position: absolute;
  inset: 0;
  z-index: 0;
  pointer-events: none;
  border-radius: inherit;
  background-image:
    linear-gradient(180deg, rgba(255, 255, 255, 0.1) 0%, transparent 32%),
    radial-gradient(circle at 92% 8%, rgba(255, 255, 255, 0.26) 0%, transparent 46%),
    radial-gradient(circle at 6% 90%, rgba(255, 255, 255, 0.14) 0%, transparent 40%),
    radial-gradient(ellipse 75% 55% at 50% 108%, rgba(191, 219, 254, 0.32) 0%, transparent 56%),
    radial-gradient(rgba(255, 255, 255, 0.1) 1px, transparent 1px);
  background-size: auto, auto, auto, auto, 11px 11px;
}

.hero-card__pattern::before {
  content: '';
  position: absolute;
  inset: -15%;
  background:
    repeating-linear-gradient(
      -32deg,
      transparent,
      transparent 18px,
      rgba(255, 255, 255, 0.045) 18px,
      rgba(255, 255, 255, 0.045) 19px
    );
  mask-image: radial-gradient(ellipse 88% 78% at 50% 38%, #000 18%, transparent 70%);
  -webkit-mask-image: radial-gradient(ellipse 88% 78% at 50% 38%, #000 18%, transparent 70%);
}

/* بقعة ضوء ناعمة — بدون حلقات دائرية واضحة */
.hero-card__pattern::after {
  content: '';
  position: absolute;
  top: -28px;
  inset-inline-start: -24px;
  width: 100px;
  height: 100px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(255, 255, 255, 0.22) 0%, transparent 68%);
  filter: blur(6px);
  opacity: 0.9;
}

.hero-card > :not(.hero-card__pattern) {
  position: relative;
  z-index: 1;
}

.hero-card__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 2px;
}

.hero-card__label {
  margin: 0;
  font-size: 14px;
  font-weight: 700;
  line-height: 1.2;
  color: #fff;
  text-shadow: 0 1px 2px rgba(15, 23, 42, 0.12);
}

.hero-card__menu {
  position: relative;
  width: 36px;
  height: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: none;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.18);
  color: #fff;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

:global(html.light) .hero-card__menu,
:global([data-theme='light']) .hero-card__menu {
  background: rgba(255, 255, 255, 0.22);
  color: #fff;
}

.hero-card__menu-badge {
  position: absolute;
  top: -4px;
  inset-inline-end: -4px;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  font-size: 10px;
  font-weight: 700;
  line-height: 18px;
  text-align: center;
  color: #fff;
  background: #EF4444;
  border-radius: var(--radius-full);
  border: 2px solid #2563EB;
}

:global(html.light) .hero-card__menu-badge,
:global([data-theme='light']) .hero-card__menu-badge {
  border-color: #3B82F6;
}

.hero-search {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 2px;
  padding: 0 10px 0 12px;
  min-height: 40px;
  background: #fff;
  border-radius: var(--radius-xl);
  box-shadow: 0 4px 16px rgba(15, 23, 42, 0.08);
}

.hero-search__icon {
  color: var(--text-muted);
  flex-shrink: 0;
}

.hero-search__input {
  flex: 1;
  min-width: 0;
  border: none;
  background: transparent;
  font-family: 'Cairo', sans-serif;
  font-size: 13px;
  color: var(--text-primary);
  outline: none;
}

.hero-search__input::placeholder {
  color: var(--text-muted);
}

.hero-search__action {
  width: 36px;
  height: 36px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  border: none;
  border-radius: 12px;
  background: var(--primary-soft);
  color: var(--primary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.hero-search__action:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.filter-row {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding: 0 var(--spacing) 12px;
  scrollbar-width: none;
}
.filter-row::-webkit-scrollbar { display: none; }

.filter-chip {
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 38px;
  padding: 0 16px;
  border: none;
  border-radius: var(--radius-full);
  background: var(--bg-card);
  color: var(--text-secondary);
  font-family: 'Cairo', sans-serif;
  font-size: 13px;
  font-weight: 600;
  box-shadow: var(--shadow-sm);
  cursor: pointer;
  white-space: nowrap;
  -webkit-tap-highlight-color: transparent;
  transition: background var(--motion-fast), color var(--motion-fast), box-shadow var(--motion-fast);
}

.filter-chip--active {
  background: var(--primary);
  color: #fff;
  box-shadow: 0 4px 14px rgba(59, 130, 246, 0.35);
}

.filter-chip__check {
  flex-shrink: 0;
}

.filter-chip__badge {
  min-width: 22px;
  height: 22px;
  padding: 0 6px;
  font-size: 11px;
  font-weight: 700;
  line-height: 22px;
  text-align: center;
  border-radius: var(--radius-full);
  background: var(--primary-soft);
  color: var(--primary);
}

.filter-chip--active .filter-chip__badge {
  background: rgba(255, 255, 255, 0.22);
  color: #fff;
}

.filter-chip:disabled {
  cursor: default;
}

.filter-chip--loading:not(.filter-chip--active) {
  opacity: 0.72;
}

.conv-list-skeleton {
  padding: 0 var(--spacing);
}

.conv-skeleton-section {
  width: 120px;
  height: 14px;
  border-radius: 6px;
  margin: 14px 4px 6px;
}

.chat-sections {
  display: flex;
  flex-direction: column;
  gap: 0;
  padding: 0 var(--spacing);
}

.section-head {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 14px 4px 10px;
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
}

.section-head svg {
  color: var(--primary);
  flex-shrink: 0;
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

.conversations--pane {
  position: relative;
  padding-bottom: 0;
}

.conversations--chatloop {
  background: var(--bg-primary);
}

.scroll-area {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  padding: 0;
  padding-bottom: calc(96px + var(--safe-bottom));
  background: var(--bg-primary);
  -webkit-overflow-scrolling: touch;
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
  color: var(--wa-header-text);
  text-align: center;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
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
/* زر طلبات المراسلة — واضح مع تسمية وشارة */
.msg-req-btn {
  position: relative;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 36px;
  padding: 0 11px 0 9px;
  border: 1px solid rgba(108, 99, 255, 0.32);
  border-radius: 20px;
  background: linear-gradient(145deg, rgba(108, 99, 255, 0.16), rgba(108, 99, 255, 0.06));
  color: var(--primary);
  cursor: pointer;
  flex-shrink: 0;
  max-width: min(46vw, 148px);
  font-family: 'Cairo', sans-serif;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.15s ease, border-color 0.15s ease, transform 0.12s ease, box-shadow 0.15s ease;
  box-shadow: 0 1px 4px rgba(108, 99, 255, 0.12);
}

.msg-req-btn.has-badge {
  padding-inline-end: 13px;
}

.msg-req-btn:active {
  transform: scale(0.97);
  background: linear-gradient(145deg, rgba(108, 99, 255, 0.22), rgba(108, 99, 255, 0.1));
}

.msg-req-btn-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 26px;
  height: 26px;
  border-radius: 50%;
  background: rgba(108, 99, 255, 0.14);
  flex-shrink: 0;
}

.msg-req-btn-label {
  font-size: 12px;
  font-weight: 700;
  line-height: 1.2;
  letter-spacing: 0.01em;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.msg-req-badge {
  position: absolute;
  top: -7px;
  inset-inline-end: -6px;
  min-width: 20px;
  height: 20px;
  padding: 0 6px;
  box-sizing: border-box;
  font-size: 11px;
  font-weight: 800;
  line-height: 1;
  color: #fff;
  background: linear-gradient(135deg, #ff6b4a, #f97316);
  border-radius: 10px;
  border: 2px solid var(--wa-header, var(--bg-secondary));
  font-family: 'Cairo', sans-serif;
  font-variant-numeric: tabular-nums;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 2px 6px rgba(249, 115, 22, 0.45);
  pointer-events: none;
}

html.light .msg-req-btn,
[data-theme='light'] .msg-req-btn {
  background: linear-gradient(145deg, rgba(108, 99, 255, 0.12), rgba(108, 99, 255, 0.04));
  border-color: rgba(108, 99, 255, 0.28);
  box-shadow: 0 1px 3px rgba(108, 99, 255, 0.1);
}

html.light .msg-req-btn-icon,
[data-theme='light'] .msg-req-btn-icon {
  background: rgba(108, 99, 255, 0.1);
}

html.light .msg-req-badge,
[data-theme='light'] .msg-req-badge {
  border-color: var(--bg-secondary);
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

.list-toolbar {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 10px var(--spacing) 12px;
  flex-shrink: 0;
  background: transparent;
}

.filter-tabs {
  display: flex;
  gap: 8px;
  width: 100%;
  min-width: 0;
  overflow-x: auto;
  padding-bottom: 2px;
  scrollbar-width: none;
  box-sizing: border-box;
}
.filter-tabs::-webkit-scrollbar { display: none; }

.search-toolbar {
  display: flex;
  align-items: center;
  gap: 6px;
  width: 100%;
  min-width: 0;
}

.search-toolbar .search-input-wrap {
  flex: 1;
  min-width: 0;
}

.mark-all-read-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  width: 40px;
  height: 40px;
  padding: 0;
  border-radius: var(--radius-full);
  border: none;
  background: var(--primary-soft);
  color: var(--primary);
  cursor: pointer;
  box-shadow: var(--shadow-sm);
  -webkit-tap-highlight-color: transparent;
}
.mark-all-read-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}

.filter-btn {
  flex: 0 0 auto;
  min-width: 0;
  min-height: 36px;
  padding: 8px 16px;
  font-size: 13px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  border-radius: var(--radius-full);
  border: none;
  background: var(--bg-card);
  color: var(--text-secondary);
  cursor: pointer;
  box-shadow: var(--shadow-sm);
  -webkit-tap-highlight-color: transparent;
  transition: background var(--motion-fast), color var(--motion-fast), box-shadow var(--motion-fast);
  white-space: nowrap;
}

.filter-btn.active {
  background: var(--primary);
  color: #fff;
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
}
html.light .conversations--wa .filter-btn.active,
[data-theme="light"] .conversations--wa .filter-btn.active {
  background: var(--primary);
  color: #fff;
  box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
}

.search-input-wrap {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 16px;
  min-height: 44px;
  border-radius: var(--radius-xl);
  border: 1px solid var(--border);
  background: var(--bg-card);
  box-shadow: var(--shadow-sm);
}
html.light .conversations--wa .search-input-wrap,
[data-theme="light"] .conversations--wa .search-input-wrap {
  box-shadow: var(--shadow-sm);
}

.search-icon {
  color: var(--wa-search-icon, var(--text-muted));
  flex-shrink: 0;
}

.search-input {
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

.scroll-area--pulling {
  transform: translateY(var(--pull-offset, 0));
  transition: transform 0.15s var(--ease-out);
}

.pull-indicator {
  padding: 10px;
  text-align: center;
  font-size: 12px;
  color: var(--text-muted);
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 48px 24px calc(88px + var(--safe-bottom));
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

.conv-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 14px;
  margin-bottom: 8px;
  min-height: 72px;
  cursor: pointer;
  border-radius: var(--radius-lg);
  position: relative;
  border: none;
  background: var(--bg-card);
  box-shadow: var(--shadow-sm);
  -webkit-tap-highlight-color: transparent;
  transition: transform var(--motion-fast), box-shadow var(--motion-fast);
}

.conv-item:active {
  transform: scale(0.99);
  box-shadow: var(--shadow-md);
}

.conversations--chatloop .conv-item.is-group {
  border-inline-start: 3px solid var(--primary);
  padding-inline-start: 11px;
}

.conv-item.unread .item-name { font-weight: 800; }

.conv-item.unread .item-preview {
  color: var(--text-secondary);
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

.item-row-name {
  align-items: flex-start;
}

.item-row-preview {
  align-items: center;
  margin-top: 2px;
}

.item-meta-col {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 4px;
  flex-shrink: 0;
  min-width: 28px;
}

.item-time {
  font-size: 11px;
  color: var(--text-muted);
  font-family: 'Cairo', sans-serif;
  font-variant-numeric: tabular-nums;
  flex-shrink: 0;
}

.unread-badge-inline {
  min-width: 20px;
  height: 20px;
  padding: 0 6px;
  background: var(--primary);
  color: white;
  font-size: 11px;
  font-weight: 700;
  font-family: 'Cairo', sans-serif;
  border-radius: var(--radius-full);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 2px 6px rgba(59, 130, 246, 0.3);
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
/* زر عائم — رسالة جديدة */
.conv-fab-wrap {
  position: fixed;
  inset-inline-end: max(16px, var(--spacing));
  inset-inline-start: auto;
  bottom: calc(28px + var(--tab-bar-clearance));
  z-index: 90;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 10px;
  pointer-events: none;
}

.conv-fab-wrap > * {
  pointer-events: auto;
}

.conv-fab-menu {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 10px;
  margin-bottom: 2px;
}

.conv-fab-menu-item {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  padding: 0;
  border: none;
  background: transparent;
  cursor: pointer;
  font-family: 'Cairo', sans-serif;
  -webkit-tap-highlight-color: transparent;
}

.conv-fab-menu-item:active .conv-fab-menu-label {
  opacity: 0.85;
}

.conv-fab-menu-label {
  padding: 8px 12px;
  border-radius: var(--radius);
  background: var(--bg-card);
  color: var(--text-primary);
  font-size: 14px;
  font-weight: 600;
  line-height: 1.2;
  box-shadow: var(--shadow-sm);
  white-space: nowrap;
  text-align: start;
}

.conv-fab-menu-icon {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  flex-shrink: 0;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.2);
}

.conv-fab-menu-icon--chat {
  background: var(--primary);
}

.conv-fab-menu-icon--group {
  background: #5c6bc0;
}

.conv-fab-main {
  width: 56px;
  height: 56px;
  border-radius: var(--radius-full);
  border: none;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--primary);
  color: #fff;
  cursor: pointer;
  box-shadow: 0 6px 20px rgba(59, 130, 246, 0.4);
  transition: transform var(--motion-fast), background var(--motion-fast), box-shadow var(--motion-fast);
  -webkit-tap-highlight-color: transparent;
}

.conv-fab-main.is-open {
  background: var(--bg-card);
  color: var(--text-primary);
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.18);
  transform: rotate(0deg);
}

.conv-fab-main:active {
  transform: scale(0.96);
}

.conv-fab-main.is-open:active {
  transform: scale(0.96);
}

.fab-menu-enter-active,
.fab-menu-leave-active {
  transition: opacity 0.2s ease, transform 0.22s cubic-bezier(0.32, 0.72, 0, 1);
}

.fab-menu-enter-from,
.fab-menu-leave-to {
  opacity: 0;
  transform: translateY(10px) scale(0.94);
  transform-origin: bottom right;
}

[dir='rtl'] .fab-menu-enter-from,
[dir='rtl'] .fab-menu-leave-to {
  transform-origin: bottom left;
}

html.light .conv-fab-menu-label,
[data-theme='light'] .conv-fab-menu-label {
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.08);
}

/* ديسكتوب: FAB داخل عمود القائمة */
@media (min-width: 1024px) {
  .conversations--pane .scroll-area {
    padding-bottom: 88px;
  }

  .conversations--pane .conv-fab-wrap {
    position: absolute;
    inset-inline-end: var(--spacing-lg);
    inset-inline-start: auto;
    bottom: 20px;
    z-index: 30;
  }
}

@media (max-width: 420px) {
  .conv-fab-wrap {
    inset-inline-end: 14px;
    bottom: calc(24px + var(--tab-bar-clearance));
  }
  .conv-fab-main {
    width: 52px;
    height: 52px;
  }
  .conv-fab-menu-icon {
    width: 40px;
    height: 40px;
  }
  .conv-fab-menu-label {
    font-size: 13px;
    padding: 7px 10px;
  }
}

@media (max-width: 420px) {
  .top-bar {
    padding: calc(var(--safe-top) + 8px) 8px 8px;
    gap: 6px;
  }
  .header-actions {
    gap: 4px;
  }
  .top-bar .back-btn {
    width: 32px !important;
    height: 32px !important;
    min-width: 32px !important;
    min-height: 32px !important;
    border-radius: 8px;
  }
  .top-bar .back-btn :deep(svg) {
    width: 16px !important;
    height: 16px !important;
  }
  .msg-req-btn {
    min-height: 32px;
    padding: 0 9px 0 7px;
    gap: 5px;
    border-radius: 16px;
  }
  .msg-req-btn-icon {
    width: 22px;
    height: 22px;
  }
  .msg-req-btn-icon :deep(svg) {
    width: 15px !important;
    height: 15px !important;
  }
  .msg-req-btn-label {
    font-size: 11px;
  }
  .msg-req-badge {
    min-width: 18px;
    height: 18px;
    font-size: 10px;
    padding: 0 5px;
    top: -6px;
    inset-inline-end: -5px;
  }
}

@media (max-width: 320px) {
  .top-bar {
    padding: calc(var(--safe-top) + 6px) 6px 6px;
    gap: 4px;
  }
  .header-actions {
    gap: 2px;
  }
  .top-bar .back-btn {
    width: 30px !important;
    height: 30px !important;
    min-width: 30px !important;
    min-height: 30px !important;
  }
  .top-bar .back-btn :deep(svg) {
    width: 15px !important;
    height: 15px !important;
  }
  .msg-req-btn-label {
    font-size: 10px;
  }
}

@media (max-width: 360px) {
  .list-toolbar {
    padding: 5px 8px 6px;
    gap: 5px;
  }
  .filter-tabs {
    gap: 3px;
    padding: 2px;
  }
  .filter-btn {
    min-height: 26px;
    padding: 4px 3px;
    font-size: 10px;
  }
  .mark-all-read-btn {
    width: 30px;
    height: 30px;
  }
  .search-input-wrap {
    min-height: 32px;
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
