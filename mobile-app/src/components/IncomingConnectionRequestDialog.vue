<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { Phone, Check, X } from 'lucide-vue-next'
import { useMatchingStore } from '../stores/matching'
import { matchingHub, ensureConnected } from '../services/signalr'
import { stopIncomingCallSound } from '../utils/sounds'

const matching = useMatchingStore()
const { t } = useI18n()
const incomingRequest = computed(() => matching.incomingConnectionRequest)

async function acceptConnectionRequest() {
  if (!incomingRequest.value) return
  const requesterId = incomingRequest.value.requesterId
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
      <div class="request-dialog glass-card">
        <div class="request-dialog-icon"><Phone :size="48" stroke-width="2" /></div>
        <h3 class="request-dialog-title">{{ t('incomingRequest.title') }}</h3>
        <p class="request-dialog-text">
          <strong>{{ incomingRequest.requesterName }}</strong> {{ t('incomingRequest.wantsToConnect') }}
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
.request-dialog-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary);
  margin-bottom: 8px;
}
.request-dialog-title { font-size: 18px; font-weight: 700; margin-bottom: 12px; text-align: center; }
.request-dialog-text { font-size: 14px; color: var(--text-secondary); margin-bottom: 20px; text-align: center; }
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
