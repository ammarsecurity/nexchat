<script setup>
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, Send, Inbox, Clock, Hash } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { useLocaleStore } from '../stores/locale'
import { formatGregorianDateTime } from '../utils/formatTime'

const router = useRouter()
const { t } = useI18n()
const localeStore = useLocaleStore()

const activeTab = ref('sent')
const loading = ref(false)
const list = ref([])

const tabs = computed(() => [
  { id: 'sent', label: t('connectionHistory.sent'), icon: Send },
  { id: 'received', label: t('connectionHistory.received'), icon: Inbox },
  { id: 'missed', label: t('connectionHistory.missed'), icon: Clock }
])

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

async function fetchList() {
  loading.value = true
  try {
    const { data } = await api.get('/user/connection-history', { params: { filter: activeTab.value } })
    list.value = data ?? []
  } catch {
    list.value = []
  } finally {
    loading.value = false
  }
}

watch(activeTab, fetchList, { immediate: true })

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

function getStatusLabel(status) {
  const map = {
    Pending: t('connectionHistory.statusPending'),
    Accepted: t('connectionHistory.statusAccepted'),
    Declined: t('connectionHistory.statusDeclined'),
    Cancelled: t('connectionHistory.statusCancelled')
  }
  return map[status] ?? status
}

function openChat(item) {
  if (item.sessionId) router.push(`/chat/${item.sessionId}`)
}

function goBack() {
  router.replace('/settings')
}
</script>

<template>
  <div class="connection-history page auth-pattern">
    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('connectionHistory.title') }}</span>
      <div class="top-bar-width-spacer" aria-hidden="true"></div>
    </header>

    <div class="tabs-wrap">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        class="tab-btn"
        :class="{ active: activeTab === tab.id }"
        @click="activeTab = tab.id"
      >
        <component :is="tab.icon" :size="18" stroke-width="2" />
        <span>{{ tab.label }}</span>
      </button>
    </div>

    <div class="scroll-area">
      <div v-if="loading" class="loading-msg">{{ t('common.loading') }}</div>
      <div v-else-if="!list.length" class="empty-state">
        <Hash :size="48" class="empty-icon" />
        <p>{{ t('connectionHistory.empty') }}</p>
      </div>
      <div v-else class="history-list">
        <div
          v-for="item in list"
          :key="item.id"
          class="history-item glass-card"
          :class="{ clickable: item.sessionId }"
          @click="item.sessionId && openChat(item)"
        >
          <div class="item-avatar" :style="{ background: item.otherAvatar && !isImageAvatar(item.otherAvatar) ? 'var(--primary)' : 'var(--bg-elevated)' }">
            <img v-if="isImageAvatar(item.otherAvatar)" :src="ensureAbsoluteUrl(item.otherAvatar)" class="avatar-img" referrerpolicy="no-referrer" />
            <span v-else>{{ item.otherName?.[0]?.toUpperCase() || '?' }}</span>
          </div>
          <div class="item-content">
            <span class="item-name">{{ item.otherName }}</span>
            <span class="item-code">{{ item.otherCode }}</span>
            <span class="item-meta">
              {{ getStatusLabel(item.status) }} · {{ formatTime(item.createdAt) }}
            </span>
          </div>
          <ChevronRight v-if="item.sessionId" :size="20" class="item-arrow" />
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.connection-history {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  padding-bottom: var(--safe-bottom);
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
  min-width: 40px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.back-btn:active { background: var(--bg-card-hover); }

.top-title {
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
}

.tabs-wrap {
  display: flex;
  gap: 8px;
  padding: 0 var(--spacing) 16px;
  flex-shrink: 0;
}

.tab-btn {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  padding: 10px 12px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 12px;
  color: var(--text-secondary);
  font-size: 13px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.tab-btn.active {
  background: rgba(108, 99, 255, 0.15);
  border-color: rgba(108, 99, 255, 0.4);
  color: var(--primary);
}
.tab-btn:active:not(.active) { opacity: 0.8; }

.scroll-area {
  flex: 1;
  overflow-y: auto;
  padding: 0 var(--spacing);
  -webkit-overflow-scrolling: touch;
}

.loading-msg {
  font-size: 14px;
  color: var(--text-muted);
  padding: 32px;
  text-align: center;
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 48px 24px;
  color: var(--text-muted);
  text-align: center;
}
.empty-icon { opacity: 0.4; margin-bottom: 16px; }

.history-list { display: flex; flex-direction: column; gap: 10px; padding-bottom: 24px; }

.history-item {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 14px 16px;
  border: 1px solid var(--border);
  border-radius: 14px;
}
.history-item.clickable { cursor: pointer; }
.history-item.clickable:active { background: var(--bg-card-hover); }

.item-avatar {
  width: 48px;
  height: 48px;
  min-width: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  font-weight: 700;
  color: white;
  overflow: hidden;
}
.avatar-img { width: 100%; height: 100%; object-fit: cover; }

.item-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.item-name { font-size: 15px; font-weight: 600; color: var(--text-primary); }
.item-code { font-size: 13px; color: var(--primary); letter-spacing: 0.5px; }
.item-meta { font-size: 12px; color: var(--text-muted); }
.item-arrow { color: var(--text-muted); flex-shrink: 0; }
</style>
