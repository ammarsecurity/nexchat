<script setup>
import { ref, onMounted, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import { Check, X } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { notify } from '../utils/notify'
import CachedAvatar from './CachedAvatar.vue'
import { useMessageRequestsStore } from '../stores/messageRequests'

const props = defineProps({
  /** 'outgoing-wait' | 'outgoing-share-wait' */
  initialNotice: { type: String, default: null }
})

const route = useRoute()
const { t } = useI18n()
const msgReqStore = useMessageRequestsStore()

const loading = ref(true)
const list = ref([])
const actionId = ref(null)
const outgoingBannerKind = ref(null)

const outgoingBannerText = computed(() => {
  if (outgoingBannerKind.value === 'share') return t('messageRequests.waitingForAcceptCannotShare')
  if (outgoingBannerKind.value === 'wait') return t('messageRequests.waitingForAcceptFromOther')
  return ''
})

function applyNotice(notice) {
  if (notice === 'outgoing-wait') outgoingBannerKind.value = 'wait'
  else if (notice === 'outgoing-share-wait') outgoingBannerKind.value = 'share'
}

function dismissOutgoingBanner() {
  outgoingBannerKind.value = null
}

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

async function fetchList() {
  loading.value = true
  try {
    const { data } = await api.get('/message-requests', { skipGlobalLoader: true })
    list.value = data ?? []
  } catch {
    list.value = []
  } finally {
    loading.value = false
  }
  await msgReqStore.fetchPendingCount()
}

async function accept(id) {
  if (actionId.value) return
  actionId.value = id
  try {
    await api.post(`/message-requests/${id}/accept`, {}, { skipGlobalLoader: true })
    list.value = list.value.filter((x) => (x.id ?? x.Id) !== id)
    await msgReqStore.fetchPendingCount()
  } catch (e) {
    const m = e.response?.data?.message ?? e.userMessage ?? t('common.error')
    notify.error(m)
  } finally {
    actionId.value = null
  }
}

async function decline(id) {
  if (actionId.value) return
  actionId.value = id
  try {
    await api.post(`/message-requests/${id}/decline`, {}, { skipGlobalLoader: true })
    list.value = list.value.filter((x) => (x.id ?? x.Id) !== id)
    await msgReqStore.fetchPendingCount()
  } catch (e) {
    const m = e.response?.data?.message ?? e.userMessage ?? t('common.error')
    notify.error(m)
  } finally {
    actionId.value = null
  }
}

onMounted(async () => {
  applyNotice(props.initialNotice || route.query.notice)
  await fetchList()
})

watch(
  () => props.initialNotice || route.query.notice,
  (notice) => applyNotice(notice)
)

defineExpose({ refresh: fetchList })
</script>

<template>
  <div class="msg-req-panel">
    <div v-if="outgoingBannerText" class="outgoing-banner" role="status">
      <p>{{ outgoingBannerText }}</p>
      <button type="button" class="outgoing-dismiss" :aria-label="t('common.cancel')" @click="dismissOutgoingBanner">×</button>
    </div>

    <div v-if="loading" class="msg-req-panel__empty">{{ t('common.loading') }}</div>
    <div v-else-if="!list.length" class="msg-req-panel__empty">
      <p>{{ t('messageRequests.empty') }}</p>
    </div>

    <div v-else class="modern-list">
      <div v-for="r in list" :key="r.id ?? r.Id" class="modern-list-row">
        <div class="modern-list-row__avatar">
          <CachedAvatar
            v-if="(r.requesterAvatar ?? r.RequesterAvatar) && isImageAvatar(r.requesterAvatar ?? r.RequesterAvatar)"
            :url="r.requesterAvatar ?? r.RequesterAvatar"
            img-class="avatar-img"
          />
          <span v-else>{{ (r.requesterName ?? r.RequesterName ?? '?')[0]?.toUpperCase() }}</span>
        </div>
        <div class="modern-list-row__body">
          <span class="modern-list-row__title">{{ r.requesterName ?? r.RequesterName }}</span>
          <span v-if="r.requesterUniqueCode ?? r.RequesterUniqueCode" class="modern-list-row__sub">
            {{ r.requesterUniqueCode ?? r.RequesterUniqueCode }}
          </span>
        </div>
        <div class="req-actions">
          <button type="button" class="req-btn req-btn--accept" :disabled="actionId === (r.id ?? r.Id)" @click="accept(r.id ?? r.Id)">
            <Check :size="16" stroke-width="2.5" />
          </button>
          <button type="button" class="req-btn req-btn--decline" :disabled="actionId === (r.id ?? r.Id)" @click="decline(r.id ?? r.Id)">
            <X :size="16" stroke-width="2.5" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.msg-req-panel {
  padding: var(--spacing);
  padding-top: 8px;
}

.msg-req-panel__empty {
  padding: 48px 16px;
  text-align: center;
  color: var(--text-muted);
  font-size: 15px;
}

.outgoing-banner {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 14px 16px;
  margin-bottom: 12px;
  border-radius: var(--radius-lg);
  background: var(--primary-soft);
  color: var(--text-primary);
  font-size: 14px;
}

.outgoing-dismiss {
  border: none;
  background: transparent;
  font-size: 22px;
  line-height: 1;
  cursor: pointer;
  color: var(--text-muted);
}

.req-actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}

.req-btn {
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: none;
  border-radius: 50%;
  cursor: pointer;
}

.req-btn--accept {
  background: rgba(34, 197, 94, 0.15);
  color: var(--success);
}

.req-btn--decline {
  background: rgba(239, 68, 68, 0.12);
  color: var(--danger);
}

.req-btn:disabled {
  opacity: 0.5;
}
</style>
