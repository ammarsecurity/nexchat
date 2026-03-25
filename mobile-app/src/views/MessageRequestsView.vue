<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronRight, Check, X } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import CachedAvatar from '../components/CachedAvatar.vue'
import { useMessageRequestsStore } from '../stores/messageRequests'

const route = useRoute()
const router = useRouter()
const { t } = useI18n()
const msgReqStore = useMessageRequestsStore()

const loading = ref(true)
const list = ref([])
const actionId = ref(null)

/** شريط طلب صادر: يُعرض بعد التوجيه من جهات الاتصال / الملف الشخصي / المشاركة */
const outgoingBannerKind = ref(null)

const outgoingBannerText = computed(() => {
  if (outgoingBannerKind.value === 'share') return t('messageRequests.waitingForAcceptCannotShare')
  if (outgoingBannerKind.value === 'wait') return t('messageRequests.waitingForAcceptFromOther')
  return ''
})

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
    window.alert(m)
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
    window.alert(m)
  } finally {
    actionId.value = null
  }
}

function goBack() {
  if (window.history.length > 2) router.back()
  else router.replace('/conversations')
}

onMounted(async () => {
  const n = route.query.notice
  if (n === 'outgoing-wait') outgoingBannerKind.value = 'wait'
  else if (n === 'outgoing-share-wait') outgoingBannerKind.value = 'share'
  if (outgoingBannerKind.value) {
    router.replace({ path: '/message-requests' })
  }
  await fetchList()
})
</script>

<template>
  <div class="message-requests page auth-pattern">
    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.back')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('messageRequests.title') }}</span>
      <span class="top-placeholder" aria-hidden="true"></span>
    </header>

    <div class="scroll-area">
      <div v-if="outgoingBannerText" class="outgoing-banner glass-card" role="status">
        <p class="outgoing-banner-text">{{ outgoingBannerText }}</p>
        <button type="button" class="outgoing-banner-dismiss" :aria-label="t('common.cancel')" @click="dismissOutgoingBanner">
          ×
        </button>
      </div>
      <div v-if="loading" class="loading-msg">{{ t('common.loading') }}</div>
      <div v-else-if="!list.length" class="empty-state">
        <p>{{ t('messageRequests.empty') }}</p>
      </div>
      <ul v-else class="req-list">
        <li v-for="r in list" :key="r.id ?? r.Id" class="req-card glass-card">
          <div class="req-avatar">
            <div
              v-if="(r.requesterAvatar ?? r.RequesterAvatar) && isImageAvatar(r.requesterAvatar ?? r.RequesterAvatar)"
              class="avatar-img-wrap"
            >
              <CachedAvatar :url="r.requesterAvatar ?? r.RequesterAvatar" img-class="avatar-img" />
            </div>
            <div v-else class="avatar-letter">
              {{ (r.requesterName ?? r.RequesterName ?? '?')[0]?.toUpperCase() }}
            </div>
          </div>
          <div class="req-body">
            <div class="req-name">{{ r.requesterName ?? r.RequesterName }}</div>
            <div v-if="r.requesterUniqueCode ?? r.RequesterUniqueCode" class="req-code">
              {{ r.requesterUniqueCode ?? r.RequesterUniqueCode }}
            </div>
          </div>
          <div class="req-actions">
            <button
              type="button"
              class="btn-accept"
              :disabled="actionId === (r.id ?? r.Id)"
              :aria-label="t('messageRequests.accept')"
              @click="accept(r.id ?? r.Id)"
            >
              <Check :size="16" stroke-width="2.5" />
            </button>
            <button
              type="button"
              class="btn-decline"
              :disabled="actionId === (r.id ?? r.Id)"
              :aria-label="t('messageRequests.decline')"
              @click="decline(r.id ?? r.Id)"
            >
              <X :size="16" stroke-width="2.5" />
            </button>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>

<style scoped>
.message-requests {
  background: var(--bg-primary);
  min-height: 100vh;
  min-height: 100dvh;
  display: flex;
  flex-direction: column;
  font-family: 'Cairo', sans-serif;
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
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
}

.top-title {
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
}

.top-placeholder {
  width: 40px;
}

.scroll-area {
  flex: 1;
  overflow-y: auto;
  padding: 0 20px 32px;
  max-width: 400px;
  margin: 0 auto;
  width: 100%;
}

.outgoing-banner {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 14px 16px;
  margin-bottom: 16px;
  border-radius: 14px;
  background: rgba(108, 99, 255, 0.1);
  border: 1px solid rgba(108, 99, 255, 0.28);
}

.outgoing-banner-text {
  margin: 0;
  flex: 1;
  font-size: 14px;
  line-height: 1.55;
  color: var(--text-primary);
  text-align: start;
}

.outgoing-banner-dismiss {
  flex-shrink: 0;
  width: 32px;
  height: 32px;
  border: none;
  border-radius: 8px;
  background: transparent;
  color: var(--text-tertiary);
  font-size: 22px;
  line-height: 1;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.outgoing-banner-dismiss:active {
  background: rgba(0, 0, 0, 0.06);
}

.loading-msg,
.empty-state {
  padding: 48px 16px;
  text-align: center;
  color: var(--text-muted);
}

.req-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.req-card {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  border-radius: 10px;
}

.req-avatar {
  flex-shrink: 0;
}

.avatar-img-wrap {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  overflow: hidden;
}

.avatar-img-wrap :deep(.avatar-img) {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.avatar-letter {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: var(--primary);
  color: white;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 14px;
}

.req-body {
  flex: 1;
  min-width: 0;
}

.req-name {
  font-weight: 600;
  color: var(--text-primary);
  font-size: 14px;
  line-height: 1.25;
}

.req-code {
  font-size: 11px;
  color: var(--text-tertiary);
  margin-top: 1px;
  letter-spacing: 0.02em;
}

.req-actions {
  display: flex;
  gap: 6px;
  flex-shrink: 0;
}

.btn-accept,
.btn-decline {
  width: 32px;
  height: 32px;
  border: none;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}

.btn-accept {
  background: rgba(34, 197, 94, 0.15);
  color: #16a34a;
}

.btn-decline {
  background: rgba(239, 68, 68, 0.12);
  color: var(--danger);
}

.btn-accept:disabled,
.btn-decline:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
