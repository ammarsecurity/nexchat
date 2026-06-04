<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import {
  X, Globe, UserCircle, UsersRound, ShieldCheck, Sparkles, Lightbulb, Search
} from 'lucide-vue-next'
import BannerStrip from '../components/BannerStrip.vue'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { useMatchingStore } from '../stores/matching'
import { useI18n } from 'vue-i18n'
import { matchingHub, ensureConnected } from '../services/signalr'
import { publicUrl } from '../utils/publicUrl'
import { useReducedMotion } from '../composables/useReducedMotion'

const router = useRouter()
const matching = useMatchingStore()
const { t } = useI18n()
const { reducedMotion } = useReducedMotion()
const dots = ref('.')
const cancelling = ref(false)
let cancelledProgrammatically = false

const filterLabels = computed(() => ({
  all: t('matching.filterAll'),
  male: t('matching.filterMale'),
  female: t('matching.filterFemale')
}))
const filterIcons = { all: Globe, male: UserCircle, female: UsersRound }
const filterStyles = {
  all: { color: 'var(--primary)', bg: 'var(--primary-soft)' },
  male: { color: 'var(--primary)', bg: 'var(--primary-soft)' },
  female: { color: '#DB2777', bg: 'rgba(219, 39, 119, 0.1)' }
}

const tips = computed(() => [
  { key: 'tip1', icon: Sparkles },
  { key: 'tip2', icon: UsersRound },
  { key: 'tip3', icon: Lightbulb }
])

const activeFilterStyle = computed(() => filterStyles[matching.genderFilter] ?? filterStyles.all)

let dotsInterval

onMounted(async () => {
  dotsInterval = setInterval(() => {
    dots.value = dots.value.length >= 3 ? '.' : dots.value + '.'
  }, 500)

  if (matching.consumeResumeSearchAfterNav()) {
    try {
      await ensureConnected(matchingHub)
      await matchingHub.invoke('StartSearching', matching.genderFilter)
    } catch {}
  }
})

onUnmounted(() => {
  clearInterval(dotsInterval)
  if (matching.consumeSkipNextMatchingUnmountCancel()) return
  if (!cancelledProgrammatically) {
    ensureConnected(matchingHub).then(() => matchingHub.invoke('CancelSearching')).catch(() => {})
  }
})

async function cancel() {
  cancelledProgrammatically = true
  cancelling.value = true
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('CancelSearching')
    matching.setIdle()
    router.replace('/home')
  } finally {
    cancelling.value = false
  }
}
</script>

<template>
  <div class="matching page">
    <LoaderOverlay :show="cancelling" :text="t('matching.cancelling')" />

    <header class="match-header">
      <h1 class="match-header__title">{{ t('matching.title') }}</h1>
      <button
        type="button"
        class="match-header__close"
        :disabled="cancelling"
        :aria-label="t('matching.cancelSearch')"
        @click="cancel"
      >
        <X :size="20" stroke-width="2.25" />
      </button>
    </header>

    <div class="match-scroll">
      <section class="match-status" aria-live="polite">
        <div class="match-radar" :class="{ 'match-radar--calm': reducedMotion }">
          <span class="match-radar__wave match-radar__wave--1" aria-hidden="true" />
          <span class="match-radar__wave match-radar__wave--2" aria-hidden="true" />
          <span class="match-radar__wave match-radar__wave--3" aria-hidden="true" />
          <div class="match-radar__core">
            <Vue3Lottie
              v-if="!reducedMotion"
              :animation-link="publicUrl('json/chat.json')"
              :height="44"
              :width="44"
              :speed="0.9"
              :loop="true"
              :auto-play="true"
              class="match-radar__lottie"
            />
            <Search v-else :size="28" stroke-width="2.25" />
          </div>
        </div>

        <p class="match-status__label">
          <span class="match-status__live" aria-hidden="true" />
          {{ t('matching.searching') }}{{ dots }}
        </p>
        <h2 class="match-status__title">{{ t('matching.searchingFor') }}</h2>

        <div class="match-status__meta">
          <div class="match-meta">
            <span class="match-meta__icon match-meta__icon--secure">
              <ShieldCheck :size="18" stroke-width="2.25" />
            </span>
            <span class="match-meta__text">{{ t('matching.secureSearch') }}</span>
          </div>
          <div
            class="match-meta"
            :style="{ '--meta-accent': activeFilterStyle.color, '--meta-bg': activeFilterStyle.bg }"
          >
            <span class="match-meta__icon match-meta__icon--filter">
              <component :is="filterIcons[matching.genderFilter]" :size="18" stroke-width="2.25" />
            </span>
            <span class="match-meta__text">{{ filterLabels[matching.genderFilter] }}</span>
          </div>
        </div>
      </section>

      <section class="match-tips">
        <h3 class="match-tips__title">{{ t('matching.tipsTitle') }}</h3>
        <ul class="match-tips__list">
          <li v-for="tip in tips" :key="tip.key" class="match-tips__row">
            <span class="match-tips__icon">
              <component :is="tip.icon" :size="16" stroke-width="2.25" />
            </span>
            <span>{{ t(`matching.${tip.key}`) }}</span>
          </li>
        </ul>
      </section>

      <div class="match-banners">
        <BannerStrip placement="matching" />
      </div>
    </div>

    <footer class="match-footer">
      <button type="button" class="match-footer__btn" :disabled="cancelling" @click="cancel">
        <X :size="18" stroke-width="2.25" />
        <span>{{ t('matching.cancelSearch') }}</span>
      </button>
    </footer>
  </div>
</template>

<style scoped>
.matching {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
  background: var(--bg-primary);
  font-family: 'Cairo', sans-serif;
}

.match-header {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: calc(var(--safe-top) + 10px) var(--spacing) 12px;
  background: var(--bg-primary);
  z-index: 2;
}

.match-header__title {
  margin: 0;
  color: var(--text-primary);
}

.match-header__close {
  width: 44px;
  height: 44px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  border: none;
  border-radius: 14px;
  background: var(--bg-card);
  color: var(--text-secondary);
  box-shadow: var(--shadow-sm);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.match-header__close:active:not(:disabled) {
  transform: scale(0.96);
  background: var(--bg-card-hover);
}

.match-header__close:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.match-scroll {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  -webkit-overflow-scrolling: touch;
  padding: 0 var(--spacing) 12px;
}

.match-status {
  margin-bottom: 14px;
  padding: 28px 18px 18px;
  border-radius: 24px;
  text-align: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  box-shadow: var(--shadow-sm);
}

.match-radar {
  position: relative;
  width: 132px;
  height: 132px;
  margin: 0 auto 22px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.match-radar__wave {
  position: absolute;
  inset: 0;
  border-radius: 50%;
  border: 2px solid rgba(37, 99, 235, 0.28);
  pointer-events: none;
}

.match-radar__wave--1 {
  animation: match-radar 2.4s ease-out infinite;
}

.match-radar__wave--2 {
  animation: match-radar 2.4s ease-out 0.8s infinite;
}

.match-radar__wave--3 {
  animation: match-radar 2.4s ease-out 1.6s infinite;
}

.match-radar--calm .match-radar__wave {
  animation: none;
  opacity: 0.35;
}

.match-radar__core {
  position: relative;
  z-index: 1;
  width: 72px;
  height: 72px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  background: linear-gradient(145deg, #2563EB 0%, #60A5FA 100%);
  box-shadow: 0 10px 28px rgba(37, 99, 235, 0.32);
}

.match-radar__lottie {
  pointer-events: none;
}

.match-status__label {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  margin: 0 0 8px;
  font-size: 12px;
  font-weight: 800;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--primary);
}

.match-status__live {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #22C55E;
  box-shadow: 0 0 0 4px rgba(34, 197, 94, 0.22);
  animation: match-live 1.3s ease-in-out infinite;
}

.match-radar--calm ~ .match-status__label .match-status__live {
  animation: none;
}

.match-status__title {
  margin: 0 0 20px;
  font-size: 21px;
  font-weight: 800;
  line-height: 1.4;
  color: var(--text-primary);
}

.match-status__meta {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}

.match-meta {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  min-height: 78px;
  padding: 12px 10px;
  border-radius: 16px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
}

.match-meta__icon {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.match-meta__icon--secure {
  background: rgba(34, 197, 94, 0.12);
  color: #16A34A;
}

.match-meta__icon--filter {
  background: var(--meta-bg, var(--primary-soft));
  color: var(--meta-accent, var(--primary));
}

.match-meta__text {
  font-size: 12px;
  font-weight: 700;
  line-height: 1.35;
  color: var(--text-secondary);
  text-align: center;
}

.match-tips {
  margin-bottom: 12px;
  padding: 14px 16px;
  border-radius: var(--radius-lg);
  background: var(--bg-card);
  border: 1px solid var(--border);
  box-shadow: var(--shadow-sm);
}

.match-tips__title {
  margin: 0 0 10px;
  font-size: 14px;
  font-weight: 800;
  color: var(--text-primary);
}

.match-tips__list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.match-tips__row {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  font-size: 13px;
  line-height: 1.45;
  color: var(--text-secondary);
}

.match-tips__icon {
  flex-shrink: 0;
  width: 32px;
  height: 32px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--primary-soft);
  color: var(--primary);
}

.match-banners :deep(.banner-strip) {
  width: 100%;
  margin-inline: 0;
  margin-block: 0;
}

.match-footer {
  flex-shrink: 0;
  padding: 10px var(--spacing) calc(10px + var(--safe-bottom));
  background: var(--bg-primary);
  border-top: 1px solid var(--border);
  box-shadow: 0 -4px 20px rgba(15, 23, 42, 0.06);
}

.match-footer__btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
  min-height: 52px;
  border: 1px solid var(--border);
  border-radius: 14px;
  background: var(--bg-card);
  color: var(--text-secondary);
  font-family: 'Cairo', sans-serif;
  font-size: 15px;
  font-weight: 700;
  cursor: pointer;
  box-shadow: var(--shadow-sm);
  -webkit-tap-highlight-color: transparent;
}

.match-footer__btn:active:not(:disabled) {
  color: var(--danger);
  border-color: rgba(239, 68, 68, 0.3);
  background: rgba(239, 68, 68, 0.06);
}

.match-footer__btn:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}

@keyframes match-radar {
  0% { transform: scale(0.55); opacity: 0.85; }
  100% { transform: scale(1); opacity: 0; }
}

@keyframes match-live {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.45; }
}

@media (prefers-reduced-motion: reduce) {
  .match-radar__wave,
  .match-status__live {
    animation: none !important;
  }
}
</style>
