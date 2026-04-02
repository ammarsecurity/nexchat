<script setup>
import { computed, watch, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { Phone, Check, X, Crown } from 'lucide-vue-next'
import { useMatchingStore } from '../stores/matching'
import { matchingHub, ensureConnected } from '../services/signalr'
import { stopIncomingCallSound } from '../utils/sounds'

const REQUEST_TIMEOUT_MS = 60000

const matching = useMatchingStore()
const { t } = useI18n()
const incomingRequest = computed(() => matching.incomingConnectionRequest)

let expireTimerId = null

function clearExpireTimer() {
  if (expireTimerId) {
    clearTimeout(expireTimerId)
    expireTimerId = null
  }
}

watch(incomingRequest, (request) => {
  clearExpireTimer()
  if (request) {
    expireTimerId = setTimeout(() => {
      expireTimerId = null
      stopIncomingCallSound()
      matching.clearIncomingConnectionRequest()
    }, REQUEST_TIMEOUT_MS)
  }
}, { immediate: true })

onUnmounted(clearExpireTimer)

async function acceptConnectionRequest() {
  if (!incomingRequest.value) return
  const requesterId = incomingRequest.value.requesterId
  clearExpireTimer()
  stopIncomingCallSound()
  matching.clearIncomingConnectionRequest()
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('AcceptConnectionRequest', requesterId)
  } catch {}
}

function declineConnectionRequest() {
  if (!incomingRequest.value) return
  const requesterId = incomingRequest.value.requesterId
  clearExpireTimer()
  stopIncomingCallSound()
  matching.clearIncomingConnectionRequest()
  ensureConnected(matchingHub).then(() => {
    matchingHub.invoke('DeclineConnectionRequest', requesterId).catch(() => {})
  })
}
</script>

<template>
  <Transition name="modal">
    <div v-if="incomingRequest" class="logout-overlay" @click.self="declineConnectionRequest">
      <div class="request-dialog glass-card" :class="{ 'request-dialog-featured': incomingRequest.requesterIsFeatured }">
        <div class="request-dialog-avatar-wrap" :class="{ 'avatar-featured': incomingRequest.requesterIsFeatured }">
          <img v-if="incomingRequest.requesterAvatar && (incomingRequest.requesterAvatar.startsWith('http') || incomingRequest.requesterAvatar.startsWith('/'))" :src="incomingRequest.requesterAvatar" class="requester-avatar-img" referrerpolicy="no-referrer" />
          <span v-else-if="incomingRequest.requesterAvatar" class="requester-avatar-emoji">{{ incomingRequest.requesterAvatar }}</span>
          <span v-else class="requester-avatar-letter">{{ incomingRequest.requesterName?.[0]?.toUpperCase() || '?' }}</span>
          <Crown v-if="incomingRequest.requesterIsFeatured" class="avatar-crown" :size="24" stroke-width="2" />
        </div>
        <h3 class="request-dialog-title">{{ t('incomingRequest.title') }}</h3>
        <p class="request-dialog-text">
          <strong>{{ incomingRequest.requesterName }}</strong>
          <Crown v-if="incomingRequest.requesterIsFeatured" class="inline-crown" :size="14" stroke-width="2" />
          {{ t('incomingRequest.wantsToConnect') }}
        </p>
        <div class="request-dialog-actions">
          <button class="btn-decline" @click="declineConnectionRequest">
            <X :size="20" />
            <span>{{ t('incomingRequest.decline') }}</span>
          </button>
          <button class="btn-accept" @click="acceptConnectionRequest">
            <Check :size="20" />
            <span>{{ t('incomingRequest.accept') }}</span>
          </button>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.logout-overlay {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.5);
  z-index: 9999;
}
.request-dialog {
  margin: var(--spacing);
  max-width: 360px;
  padding: var(--spacing);
  width: 100%;
}
.request-dialog-avatar-wrap {
  position: relative;
  width: 72px;
  height: 72px;
  margin: 0 auto 12px;
  border-radius: 50%;
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.3), rgba(255, 101, 132, 0.2));
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 28px;
  font-weight: 700;
  color: var(--primary);
}
.request-dialog-featured .request-dialog-avatar-wrap {
  padding: 4px;
  background: linear-gradient(135deg, #FFD700, #FFA500);
  box-shadow: 0 0 20px rgba(255, 215, 0, 0.5);
}
.requester-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}
.requester-avatar-emoji { font-size: 36px; }
.requester-avatar-letter { font-size: 28px; }
.avatar-crown {
  position: absolute;
  top: -4px;
  right: -4px;
  color: #FFD700;
  filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3));
}
.inline-crown {
  display: inline-block;
  vertical-align: middle;
  margin-inline-start: 4px;
  color: #FFD700;
}
.request-dialog-title { font-size: 18px; font-weight: 700; margin-bottom: 12px; text-align: center; }
.request-dialog-text {
  font-size: 14px;
  color: var(--text-secondary);
  margin-bottom: 20px;
  text-align: center;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100%;
}
.request-dialog-actions {
  display: flex;
  gap: 12px;
}
.btn-decline {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 48px;
  padding: 0 16px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}
.btn-decline:active { opacity: 0.9; }
.btn-accept {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 48px;
  padding: 0 16px;
  background: var(--primary);
  border: none;
  border-radius: var(--radius-sm);
  color: white;
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}
.btn-accept:active { opacity: 0.9; }

.modal-enter-active, .modal-leave-active { transition: opacity 0.25s; }
.modal-enter-from, .modal-leave-to { opacity: 0; }
</style>
