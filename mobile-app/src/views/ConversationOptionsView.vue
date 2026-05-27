<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Pin, Archive, Trash2, Check, User, Users } from 'lucide-vue-next'
import ModernPageShell from '../components/ui/ModernPageShell.vue'
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
  <ModernPageShell :title="t('conversations.optionsTitle')" back-to="/conversations">
    <template v-if="conv">
      <div class="conv-hero">
        <div
          class="modern-avatar-xl conv-hero-avatar"
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
        <h2 class="modern-profile-name">{{ conv.partnerName ?? conv.PartnerName ?? '—' }}</h2>
      </div>

      <div class="modern-option-list">
        <button class="modern-option-btn" @click="openProfile">
          <component :is="(conv.isGroup ?? conv.IsGroup) ? Users : User" :size="18" />
          <span>{{ (conv.isGroup ?? conv.IsGroup) ? t('groups.infoTitle') : t('profile.viewProfile') }}</span>
        </button>
        <button class="modern-option-btn" @click="togglePin">
          <Pin :size="18" />
          <span>{{ (conv.isPinned ?? conv.IsPinned) ? t('conversations.unpin') : t('conversations.pin') }}</span>
        </button>
        <button class="modern-option-btn" @click="toggleArchive">
          <Archive :size="18" />
          <span>{{ (conv.isArchived ?? conv.IsArchived) ? t('conversations.unarchive') : t('conversations.archive') }}</span>
        </button>
        <button v-if="getUnreadCount(conv) > 0" class="modern-option-btn" @click="markRead">
          <Check :size="18" />
          <span>{{ t('conversations.markRead') }}</span>
        </button>
        <button class="modern-option-btn modern-option-btn--danger" @click="deleteConversation">
          <Trash2 :size="18" />
          <span>{{ t('conversations.delete') }}</span>
        </button>
      </div>
    </template>
    <div v-else class="modern-empty">
      <p>{{ t('conversations.notFound') }}</p>
      <button class="btn-gradient" style="max-width:240px" @click="goBack">{{ t('common.back') }}</button>
    </div>
  </ModernPageShell>
</template>

<style scoped>
.conv-hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 16px 0 24px;
}

.conv-hero-avatar {
  width: 96px;
  height: 96px;
  font-size: 32px;
}
</style>
