<script setup>
import { onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, Bell, Trash2 } from 'lucide-vue-next'
import { useNotificationsStore } from '../stores/notifications'
import { useLocaleStore } from '../stores/locale'
import { formatGregorianDateTime } from '../utils/formatTime'
import api from '../services/api'

const router = useRouter()
const notifications = useNotificationsStore()
const localeStore = useLocaleStore()

function formatTime(timestamp) {
  if (!timestamp) return ''
  const d = new Date(timestamp)
  const now = new Date()
  const diff = now - d
  const locale = localeStore.locale
  if (diff < 60000) return 'الآن'
  if (diff < 3600000) return `منذ ${Math.floor(diff / 60000)} د`
  if (diff < 86400000) return `منذ ${Math.floor(diff / 3600000)} س`
  return formatGregorianDateTime(d, locale)
}

function getTypeLabel(type) {
  if (type === 'video_call') return 'مكالمة فيديو'
  if (type === 'code_connected') return 'اتصال بالكود'
  if (type === 'conversation_message') return 'رسالة محادثة'
  return 'رسالة'
}

function handleClick(n) {
  notifications.markRead(n.id)
  if (n.serverId) api.put(`/user-notifications/${n.serverId}/read`).catch(() => {})
  if (n.conversationId) {
    router.push({ path: '/conversations', query: { open: n.conversationId } })
    return
  }
  if (n.sessionId) {
    if (n.type === 'video_call') router.push(`/chat/${n.sessionId}`)
    else router.push(`/chat/${n.sessionId}`)
  }
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
      const normalized = (data || []).map((x) => {
        let parsed = {}
        try { parsed = JSON.parse(x.dataJson || '{}') } catch {}
        return {
          id: `srv-${x.id}`,
          serverId: x.id,
          type: x.type,
          title: x.title,
          body: x.body,
          timestamp: x.createdAt,
          isRead: x.isRead,
          sessionId: parsed.sessionId,
          conversationId: parsed.conversationId,
          messageRequestId: parsed.messageRequestId
        }
      })
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
  <div class="notifications page">
    <header class="top-bar">
      <button class="back-btn" @click="router.replace('/settings')"><ChevronRight :size="22" /></button>
      <span class="top-title">الإشعارات</span>
      <button v-if="notifications.list.length" class="clear-btn" @click="clearAll" title="مسح الكل">
        <Trash2 :size="20" />
      </button>
      <div v-else style="width:40px"></div>
    </header>

    <div class="scroll-area">
      <div v-if="!notifications.list.length" class="empty-state">
        <Bell :size="48" class="empty-icon" />
        <p>لا توجد إشعارات</p>
      </div>
      <div v-else class="notif-list">
        <button
          v-for="n in notifications.list"
          :key="n.id"
          class="notif-row glass-card"
          :class="{ unread: !n.isRead }"
          @click="handleClick(n)"
        >
          <div class="notif-icon" :class="n.type">
            <Bell :size="20" />
          </div>
          <div class="notif-content">
            <span class="notif-title">{{ n.title || getTypeLabel(n.type) }}</span>
            <span class="notif-body">{{ n.body }}</span>
            <span class="notif-time">{{ formatTime(n.timestamp) }}</span>
          </div>
          <ChevronRight v-if="n.sessionId || n.conversationId" :size="18" class="notif-arrow" />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.notifications {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  overflow: hidden;
  font-family: 'Cairo', sans-serif;
}

.top-bar {
  align-items: center;
  display: flex;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 12px;
}

.back-btn, .clear-btn {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  height: var(--touch-min);
  justify-content: center;
  min-width: var(--touch-min);
}

.back-btn:active, .clear-btn:active { background: var(--bg-card-hover); }

.top-title { font-size: 17px; font-weight: 600; }

.scroll-area {
  flex: 1;
  overflow-y: auto;
  padding: var(--spacing);
  padding-bottom: calc(var(--spacing) + var(--safe-bottom));
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 48px 24px;
  color: var(--text-muted);
}

.empty-icon { opacity: 0.4; margin-bottom: 16px; }

.notif-list { display: flex; flex-direction: column; gap: 8px; }

.notif-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 14px var(--spacing);
  text-align: start;
  cursor: pointer;
  border: 1px solid var(--border);
  width: 100%;
}

.notif-row:active { background: var(--bg-card-hover); }
.notif-row.unread {
  border-color: rgba(108, 99, 255, 0.35);
  box-shadow: 0 0 0 1px rgba(108, 99, 255, 0.15) inset;
}

.notif-icon {
  width: 40px;
  height: 40px;
  min-width: 40px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(108, 99, 255, 0.15);
  color: var(--primary);
}

.notif-icon.video_call { background: rgba(255, 101, 132, 0.15); color: var(--danger); }

.notif-icon.code_connected { background: rgba(34, 197, 94, 0.15); color: var(--success); }

.notif-icon.conversation_message { background: rgba(124, 117, 255, 0.15); color: var(--primary); }

.notif-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.notif-title { font-weight: 600; font-size: 15px; font-family: 'Cairo', sans-serif; }

.notif-body {
  font-size: 13px;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  font-family: 'Cairo', sans-serif;
}

.notif-time { font-size: 12px; color: var(--text-muted); }

.notif-arrow { color: var(--text-muted); flex-shrink: 0; }
</style>
