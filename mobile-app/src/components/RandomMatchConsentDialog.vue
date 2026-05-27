<script setup>
import { ref, computed, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { Check, X, SkipForward, Crown, Loader2, LogOut } from 'lucide-vue-next'
import { useMatchingStore } from '../stores/matching'
import { matchingHub, ensureConnected } from '../services/signalr'
import { ensureAbsoluteUrl } from '../utils/imageUrl'

const matching = useMatchingStore()
const { t } = useI18n()

const pending = computed(() => matching.pendingRandomMatch)
const waitingPeer = ref(false)
const acting = ref(false)

const partner = computed(() => pending.value?.partner)

const sessionId = computed(() =>
  pending.value?.sessionId
)

const partnerIsFeatured = computed(() => partner.value?.isFeatured ?? partner.value?.IsFeatured ?? false)

const avatarIsImage = computed(() => {
  const a = partner.value?.avatar
  return a && (a.startsWith('http') || a.startsWith('/'))
})

const avatarIsEmoji = computed(() => partner.value?.avatar && !avatarIsImage.value)

const nameLetter = computed(() => partner.value?.name?.[0]?.toUpperCase() || '?')

watch(pending, (v) => {
  if (!v) waitingPeer.value = false
})

async function accept() {
  if (!sessionId.value || acting.value) return
  acting.value = true
  waitingPeer.value = true
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('AcceptRandomMatch', sessionId.value)
  } catch {
    waitingPeer.value = false
  } finally {
    acting.value = false
  }
}

async function declineOrSkip() {
  if (!sessionId.value || acting.value) return
  acting.value = true
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('DeclineRandomMatch', sessionId.value)
  } finally {
    acting.value = false
  }
}

async function exitRandomChat() {
  if (!sessionId.value || acting.value) return
  acting.value = true
  matching.armSkipRestartAfterRandomDecline()
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('DeclineRandomMatch', sessionId.value)
  } catch {
    matching.consumeSkipRestartAfterRandomDecline()
  } finally {
    acting.value = false
  }
}
</script>

<template>
  <Transition name="rm-modal">
    <div v-if="pending" class="rm-overlay" @click.self="declineOrSkip">
      <div class="rm-sheet" :class="{ 'rm-sheet--featured': partnerIsFeatured }">
        <div class="rm-sheet__handle" aria-hidden="true" />

        <p class="rm-hint">{{ t('randomMatch.hint') }}</p>

        <div class="rm-avatar-wrap" :class="{ 'rm-avatar-wrap--featured': partnerIsFeatured }">
          <template v-if="partner">
            <img
              v-if="avatarIsImage"
              :src="ensureAbsoluteUrl(partner.avatar)"
              class="rm-avatar-img"
              referrerpolicy="no-referrer"
              alt=""
            />
            <span v-else-if="avatarIsEmoji" class="rm-avatar-emoji">{{ partner.avatar }}</span>
            <span v-else class="rm-letter">{{ nameLetter }}</span>
            <Crown v-if="partnerIsFeatured" class="rm-crown" :size="20" stroke-width="2" />
          </template>
        </div>

        <h3 class="rm-name">
          {{ partner?.name || '…' }}
          <Crown v-if="partnerIsFeatured" class="inline-crown" :size="14" stroke-width="2" />
        </h3>
        <p v-if="partner?.uniqueCode || partner?.UniqueCode" class="rm-code">
          {{ t('randomMatch.publicId') }}: {{ partner?.uniqueCode ?? partner?.UniqueCode }}
        </p>

        <p v-if="waitingPeer" class="rm-wait">
          <Loader2 :size="18" class="spin" />
          {{ t('randomMatch.waitingPeer') }}
        </p>

        <div class="rm-actions">
          <button type="button" class="rm-btn rm-btn--accept" :disabled="acting || waitingPeer" @click="accept">
            <Check :size="18" stroke-width="2.5" />
            <span>{{ t('randomMatch.accept') }}</span>
          </button>
          <div class="rm-actions__row">
            <button type="button" class="rm-btn rm-btn--ghost" :disabled="acting" @click="declineOrSkip">
              <SkipForward :size="17" stroke-width="2.25" />
              <span>{{ t('randomMatch.skip') }}</span>
            </button>
            <button type="button" class="rm-btn rm-btn--outline" :disabled="acting" @click="declineOrSkip">
              <X :size="17" stroke-width="2.25" />
              <span>{{ t('randomMatch.decline') }}</span>
            </button>
          </div>
        </div>

        <button type="button" class="rm-exit" :disabled="acting" @click="exitRandomChat">
          <LogOut :size="17" stroke-width="2.25" />
          <span>{{ t('randomMatch.exitRandom') }}</span>
        </button>

        <p class="rm-legal">{{ t('randomMatch.legalHint') }}</p>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.rm-overlay {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  background: rgba(15, 23, 42, 0.55);
  backdrop-filter: blur(4px);
  z-index: 10000;
  padding: 0;
}

.rm-sheet {
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

.rm-sheet--featured {
  box-shadow: 0 -12px 40px rgba(15, 23, 42, 0.18), inset 0 1px 0 rgba(250, 204, 21, 0.35);
}

.rm-sheet__handle {
  width: 40px;
  height: 4px;
  margin: 0 auto 14px;
  border-radius: 999px;
  background: var(--text-tertiary);
  opacity: 0.45;
}

.rm-hint {
  font-size: 13px;
  color: var(--text-secondary);
  text-align: center;
  margin: 0 0 16px;
  line-height: 1.5;
}

.rm-avatar-wrap {
  position: relative;
  width: 88px;
  height: 88px;
  margin: 0 auto 12px;
  border-radius: 50%;
  background: linear-gradient(145deg, rgba(37, 99, 235, 0.2), rgba(96, 165, 250, 0.35));
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 34px;
  font-weight: 700;
  color: var(--primary);
  box-shadow: 0 0 0 3px var(--bg-card), 0 0 0 5px rgba(37, 99, 235, 0.25);
}

.rm-avatar-wrap--featured {
  box-shadow: 0 0 0 3px var(--bg-card), 0 0 0 5px rgba(250, 204, 21, 0.55);
}

.rm-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}

.rm-avatar-emoji {
  font-size: 38px;
  line-height: 1;
}

.rm-crown {
  position: absolute;
  bottom: -2px;
  inset-inline-end: -2px;
  color: #facc15;
  filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.35));
}

.inline-crown {
  display: inline-block;
  vertical-align: middle;
  color: #facc15;
  margin-inline-start: 4px;
}

.rm-name {
  text-align: center;
  font-size: 20px;
  font-weight: 800;
  margin: 0 0 4px;
  color: var(--text-primary);
}

.rm-code {
  text-align: center;
  font-size: 13px;
  color: var(--text-secondary);
  margin: 0 0 14px;
  font-variant-numeric: tabular-nums;
}

.rm-wait {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  font-size: 14px;
  color: var(--text-secondary);
  margin: 0 0 14px;
}

.spin {
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.rm-actions {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.rm-actions__row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}

.rm-btn {
  min-height: 48px;
  border-radius: 14px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  font-family: 'Cairo', sans-serif;
  font-size: 15px;
  font-weight: 700;
  cursor: pointer;
  border: none;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.12s ease, opacity 0.12s ease;
}

.rm-btn:active:not(:disabled) {
  transform: scale(0.98);
}

.rm-btn:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.rm-btn--accept {
  width: 100%;
  background: linear-gradient(135deg, #2563EB, #60A5FA);
  color: #fff;
  box-shadow: 0 6px 18px rgba(37, 99, 235, 0.35);
}

.rm-btn--ghost {
  background: var(--primary-soft);
  color: var(--primary);
}

.rm-btn--outline {
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  color: var(--text-secondary);
}

.rm-exit {
  width: 100%;
  margin-top: 10px;
  min-height: 46px;
  border-radius: 14px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
  font-weight: 700;
  cursor: pointer;
  border: 1px solid rgba(37, 99, 235, 0.28);
  background: rgba(37, 99, 235, 0.08);
  color: var(--primary);
  -webkit-tap-highlight-color: transparent;
}

.rm-exit:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.rm-exit:active:not(:disabled) {
  background: rgba(37, 99, 235, 0.14);
}

.rm-legal {
  margin: 14px 0 0;
  text-align: center;
  line-height: 1.45;
  font-size: 12px;
  color: var(--text-tertiary);
}

.rm-modal-enter-active,
.rm-modal-leave-active {
  transition: opacity 0.25s ease;
}

.rm-modal-enter-active .rm-sheet,
.rm-modal-leave-active .rm-sheet {
  transition: transform 0.28s cubic-bezier(0.32, 0.72, 0, 1);
}

.rm-modal-enter-from,
.rm-modal-leave-to {
  opacity: 0;
}

.rm-modal-enter-from .rm-sheet,
.rm-modal-leave-to .rm-sheet {
  transform: translateY(100%);
}
</style>
