<script setup>
import { onMounted, onUnmounted } from 'vue'
import { Bell, Trash2 } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useNotificationsStore } from '../stores/notifications'
import { useLocaleStore } from '../stores/locale'
import { formatGregorianDateTime } from '../utils/formatTime'
import ModernPageShell from '../components/ui/ModernPageShell.vue'
import api from '../services/api'
import { navigateFromNotification, normalizeServerNotification } from '../services/notifications'

const { t } = useI18n()
const notifications = useNotificationsStore()
const localeStore = useLocaleStore()

function formatTime(timestamp) {
  if (!timestamp) return ''
  const d = new Date(timestamp)
  const now = new Date()
  const diff = now - d
  const locale = localeStore.locale
  if (diff < 60000) return t('connectionHistory.now')
  if (diff < 3600000) return t('connectionHistory.minutesAgo', { n: Math.floor(diff / 60000) })
  if (diff < 86400000) return t('connectionHistory.hoursAgo', { n: Math.floor(diff / 3600000) })
  return formatGregorianDateTime(d, locale)
}

function getTypeLabel(type) {
  if (type === 'video_call') return t('notifications.typeVideoCall')
  if (type === 'code_connected') return t('notifications.typeCode')
  if (type === 'conversation_message' || type === 'message') return t('notifications.typeMessage')
  if (type === 'story_published') return t('notifications.typeStory')
  if (type === 'message_request') return t('notifications.typeMessageRequest')
  return t('notifications.typeDefault')
}

function handleClick(n) {
  notifications.markRead(n.id)
  if (n.serverId) api.put(`/user-notifications/${n.serverId}/read`).catch(() => {})
  navigateFromNotification(n)
}

function clearAll() {
  notifications.clear()
  api.put('/user-notifications/read-all').catch(() => {})
}

const handler = (e) => notifications.add(e.detail)

onMounted(() => {
  notifications.load()
  api.get('/user-notifications?take=40')
    .then(({ data }) => {
      const normalized = (data || []).map((x) => normalizeServerNotification(x))
      if (normalized.length) {
        const seen = new Set(notifications.list.map(x => String(x.serverId || x.id)))
        normalized.forEach((n) => {
          if (!seen.has(String(n.serverId))) notifications.add(n)
        })
      }
    })
    .catch(() => {})
  window.addEventListener('nexchat:notification', handler)
})

onUnmounted(() => {
  window.removeEventListener('nexchat:notification', handler)
})
</script>

<template>
  <ModernPageShell :title="t('settings.notifications')" back-to="/home">
    <template #actions>
      <button
        v-if="notifications.list.length"
        type="button"
        class="modern-glass-btn"
        :title="t('notifications.clearAll')"
        :aria-label="t('notifications.clearAll')"
        @click="clearAll"
      >
        <Trash2 :size="18" stroke-width="2" />
      </button>
    </template>

    <div v-if="!notifications.list.length" class="modern-empty">
      <Bell :size="48" />
      <p>{{ t('notifications.empty') }}</p>
    </div>

    <div v-else class="modern-list">
      <button
        v-for="n in notifications.list"
        :key="n.id"
        type="button"
        class="modern-list-row modern-list-row--clickable notif-row"
        :class="{ unread: !n.isRead }"
        @click="handleClick(n)"
      >
        <div class="modern-list-row__avatar notif-icon">
          <Bell :size="22" stroke-width="2" />
        </div>
        <div class="modern-list-row__body">
          <span class="modern-list-row__title">{{ n.title || getTypeLabel(n.type) }}</span>
          <span class="modern-list-row__sub">{{ n.body }}</span>
          <span class="notif-time">{{ formatTime(n.timestamp) }}</span>
        </div>
      </button>
    </div>
  </ModernPageShell>
</template>

<style scoped>
.notif-row {
  width: 100%;
  border: none;
  text-align: inherit;
  font: inherit;
  cursor: pointer;
}

.notif-row.unread {
  border-color: var(--primary-muted);
  background: var(--primary-soft);
}

.notif-icon {
  background: var(--primary-soft);
  color: var(--primary);
}

.notif-time {
  font-size: 11px;
  color: var(--text-muted);
  margin-top: 4px;
}
</style>
