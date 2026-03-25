<script setup>
import { computed, watch, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { Check, X } from 'lucide-vue-next'
import CachedAvatar from './CachedAvatar.vue'
import { useIncomingConversationCallStore } from '../stores/incomingConversationCall'
import { useActiveCallStore } from '../stores/activeCall'
import { conversationHub, ensureConnected } from '../services/signalr'
import { startIncomingCallSound, stopIncomingCallSound } from '../utils/sounds'

const RING_TIMEOUT_MS = 120000

const { t } = useI18n()
const router = useRouter()
const store = useIncomingConversationCallStore()
const activeCall = useActiveCallStore()

const visible = computed(() => store.visible)
const callerName = computed(() => store.callerName || '…')
const voiceOnly = computed(() => store.voiceOnly)

const avatarIsHttp = computed(() => {
  const a = store.callerAvatar
  return typeof a === 'string' && (a.startsWith('http') || a.startsWith('/'))
})

const callerLetter = computed(() => (callerName.value?.[0] || '?').toUpperCase())

let expireTimerId = null

function clearExpireTimer() {
  if (expireTimerId) {
    clearTimeout(expireTimerId)
    expireTimerId = null
  }
}

watch(visible, (v) => {
  clearExpireTimer()
  if (v) {
    startIncomingCallSound()
    expireTimerId = setTimeout(() => {
      expireTimerId = null
      stopIncomingCallSound()
      store.clear()
    }, RING_TIMEOUT_MS)
  } else {
    stopIncomingCallSound()
  }
})

onUnmounted(() => {
  clearExpireTimer()
  stopIncomingCallSound()
})

async function accept() {
  const id = store.conversationId
  const vo = store.voiceOnly
  const name = store.callerName
  const avatar = store.callerAvatar
  if (!id) return
  clearExpireTimer()
  stopIncomingCallSound()
  store.clear()
  try {
    await ensureConnected(conversationHub)
    await conversationHub.invoke('AcceptVideoCall', id)
  } catch {
    return
  }
  activeCall.syncMeta({
    sessionId: id,
    voiceOnly: vo,
    isConversation: true,
    partnerName: name,
    partnerAvatar: avatar
  })
  router.push({
    path: `/video/${id}`,
    state: { initiator: false, voiceOnly: vo, fromConversation: true }
  })
}

function decline() {
  const id = store.conversationId
  if (!id) return
  clearExpireTimer()
  stopIncomingCallSound()
  store.clear()
  ensureConnected(conversationHub).then(() => {
    conversationHub.invoke('DeclineVideoCall', id).catch(() => {})
  })
}
</script>

<template>
  <Transition name="modal">
    <div v-if="visible" class="conv-call-overlay" @click.self="decline">
      <div class="conv-call-dialog glass-card">
        <div class="conv-call-avatar-wrap">
          <CachedAvatar
            v-if="avatarIsHttp"
            :url="store.callerAvatar"
            img-class="conv-call-avatar-img"
          />
          <span v-else-if="store.callerAvatar && store.callerAvatar.length <= 4" class="conv-call-emoji">{{ store.callerAvatar }}</span>
          <span v-else class="conv-call-letter">{{ callerLetter }}</span>
        </div>
        <h3 class="conv-call-title">{{ callerName }}</h3>
        <p class="conv-call-label">
          {{ voiceOnly ? t('conversationChat.incomingVoiceCall') : t('conversationChat.incomingVideoCall') }}
        </p>
        <div class="conv-call-actions">
          <button type="button" class="btn-decline" @click="decline">
            <X :size="20" />
            <span>{{ t('incomingRequest.decline') }}</span>
          </button>
          <button type="button" class="btn-accept" @click="accept">
            <Check :size="20" />
            <span>{{ t('incomingRequest.accept') }}</span>
          </button>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.conv-call-overlay {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.55);
  z-index: 10000;
  padding: var(--spacing);
}
.conv-call-dialog {
  max-width: 360px;
  width: 100%;
  padding: var(--spacing-lg);
}
.conv-call-avatar-wrap {
  width: 72px;
  height: 72px;
  margin: 0 auto 12px;
  border-radius: 50%;
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.35), rgba(255, 101, 132, 0.2));
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 28px;
  font-weight: 700;
  color: var(--primary);
  overflow: hidden;
}
.conv-call-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}
.conv-call-emoji {
  font-size: 36px;
  line-height: 1;
}
.conv-call-letter {
  font-size: 28px;
}
.conv-call-title {
  font-size: 17px;
  font-weight: 700;
  text-align: center;
  margin-bottom: 8px;
  font-family: 'Cairo', sans-serif;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.conv-call-label {
  font-size: 14px;
  color: var(--text-secondary);
  text-align: center;
  margin-bottom: 20px;
  font-family: 'Cairo', sans-serif;
}
.conv-call-actions {
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
  -webkit-tap-highlight-color: transparent;
}
.btn-decline:active {
  opacity: 0.92;
}
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
  -webkit-tap-highlight-color: transparent;
}
.btn-accept:active {
  opacity: 0.92;
}
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.25s;
}
.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}
</style>
