<script setup>
import { ref, computed, watch } from 'vue'
import { Send, Inbox, Clock, Hash } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { useLocaleStore } from '../stores/locale'
import { formatGregorianDateTime } from '../utils/formatTime'
import ModernPageShell from '../components/ui/ModernPageShell.vue'
import { useRouter } from 'vue-router'

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
</script>

<template>
  <ModernPageShell :title="t('connectionHistory.title')" back-to="/settings">
    <div class="modern-chip-row">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        type="button"
        class="filter-chip"
        :class="{ 'filter-chip--active': activeTab === tab.id }"
        @click="activeTab = tab.id"
      >
        <component :is="tab.icon" :size="14" stroke-width="2" />
        <span>{{ tab.label }}</span>
      </button>
    </div>

    <div v-if="loading" class="modern-empty">{{ t('common.loading') }}</div>
    <div v-else-if="!list.length" class="modern-empty">
      <Hash :size="48" />
      <p>{{ t('connectionHistory.empty') }}</p>
    </div>
    <div v-else class="modern-list">
      <div
        v-for="item in list"
        :key="item.id"
        class="modern-list-row"
        :class="{ 'modern-list-row--clickable': item.sessionId }"
        @click="item.sessionId && openChat(item)"
      >
        <div class="modern-list-row__avatar">
          <img v-if="isImageAvatar(item.otherAvatar)" :src="ensureAbsoluteUrl(item.otherAvatar)" alt="" />
          <span v-else>{{ item.otherName?.[0]?.toUpperCase() || '?' }}</span>
        </div>
        <div class="modern-list-row__body">
          <span class="modern-list-row__title">{{ item.otherName }}</span>
          <span class="modern-list-row__sub">{{ item.otherCode }}</span>
          <span class="modern-list-row__sub">{{ getStatusLabel(item.status) }} · {{ formatTime(item.createdAt) }}</span>
        </div>
      </div>
    </div>
  </ModernPageShell>
</template>

<style scoped>
.modern-chip-row {
  padding: 0 0 12px;
  margin-bottom: 4px;
}
</style>
