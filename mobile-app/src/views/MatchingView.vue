<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { X, Globe, UserCircle, UsersRound, Users } from 'lucide-vue-next'
import BannerStrip from '../components/BannerStrip.vue'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { useMatchingStore } from '../stores/matching'
import { useI18n } from 'vue-i18n'
import { matchingHub, ensureConnected } from '../services/signalr'
import { publicUrl } from '../utils/publicUrl'

const router = useRouter()
const matching = useMatchingStore()
const { t } = useI18n()
const dots = ref('.')
const cancelling = ref(false)
const onlineCount = ref(Math.floor(Math.random() * 200) + 50)
let cancelledProgrammatically = false

const filterLabels = computed(() => ({ all: t('matching.filterAll'), male: t('matching.filterMale'), female: t('matching.filterFemale') }))
const filterIcons = { all: Globe, male: UserCircle, female: UsersRound }
const filterStyles = {
  all: { color: '#7C75FF', bg: 'rgba(124, 117, 255, 0.15)' },
  male: { color: '#3B82F6', bg: 'rgba(59, 130, 246, 0.15)' },
  female: { color: '#EC4899', bg: 'rgba(236, 72, 153, 0.15)' }
}

let dotsInterval
let onlineInterval

onMounted(() => {
  dotsInterval = setInterval(() => {
    dots.value = dots.value.length >= 3 ? '.' : dots.value + '.'
  }, 500)
  onlineInterval = setInterval(() => {
    onlineCount.value = Math.max(20, onlineCount.value + Math.floor(Math.random() * 6) - 3)
  }, 5000)
})

onUnmounted(() => {
  clearInterval(dotsInterval)
  clearInterval(onlineInterval)
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
    <div class="chat-pattern" aria-hidden="true"></div>

    <!-- Header -->
    <header class="matching-header">
      <h1 class="matching-title">{{ t('matching.title') }}</h1>
      <button class="cancel-header-btn" :disabled="cancelling" @click="cancel" :aria-label="t('common.cancel')">
        <X :size="22" stroke-width="2" />
      </button>
    </header>

    <div class="content">
      <!-- Search visual -->
      <section class="search-section">
        <div class="search-visual">
          <Vue3Lottie
            :animation-link="publicUrl('json/world-map-searching.json')"
            width="100%"
            height="100%"
            :speed="0.8"
            :loop="true"
            :auto-play="true"
            class="search-visual-lottie"
          />
        </div>
        <div class="search-text">
          <h2 class="search-heading">{{ t('matching.searching') }}{{ dots }}</h2>
          <p class="search-sub">{{ t('matching.searchingFor') }}</p>
          <div class="badges-row">
            <div class="online-badge">
              <Users :size="14" stroke-width="2" />
              <span class="online-count">{{ onlineCount }}</span>
              <span class="online-label">{{ t('home.onlineNow') }}</span>
            </div>
            <div class="filter-badge" :style="{ '--filter-color': filterStyles[matching.genderFilter].color }">
              <component :is="filterIcons[matching.genderFilter]" :size="14" stroke-width="2" />
              <span class="filter-val">{{ filterLabels[matching.genderFilter] }}</span>
            </div>
          </div>
        </div>
      </section>

      <!-- Banner Slider -->
      <BannerStrip placement="matching" />

      <!-- Cancel CTA -->
      <button class="cancel-btn" :disabled="cancelling" @click="cancel">
        <X :size="18" stroke-width="2" />
        <span>{{ t('matching.cancelSearch') }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.matching {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  min-height: 100%;
  overflow-y: auto;
  padding: 0;
  position: relative;
  -webkit-overflow-scrolling: touch;
}

.chat-pattern {
  position: absolute;
  inset: 0;
  opacity: 0.08;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='64' height='64' viewBox='0 0 64 64'%3E%3Cg fill='none' stroke='%236C63FF' stroke-width='0.35'%3E%3Cpath d='M8 8h16v16H8z'/%3E%3Cpath d='M40 8h16v16H40z'/%3E%3Cpath d='M8 40h16v16H8z'/%3E%3Cpath d='M40 40h16v16H40z'/%3E%3Cpath d='M24 24h16v16H24z'/%3E%3C/g%3E%3Ccircle cx='16' cy='16' r='2' fill='%236C63FF' opacity='0.4'/%3E%3Ccircle cx='48' cy='16' r='2' fill='%23FF6584' opacity='0.35'/%3E%3Ccircle cx='16' cy='48' r='2' fill='%23FF6584' opacity='0.35'/%3E%3Ccircle cx='48' cy='48' r='2' fill='%236C63FF' opacity='0.4'/%3E%3Ccircle cx='32' cy='32' r='2' fill='%236C63FF' opacity='0.5'/%3E%3Cline x1='16' y1='16' x2='32' y2='32' stroke='%236C63FF' stroke-width='0.25' opacity='0.3'/%3E%3Cline x1='48' y1='16' x2='32' y2='32' stroke='%236C63FF' stroke-width='0.25' opacity='0.3'/%3E%3Cline x1='16' y1='48' x2='32' y2='32' stroke='%236C63FF' stroke-width='0.25' opacity='0.3'/%3E%3Cline x1='48' y1='48' x2='32' y2='32' stroke='%236C63FF' stroke-width='0.25' opacity='0.3'/%3E%3C/svg%3E");
  background-size: 64px 64px;
  background-repeat: repeat;
  background-position: 0 0;
  animation: pattern-drift 28s linear infinite;
  pointer-events: none;
  z-index: 0;
}

@keyframes pattern-drift {
  0% { background-position: 0 0; }
  100% { background-position: 64px 64px; }
}

/* Header */
.matching-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 16px;
  background: var(--bg-primary);
  border-bottom: 1px solid var(--border);
  position: relative;
  z-index: 10;
}

.matching-title {
  font-size: 18px;
  font-weight: 700;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
}

.cancel-header-btn {
  width: 44px;
  height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.2s, color 0.2s;
}
.cancel-header-btn:hover { color: var(--text-primary); }
.cancel-header-btn:active { background: var(--bg-card-hover); }
.cancel-header-btn:disabled { opacity: 0.5; cursor: not-allowed; }

/* Content */
.content {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 24px;
  padding: 24px var(--spacing) calc(32px + var(--safe-bottom));
  position: relative;
  z-index: 10;
  width: 100%;
}

/* Search section */
.search-section {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 20px;
  width: 100%;
}

.search-visual {
  position: relative;
  width: 100%;
  aspect-ratio: 16 / 9;
  max-height: 280px;
  display: flex;
  align-items: center;
  justify-content: center;
}
.search-visual-lottie {
  display: block;
  width: 100%;
  height: 100%;
}
.search-visual-lottie :deep(.lottie-animation-container),
.search-visual-lottie :deep(svg) {
  width: 100% !important;
  height: 100% !important;
}

.search-text { text-align: center; }
.search-heading {
  font-size: 24px;
  font-weight: 700;
  color: var(--primary);
  margin-bottom: 4px;
  font-family: 'Cairo', sans-serif;
}
.search-sub {
  font-size: 15px;
  color: var(--text-secondary);
}

.badges-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-top: 12px;
}

.online-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  background: rgba(108, 99, 255, 0.1);
  border: 1px solid rgba(108, 99, 255, 0.2);
  border-radius: 20px;
  font-size: 13px;
}

.online-badge .online-count {
  font-weight: 700;
  color: var(--primary);
}

.online-badge .online-label {
  color: var(--text-secondary);
  font-weight: 500;
}

.filter-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  background: rgba(108, 99, 255, 0.1);
  border: 1px solid rgba(108, 99, 255, 0.2);
  border-radius: 20px;
  font-size: 13px;
  color: var(--filter-color, var(--primary));
}

.filter-badge .filter-val {
  font-weight: 700;
}

/* Cancel button */
.cancel-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
  max-width: 340px;
  min-height: 48px;
  padding: 0 24px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 12px;
  color: var(--text-secondary);
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.2s, color 0.2s, border-color 0.2s;
}
.cancel-btn:hover { color: var(--danger); border-color: rgba(255, 101, 132, 0.3); }
.cancel-btn:active { background: var(--bg-card-hover); }
.cancel-btn:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
