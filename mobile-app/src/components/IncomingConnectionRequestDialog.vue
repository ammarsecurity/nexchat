<script setup>
import { computed, watch, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { Check, X, Crown } from 'lucide-vue-next'
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
  <Transition name="req-modal">
    <div v-if="incomingRequest" class="req-overlay" @click.self="declineConnectionRequest">
      <div class="req-sheet" :class="{ 'req-sheet--featured': incomingRequest.requesterIsFeatured }">
        <div class="req-sheet__handle" aria-hidden="true" />

        <div class="req-avatar-wrap" :class="{ 'req-avatar-wrap--featured': incomingRequest.requesterIsFeatured }">
          <img
            v-if="incomingRequest.requesterAvatar && (incomingRequest.requesterAvatar.startsWith('http') || incomingRequest.requesterAvatar.startsWith('/'))"
            :src="incomingRequest.requesterAvatar"
            class="req-avatar-img"
            referrerpolicy="no-referrer"
            alt=""
          />
          <span v-else-if="incomingRequest.requesterAvatar" class="req-avatar-emoji">{{ incomingRequest.requesterAvatar }}</span>
          <span v-else class="req-avatar-letter">{{ incomingRequest.requesterName?.[0]?.toUpperCase() || '?' }}</span>
          <Crown v-if="incomingRequest.requesterIsFeatured" class="req-crown" :size="22" stroke-width="2" />
        </div>

        <h3 class="req-title">{{ t('incomingRequest.title') }}</h3>
        <p class="req-text">
          <strong>{{ incomingRequest.requesterName }}</strong>
          <Crown v-if="incomingRequest.requesterIsFeatured" class="inline-crown" :size="14" stroke-width="2" />
          {{ t('incomingRequest.wantsToConnect') }}
        </p>

        <div class="req-actions">
          <button type="button" class="req-btn req-btn--decline" @click="declineConnectionRequest">
            <X :size="20" stroke-width="2.25" />
            <span>{{ t('incomingRequest.decline') }}</span>
          </button>
          <button type="button" class="req-btn req-btn--accept" @click="acceptConnectionRequest">
            <Check :size="20" stroke-width="2.25" />
            <span>{{ t('incomingRequest.accept') }}</span>
          </button>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.req-overlay {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  background: rgba(15, 23, 42, 0.55);
  backdrop-filter: blur(4px);
  z-index: 9999;
}

.req-sheet {
  width: 100%;
  max-width: min(var(--app-max-width, 100%), 480px);
  padding: 10px var(--spacing) calc(var(--spacing) + var(--safe-bottom));
  border-radius: 24px 24px 0 0;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-bottom: none;
  box-shadow: 0 -12px 40px rgba(15, 23, 42, 0.18);
  font-family: 'Cairo', sans-serif;
}

.req-sheet--featured {
  box-shadow: 0 -12px 40px rgba(15, 23, 42, 0.18), inset 0 1px 0 rgba(250, 204, 21, 0.35);
}

.req-sheet__handle {
  width: 40px;
  height: 4px;
  margin: 0 auto 16px;
  border-radius: 999px;
  background: var(--text-tertiary);
  opacity: 0.45;
}

.req-avatar-wrap {
  position: relative;
  width: 84px;
  height: 84px;
  margin: 0 auto 14px;
  border-radius: 50%;
  background: linear-gradient(145deg, rgba(37, 99, 235, 0.2), rgba(96, 165, 250, 0.35));
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 32px;
  font-weight: 700;
  color: var(--primary);
  box-shadow: 0 0 0 3px var(--bg-card), 0 0 0 5px rgba(37, 99, 235, 0.25);
}

.req-avatar-wrap--featured {
  background: linear-gradient(145deg, rgba(250, 204, 21, 0.35), rgba(251, 191, 36, 0.2));
  box-shadow: 0 0 0 3px var(--bg-card), 0 0 0 5px rgba(250, 204, 21, 0.55);
}

.req-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}

.req-avatar-emoji {
  font-size: 38px;
}

.req-avatar-letter {
  font-size: 32px;
}

.req-crown {
  position: absolute;
  top: -4px;
  inset-inline-end: -4px;
  color: #FFD700;
  filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.3));
}

.inline-crown {
  display: inline-block;
  vertical-align: middle;
  margin-inline-start: 4px;
  color: #FFD700;
}

.req-title {
  font-size: 18px;
  font-weight: 800;
  margin: 0 0 8px;
  text-align: center;
  color: var(--text-primary);
}

.req-text {
  font-size: 14px;
  color: var(--text-secondary);
  margin: 0 0 20px;
  text-align: center;
  line-height: 1.45;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100%;
}

.req-actions {
  display: flex;
  gap: 10px;
}

.req-btn {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 50px;
  padding: 0 16px;
  border-radius: 14px;
  font-size: 15px;
  font-weight: 700;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.12s ease, opacity 0.12s ease;
}

.req-btn:active {
  transform: scale(0.98);
}

.req-btn--decline {
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  color: var(--text-secondary);
}

.req-btn--accept {
  background: linear-gradient(135deg, #2563EB, #60A5FA);
  border: none;
  color: #fff;
  box-shadow: 0 6px 18px rgba(37, 99, 235, 0.35);
}

.req-modal-enter-active,
.req-modal-leave-active {
  transition: opacity 0.25s ease;
}

.req-modal-enter-active .req-sheet,
.req-modal-leave-active .req-sheet {
  transition: transform 0.28s cubic-bezier(0.32, 0.72, 0, 1);
}

.req-modal-enter-from,
.req-modal-leave-to {
  opacity: 0;
}

.req-modal-enter-from .req-sheet,
.req-modal-leave-to .req-sheet {
  transform: translateY(100%);
}
</style>
