<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useMatchingStore } from '../stores/matching'
import { useChatStore } from '../stores/chat'
import { matchingHub } from '../services/signalr'

const router = useRouter()
const matching = useMatchingStore()
const chat = useChatStore()
const dots = ref('.')

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
  await matchingHub.invoke('CancelSearching')
  matching.setIdle()
  router.replace('/home')
}
</script>

<template>
  <div class="matching page">
    <div class="bg-orb bg-1"></div>
    <div class="bg-orb bg-2"></div>

    <div class="content">
      <!-- Animated Search Rings -->
      <div class="search-visual">
        <div class="search-ring s-ring-1"></div>
        <div class="search-ring s-ring-2"></div>
        <div class="search-ring s-ring-3"></div>
        <div class="search-ring s-ring-4"></div>
        <div class="search-center">
          <span class="search-icon">🔍</span>
        </div>
      </div>

      <div class="search-text">
        <h2 class="gradient-text">جارٍ البحث{{ dots }}</h2>
        <p class="text-secondary">نبحث عن شخص مناسب لك</p>
      </div>

      <div class="filter-chip glass-card">
        <span>🎯 الفلتر: </span>
        <span class="filter-val">
          {{ matching.genderFilter === 'all' ? 'الكل' : matching.genderFilter === 'male' ? 'ذكور' : 'إناث' }}
        </span>
      </div>

      <div class="tips glass-card">
        <div class="tip-title text-secondary text-sm">نصائح أثناء الانتظار 💡</div>
        <ul class="tip-list text-sm text-muted">
          <li>يمكنك مشاركة كودك مع أصدقائك</li>
          <li>استخدم فلتر الجنس للمطابقة الأسرع</li>
          <li>أوقات الذروة: الليل وعطل نهاية الأسبوع</li>
        </ul>
      </div>

      <button class="btn-ghost cancel-btn" @click="cancel">
        ❌ إلغاء البحث
      </button>
    </div>
  </div>
</template>

<style scoped>
.matching {
  background: var(--bg-primary);
  align-items: center;
  justify-content: center;
  padding: 32px 24px;
  position: relative;
  overflow: hidden;
}

.bg-orb {
  border-radius: 50%;
  filter: blur(80px);
  position: absolute;
  pointer-events: none;
}
.bg-1 { background: rgba(108,99,255,0.2); width:300px; height:300px; top:-80px; right:-80px; }
.bg-2 { background: rgba(255,101,132,0.15); width:250px; height:250px; bottom:-60px; left:-60px; }

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
  background: var(--gradient);
  border-radius: 50%;
  width: 64px;
  height: 64px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 28px;
  box-shadow: 0 0 30px rgba(108,99,255,0.5);
  animation: center-pulse 2s ease-in-out infinite;
  z-index: 5;
}
@keyframes center-pulse {
  0%,100% { transform: scale(1); }
  50% { transform: scale(1.1); }
}

.search-text { text-align: center; }
.search-text h2 { font-size: 26px; font-weight: 700; margin-bottom: 6px; }

.filter-chip {
  display: flex;
  gap: 6px;
  align-items: center;
  padding: 10px 18px;
  font-size: 14px;
  color: var(--text-secondary);
}
.filter-val { color: white; font-weight: 600; }

.tips {
  padding: 16px;
  width: 100%;
}
.tip-title { margin-bottom: 10px; }
.tip-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
  list-style: none;
  padding: 0;
}
.tip-list li::before { content: '• '; color: #6C63FF; }

.cancel-btn {
  width: 100%;
  padding: 14px;
  font-size: 15px;
}
</style>
