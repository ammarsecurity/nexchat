<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronRight, Pin, Archive, Trash2, Check, User, Users } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import CachedAvatar from '../components/CachedAvatar.vue'
import { useConversationsListStore } from '../stores/conversationsList'

const route = useRoute()
const router = useRouter()
const { t } = useI18n()
const listStore = useConversationsListStore()

const conversationId = route.params.conversationId
const conv = computed(() =>
  listStore.list.find((c) => String(c.id ?? c.Id) === String(conversationId))
)

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))
function getUnreadCount(c) {
  const n = c?.unreadCount ?? c?.UnreadCount ?? 0
  return typeof n === 'number' ? n : parseInt(n, 10) || 0
}

function goBack() {
  router.replace('/conversations')
}

function openProfile() {
  if (!conv.value) return
  const id = conv.value.id ?? conv.value.Id
  const isGroupConv = conv.value.isGroup ?? conv.value.IsGroup
  if (isGroupConv && id) {
    router.push(`/conversation/${id}/group-info`)
    return
  }
  const pid = conv.value.partnerId ?? conv.value.PartnerId
  if (!pid) return
  router.push({
    path: `/profile/${pid}`,
    state: { conversationId }
  })
}

async function togglePin() {
  if (!conv.value) return
  try {
    const id = conv.value.id ?? conv.value.Id
    await api.put(`/conversations/${id}/pin`)
    listStore.updateConversation(id, { isPinned: !(conv.value.isPinned ?? conv.value.IsPinned) })
  } catch {}
  goBack()
}

async function toggleArchive() {
  if (!conv.value) return
  try {
    const id = conv.value.id ?? conv.value.Id
    await api.put(`/conversations/${id}/archive`)
    listStore.updateConversation(id, { isArchived: !(conv.value.isArchived ?? conv.value.IsArchived) })
  } catch {}
  goBack()
}

async function markRead() {
  if (!conv.value) return
  try {
    const id = conv.value.id ?? conv.value.Id
    await api.put(`/conversations/${id}/read`)
    listStore.updateConversation(id, { unreadCount: 0 })
  } catch {}
  goBack()
}

async function deleteConversation() {
  if (!conv.value) return
  try {
    const id = conv.value.id ?? conv.value.Id
    await api.delete(`/conversations/${id}`)
    listStore.removeConversation(id)
  } catch {}
  goBack()
}
</script>

<template>
  <div class="conversation-options page auth-pattern">
    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('conversations.optionsTitle') }}</span>
    </header>

    <template v-if="conv">
      <div class="conv-header">
        <div
          class="conv-avatar"
          :style="{
            background:
              (conv.partnerAvatar ?? conv.PartnerAvatar) && !isImageAvatar(conv.partnerAvatar ?? conv.PartnerAvatar)
                ? 'var(--primary)'
                : 'var(--bg-elevated)'
          }"
        >
          <CachedAvatar
            v-if="(conv.partnerAvatar ?? conv.PartnerAvatar) && isImageAvatar(conv.partnerAvatar ?? conv.PartnerAvatar)"
            :url="conv.partnerAvatar ?? conv.PartnerAvatar"
            img-class="avatar-img"
          />
          <span v-else>{{ (conv.partnerName ?? conv.PartnerName)?.[0]?.toUpperCase() || '?' }}</span>
        </div>
        <p class="conv-name">{{ conv.partnerName ?? conv.PartnerName ?? '—' }}</p>
      </div>

      <div class="options-list">
        <button class="option-btn" @click="openProfile">
          <component :is="(conv.isGroup ?? conv.IsGroup) ? Users : User" :size="20" />
          <span>{{ (conv.isGroup ?? conv.IsGroup) ? t('groups.infoTitle') : t('profile.viewProfile') }}</span>
        </button>
        <button class="option-btn" @click="togglePin">
          <Pin :size="20" />
          <span>{{ (conv.isPinned ?? conv.IsPinned) ? t('conversations.unpin') : t('conversations.pin') }}</span>
        </button>
        <button class="option-btn" @click="toggleArchive">
          <Archive :size="20" />
          <span>{{ (conv.isArchived ?? conv.IsArchived) ? t('conversations.unarchive') : t('conversations.archive') }}</span>
        </button>
        <button v-if="getUnreadCount(conv) > 0" class="option-btn" @click="markRead">
          <Check :size="20" />
          <span>{{ t('conversations.markRead') }}</span>
        </button>
        <button class="option-btn danger" @click="deleteConversation">
          <Trash2 :size="20" />
          <span>{{ t('conversations.delete') }}</span>
        </button>
      </div>
    </template>
    <div v-else class="empty-state">
      <p>{{ t('conversations.notFound') }}</p>
      <button class="btn-gradient" @click="goBack">{{ t('common.back') }}</button>
    </div>
  </div>
</template>

<style scoped>
.conversation-options {
  background: var(--bg-primary);
  min-height: 100%;
  padding-bottom: var(--safe-bottom);
  font-family: 'Cairo', sans-serif;
}

.top-bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 12px;
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

.conv-header {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 24px var(--spacing);
  gap: 12px;
}

.conv-avatar {
  width: 72px;
  height: 72px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  color: white;
  font-size: 28px;
  font-weight: 600;
}

.conv-avatar .avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.conv-name {
  font-size: 18px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
}

.options-list {
  padding: 0 var(--spacing);
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.option-btn {
  display: flex;
  align-items: center;
  gap: 16px;
  width: 100%;
  padding: 16px 20px;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--bg-card);
  color: var(--text-primary);
  font-size: 16px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  text-align: start;
  -webkit-tap-highlight-color: transparent;
}

.option-btn:active {
  background: var(--bg-elevated);
}

.option-btn.danger {
  color: #f44336;
  margin-top: 8px;
}

.empty-state {
  padding: 32px var(--spacing);
  text-align: center;
  color: var(--text-secondary);
}

.empty-state p {
  margin-bottom: 16px;
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
}
</style>
