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

/** رفض المطابقة والخروج من وضع البحث العشوائي (بدون إعادة StartSearching) */
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
  <Transition name="modal">
    <div v-if="pending" class="rm-overlay" @click.self="declineOrSkip">
      <div class="rm-dialog glass-card" :class="{ 'rm-featured': partnerIsFeatured }">
        <p class="rm-hint">{{ t('randomMatch.hint') }}</p>
        <div class="rm-avatar-wrap" :class="{ 'avatar-featured': partnerIsFeatured }">
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
            <Crown v-if="partnerIsFeatured" class="rm-crown" :size="22" stroke-width="2" />
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
          <button type="button" class="btn-skip" :disabled="acting" @click="declineOrSkip">
            <SkipForward :size="18" />
            <span>{{ t('randomMatch.skip') }}</span>
          </button>
          <button type="button" class="btn-decline" :disabled="acting" @click="declineOrSkip">
            <X :size="18" />
            <span>{{ t('randomMatch.decline') }}</span>
          </button>
          <button type="button" class="btn-accept" :disabled="acting || waitingPeer" @click="accept">
            <Check :size="18" />
            <span>{{ t('randomMatch.accept') }}</span>
          </button>
        </div>
        <button
          type="button"
          class="btn-exit-random"
          :disabled="acting"
          @click="exitRandomChat"
        >
          <LogOut :size="18" />
          <span>{{ t('randomMatch.exitRandom') }}</span>
        </button>
        <p class="rm-legal text-muted text-sm">{{ t('randomMatch.legalHint') }}</p>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.rm-overlay {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.55);
  z-index: 10000;
  padding: var(--spacing);
}

.rm-dialog {
  width: 100%;
  max-width: 380px;
  padding: calc(var(--spacing) + 4px);
  border-radius: var(--radius, 16px);
  font-family: 'Cairo', system-ui, sans-serif;
}

.rm-hint {
  font-size: 13px;
  color: var(--text-secondary);
  text-align: center;
  margin: 0 0 12px;
  line-height: 1.45;
}

.rm-avatar-wrap {
  position: relative;
  width: 80px;
  height: 80px;
  margin: 0 auto 10px;
  border-radius: 50%;
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.35), rgba(255, 101, 132, 0.25));
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 32px;
  font-weight: 700;
  color: var(--primary);
}

.rm-avatar-wrap.avatar-featured {
  box-shadow: 0 0 0 2px rgba(250, 204, 21, 0.6);
}

.rm-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}

.rm-avatar-emoji {
  font-size: 36px;
  line-height: 1;
}

.rm-crown {
  position: absolute;
  bottom: -4px;
  right: -4px;
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
  font-size: 18px;
  font-weight: 600;
  margin: 0 0 6px;
}

.rm-code {
  text-align: center;
  font-size: 13px;
  color: var(--text-secondary);
  margin: 0 0 12px;
  font-variant-numeric: tabular-nums;
}

.rm-wait {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  font-size: 14px;
  color: var(--text-secondary);
  margin: 0 0 12px;
}

.spin {
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.rm-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  justify-content: center;
}

.rm-actions button {
  flex: 1 1 calc(33% - 8px);
  min-height: var(--touch-min, 44px);
  border-radius: 12px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  font-family: 'Cairo', system-ui, sans-serif;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  border: none;
  -webkit-tap-highlight-color: transparent;
}

.btn-accept {
  background: linear-gradient(135deg, var(--primary), #8b5cf6);
  color: #fff;
}

.btn-decline {
  background: var(--bg-card);
  border: 1px solid var(--border) !important;
  color: var(--text-secondary);
}

.btn-skip {
  background: rgba(108, 99, 255, 0.12);
  color: var(--primary);
}

.btn-exit-random {
  width: 100%;
  margin-top: 10px;
  min-height: var(--touch-min, 44px);
  border-radius: 12px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  font-family: 'Cairo', system-ui, sans-serif;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  border: 1px solid rgba(108, 99, 255, 0.4);
  background: linear-gradient(
    180deg,
    rgba(108, 99, 255, 0.22) 0%,
    rgba(108, 99, 255, 0.12) 100%
  );
  color: var(--primary);
  box-shadow: 0 1px 0 rgba(255, 255, 255, 0.06) inset, 0 2px 12px rgba(108, 99, 255, 0.2);
  transition: background 0.15s, box-shadow 0.15s, border-color 0.15s;
  -webkit-tap-highlight-color: transparent;
}
.btn-exit-random:disabled {
  opacity: 0.55;
  cursor: not-allowed;
  box-shadow: none;
}
.btn-exit-random:not(:disabled):hover {
  border-color: rgba(108, 99, 255, 0.55);
  background: linear-gradient(
    180deg,
    rgba(108, 99, 255, 0.3) 0%,
    rgba(108, 99, 255, 0.16) 100%
  );
}
.btn-exit-random:not(:disabled):active {
  background: linear-gradient(
    180deg,
    rgba(108, 99, 255, 0.2) 0%,
    rgba(108, 99, 255, 0.1) 100%
  );
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.2) inset;
}

.rm-actions button:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

.rm-legal {
  margin: 14px 0 0;
  text-align: center;
  line-height: 1.4;
}

.rm-featured.rm-dialog {
  box-shadow: 0 0 0 1px rgba(250, 204, 21, 0.25);
}
</style>
