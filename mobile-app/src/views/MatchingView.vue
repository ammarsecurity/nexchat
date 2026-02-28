<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { Search, Target, Lightbulb, X } from 'lucide-vue-next'
import BannerStrip from '../components/BannerStrip.vue'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { useMatchingStore } from '../stores/matching'
import { useChatStore } from '../stores/chat'
import { matchingHub, ensureConnected } from '../services/signalr'

const router = useRouter()
const matching = useMatchingStore()
const chat = useChatStore()
const dots = ref('.')
const cancelling = ref(false)

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
    <div class="content">
      <!-- Animated Search Rings -->
      <div class="search-visual">
        <div class="search-ring s-ring-1"></div>
        <div class="search-ring s-ring-2"></div>
        <div class="search-ring s-ring-3"></div>
        <div class="search-ring s-ring-4"></div>
        <div class="search-center">
          <Search :size="28" class="search-icon" />
        </div>
      </div>

      <div class="search-text">
        <h2 class="gradient-text">جارٍ البحث{{ dots }}</h2>
        <p class="text-secondary">نبحث عن شخص مناسب لك</p>
      </div>

      <div class="filter-chip glass-card">
        <Target :size="18" />
        <span>الفلتر: </span>
        <span class="filter-val">
          {{ matching.genderFilter === 'all' ? 'الكل' : matching.genderFilter === 'male' ? 'ذكور' : 'إناث' }}
        </span>
      </div>

      <div class="tips glass-card">
        <div class="tip-title text-secondary text-sm">
          <Lightbulb :size="16" />
          <span>نصائح أثناء الانتظار</span>
        </div>
        <ul class="tip-list text-sm text-muted">
          <li>يمكنك مشاركة كودك مع أصدقائك</li>
          <li>استخدم فلتر الجنس للمطابقة الأسرع</li>
          <li>أوقات الذروة: الليل وعطل نهاية الأسبوع</li>
        </ul>
      </div>

      <button class="btn-ghost cancel-btn" :disabled="cancelling" @click="cancel">
        <X :size="18" /> إلغاء البحث
      </button>

      <BannerStrip placement="matching" />
    </div>
  </div>
</template>

<style scoped>
.matching {
  background: var(--bg-primary);
  align-items: center;
  display: flex;
  flex-direction: column;
  justify-content: flex-start;
  min-height: 100%;
  overflow-y: auto;
  padding: calc(var(--safe-top) + 20px) var(--spacing) calc(32px + var(--safe-bottom));
  position: relative;
  -webkit-overflow-scrolling: touch;
}

.chat-pattern {
  position: absolute;
  inset: 0;
  opacity: 0.05;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='60' height='60' viewBox='0 0 60 60'%3E%3Cpath fill='none' stroke='%236C63FF' stroke-width='0.5' d='M10 22c0-2 1.6-4 4-4h20c2.4 0 4 2 4 4v14c0 2-1.6 4-4 4H16l-4 4v-4c-2.4 0-4-2-4-4V22z'/%3E%3Cpath fill='none' stroke='%236C63FF' stroke-width='0.5' d='M38 12c0-1.2 1-2.5 2.5-2.5h10c1.5 0 2.5 1.3 2.5 2.5v8c0 1.2-1 2.5-2.5 2.5H42l-2 2v-2c-1.5 0-2.5-1.3-2.5-2.5V12z'/%3E%3C/svg%3E");
  background-size: 60px 60px;
  background-repeat: repeat;
  background-position: 0 0;
  animation: pattern-drift 20s linear infinite;
  pointer-events: none;
  z-index: 0;
}

@keyframes pattern-drift {
  0% { background-position: 0 0; }
  100% { background-position: 60px 60px; }
}

.content {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 28px;
  position: relative;
  z-index: 10;
  width: 100%;
}

.search-visual {
  position: relative;
  width: 220px;
  height: 220px;
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
.s-ring-1 { width: 80px; height: 80px; border-color: rgba(108,99,255,0.6); animation-delay: 0s; }
.s-ring-2 { width: 120px; height: 120px; border-color: rgba(108,99,255,0.4); animation-delay: 0.75s; }
.s-ring-3 { width: 160px; height: 160px; border-color: rgba(108,99,255,0.25); animation-delay: 1.5s; }
.s-ring-4 { width: 200px; height: 200px; border-color: rgba(108,99,255,0.1); animation-delay: 2.25s; }

@keyframes radar {
  0% { opacity: 1; transform: scale(0.8); }
  100% { opacity: 0; transform: scale(1.15); }
}

.search-center {
  align-items: center;
  background: var(--primary);
  border-radius: 50%;
  color: white;
  display: flex;
  height: 64px;
  justify-content: center;
  width: 64px;
  z-index: 5;
}
.search-icon { color: white; }

.search-text { text-align: center; }
.search-text h2 { font-size: 26px; font-weight: 700; margin-bottom: 6px; }

.filter-chip {
  align-items: center;
  color: var(--text-secondary);
  display: flex;
  font-size: 14px;
  gap: 8px;
  padding: 12px 18px;
  background: var(--bg-card);
  border-radius: 12px;
  width: 100%;
  max-width: 280px;
}
.filter-val { color: var(--text-primary); font-weight: 600; }

.tips {
  padding: 16px;
  width: 100%;
  background: var(--bg-card);
  border-radius: 12px;
  border: 1px solid var(--border);
}
.tip-title { align-items: center; display: flex; gap: 6px; margin-bottom: 10px; }
.tip-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
  list-style: none;
  padding: 0;
}
.tip-list li::before { content: '• '; color: #6C63FF; }

.cancel-btn {
  align-items: center;
  display: flex;
  font-size: 15px;
  gap: 8px;
  justify-content: center;
  min-height: var(--touch-min);
  padding: 0 var(--spacing);
  width: 100%;
}
</style>
