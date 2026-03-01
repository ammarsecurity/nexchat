<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { Search, Lightbulb, X, Globe, UserCircle, UsersRound } from 'lucide-vue-next'
import BannerStrip from '../components/BannerStrip.vue'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import PrivacyBadge from '../components/PrivacyBadge.vue'
import { useMatchingStore } from '../stores/matching'
import { useChatStore } from '../stores/chat'
import { matchingHub, ensureConnected } from '../services/signalr'

const router = useRouter()
const matching = useMatchingStore()
const chat = useChatStore()
const dots = ref('.')
const cancelling = ref(false)

const filterLabels = { all: 'الكل', male: 'ذكور', female: 'إناث' }
const filterIcons = { all: Globe, male: UserCircle, female: UsersRound }
const filterStyles = {
  all: { color: '#7C75FF', bg: 'rgba(124, 117, 255, 0.15)' },
  male: { color: '#3B82F6', bg: 'rgba(59, 130, 246, 0.15)' },
  female: { color: '#EC4899', bg: 'rgba(236, 72, 153, 0.15)' }
}

let dotsInterval

onMounted(() => {
  dotsInterval = setInterval(() => {
    dots.value = dots.value.length >= 3 ? '.' : dots.value + '.'
  }, 500)

  matchingHub.off('MatchFound')
  matchingHub.on('MatchFound', (data) => {
    const sessionId = data.sessionId ?? data.SessionId
    const partner = data.partner ?? data.Partner
    chat.setSession(sessionId, partner)
    matching.setMatched()
    router.replace(`/chat/${sessionId}`)
  })
})

onUnmounted(() => {
  clearInterval(dotsInterval)
  matchingHub.off('MatchFound')
})

async function cancel() {
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
    <LoaderOverlay :show="cancelling" text="جاري الإلغاء..." />
    <div class="chat-pattern" aria-hidden="true"></div>

    <!-- Header -->
    <header class="matching-header">
      <h1 class="matching-title">البحث عن مطابقة</h1>
      <button class="cancel-header-btn" :disabled="cancelling" @click="cancel" aria-label="إلغاء">
        <X :size="22" stroke-width="2" />
      </button>
    </header>

    <div class="content">
      <!-- Search visual -->
      <section class="search-section">
        <div class="search-visual">
          <div class="search-ring s-ring-1"></div>
          <div class="search-ring s-ring-2"></div>
          <div class="search-ring s-ring-3"></div>
          <div class="search-ring s-ring-4"></div>
          <div class="search-center">
            <Search :size="32" class="search-icon" />
          </div>
        </div>
        <div class="search-text">
          <h2 class="search-heading">جارٍ البحث{{ dots }}</h2>
          <p class="search-sub">نبحث عن شخص مناسب لك</p>
        </div>
      </section>

      <!-- Privacy badge -->
      <section class="privacy-section">
        <PrivacyBadge />
      </section>

      <!-- Filter info -->
      <section class="filter-section">
        <div class="filter-chip" :style="{ '--filter-color': filterStyles[matching.genderFilter].color, '--filter-bg': filterStyles[matching.genderFilter].bg }">
          <span class="filter-icon">
            <component :is="filterIcons[matching.genderFilter]" :size="20" stroke-width="2" />
          </span>
          <span class="filter-label">الفلتر الحالي:</span>
          <span class="filter-val">{{ filterLabels[matching.genderFilter] }}</span>
        </div>
      </section>

      <!-- Tips -->
      <section class="tips-section">
        <div class="tips-card">
          <div class="tips-header">
            <Lightbulb :size="18" class="tips-icon" />
            <span class="tips-title">نصائح أثناء الانتظار</span>
          </div>
          <ul class="tips-list">
            <li>يمكنك مشاركة كودك مع أصدقائك</li>
            <li>استخدم فلتر الجنس للمطابقة الأسرع</li>
            <li>أوقات الذروة: الليل وعطل نهاية الأسبوع</li>
          </ul>
        </div>
      </section>

      <!-- Cancel CTA -->
      <button class="cancel-btn" :disabled="cancelling" @click="cancel">
        <X :size="18" stroke-width="2" />
        <span>إلغاء البحث</span>
      </button>

      <BannerStrip placement="matching" />
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
  opacity: 0.04;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='60' height='60' viewBox='0 0 60 60'%3E%3Cpath fill='none' stroke='%236C63FF' stroke-width='0.5' d='M10 22c0-2 1.6-4 4-4h20c2.4 0 4 2 4 4v14c0 2-1.6 4-4 4H16l-4 4v-4c-2.4 0-4-2-4-4V22z'/%3E%3Cpath fill='none' stroke='%236C63FF' stroke-width='0.5' d='M38 12c0-1.2 1-2.5 2.5-2.5h10c1.5 0 2.5 1.3 2.5 2.5v8c0 1.2-1 2.5-2.5 2.5H42l-2 2v-2c-1.5 0-2.5-1.3-2.5-2.5V12z'/%3E%3C/svg%3E");
  background-size: 60px 60px;
  background-repeat: repeat;
  background-position: 0 0;
  animation: pattern-drift 25s linear infinite;
  pointer-events: none;
  z-index: 0;
}

@keyframes pattern-drift {
  0% { background-position: 0 0; }
  100% { background-position: 60px 60px; }
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
  width: 200px;
  height: 200px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.search-ring {
  border-radius: 50%;
  border: 2px solid;
  position: absolute;
  animation: radar 3s ease-out infinite;
}
.s-ring-1 { width: 72px; height: 72px; border-color: rgba(108,99,255,0.5); animation-delay: 0s; }
.s-ring-2 { width: 110px; height: 110px; border-color: rgba(108,99,255,0.35); animation-delay: 0.6s; }
.s-ring-3 { width: 148px; height: 148px; border-color: rgba(108,99,255,0.2); animation-delay: 1.2s; }
.s-ring-4 { width: 186px; height: 186px; border-color: rgba(108,99,255,0.08); animation-delay: 1.8s; }

@keyframes radar {
  0% { opacity: 1; transform: scale(0.85); }
  100% { opacity: 0; transform: scale(1.12); }
}

.search-center {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 72px;
  height: 72px;
  border-radius: 50%;
  background: linear-gradient(145deg, #7C75FF 0%, var(--primary) 50%, #5B54E8 100%);
  color: white;
  box-shadow: 0 4px 16px rgba(108, 99, 255, 0.4);
  z-index: 5;
}
.search-icon { color: white; }

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

/* Privacy section */
.privacy-section {
  width: 100%;
  max-width: 340px;
  display: flex;
  justify-content: center;
}

/* Filter section */
.filter-section {
  width: 100%;
  max-width: 340px;
}

.filter-chip {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px 18px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  width: 100%;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
}

.filter-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 10px;
  background: var(--filter-bg, rgba(108, 99, 255, 0.15));
  color: var(--filter-color, var(--primary));
}

.filter-label {
  font-size: 14px;
  color: var(--text-secondary);
  font-weight: 500;
}

.filter-val {
  font-size: 15px;
  font-weight: 700;
  color: var(--filter-color, var(--primary));
  margin-inline-start: auto;
}

/* Tips section */
.tips-section {
  width: 100%;
  max-width: 340px;
}

.tips-card {
  padding: 18px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
}

.tips-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
}

.tips-icon {
  color: var(--primary);
  flex-shrink: 0;
}

.tips-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
}

.tips-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  list-style: none;
  padding: 0;
  margin: 0;
}

.tips-list li {
  font-size: 14px;
  color: var(--text-secondary);
  padding-inline-start: 16px;
  position: relative;
}
.tips-list li::before {
  content: '';
  position: absolute;
  inset-inline-start: 0;
  top: 0.5em;
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: var(--primary);
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
