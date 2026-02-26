<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { useMatchingStore } from '../stores/matching'
import { useChatStore } from '../stores/chat'
import { matchingHub, startHub } from '../services/signalr'

const router = useRouter()
const auth = useAuthStore()
const matching = useMatchingStore()
const chat = useChatStore()

const codeInput = ref('')
const codeError = ref('')
const copied = ref(false)
const onlineCount = ref(Math.floor(Math.random() * 200) + 50)

const user = computed(() => auth.user)
const avatarLetter = computed(() => user.value?.name?.[0]?.toUpperCase() || '?')

onMounted(async () => {
  await startHub(matchingHub)

  // Remove old listeners to avoid duplicates on re-mount
  matchingHub.off('MatchFound')
  matchingHub.off('SearchCancelled')
  matchingHub.off('CodeError')

  matchingHub.on('MatchFound', (data) => {
    const sessionId = data.sessionId ?? data.SessionId
    const partner = data.partner ?? data.Partner
    chat.setSession(sessionId, partner)
    matching.setMatched()
    router.push(`/chat/${sessionId}`)
  })

  matchingHub.on('SearchCancelled', () => {
    matching.setIdle()
  })

  matchingHub.on('CodeError', (msg) => {
    codeError.value = msg
  })

  // Simulate online count change
  setInterval(() => {
    onlineCount.value = Math.max(20, onlineCount.value + Math.floor(Math.random() * 6) - 3)
  }, 5000)
})

async function startRandom() {
  matching.setSearching()
  await matchingHub.invoke('StartSearching', matching.genderFilter)
  // Only navigate to /matching if we weren't already matched during invoke
  if (matching.status !== 'matched') {
    router.push('/matching')
  }
}

async function connectByCode() {
  if (!codeInput.value.trim()) return
  codeError.value = ''
  const code = codeInput.value.trim().toUpperCase()
  if (!code.startsWith('NX-') || code.length !== 7) {
    codeError.value = 'الكود يجب أن يكون بالشكل NX-XXXX'
    return
  }
  await matchingHub.invoke('ConnectByCode', code)
}

function copyCode() {
  navigator.clipboard.writeText(user.value.uniqueCode)
  copied.value = true
  setTimeout(() => copied.value = false, 2000)
}

onUnmounted(() => {
  matchingHub.off('MatchFound')
  matchingHub.off('SearchCancelled')
  matchingHub.off('CodeError')
})

function logout() {
  matchingHub.stop()
  auth.logout()
  router.replace('/login')
}

const genderFilters = [
  { value: 'all', label: 'الكل', icon: '🌍' },
  { value: 'male', label: 'ذكور', icon: '👨' },
  { value: 'female', label: 'إناث', icon: '👩' }
]
</script>

<template>
  <div class="home page">
    <!-- Background -->
    <div class="bg-orb bg-1"></div>
    <div class="bg-orb bg-2"></div>

    <!-- Header -->
    <header class="header">
      <div class="user-info">
        <div class="avatar avatar-sm home-avatar" :style="{ background: auth.avatarColor }">
          <img v-if="auth.avatar && auth.avatar.startsWith('http')" :src="auth.avatar" class="home-avatar-img" />
          <span v-else-if="auth.avatar">{{ auth.avatar }}</span>
          <span v-else>{{ avatarLetter }}</span>
        </div>
        <div>
          <div class="user-name">{{ user?.name }}</div>
          <div class="online-badge">
            <span class="dot"></span>
            <span>{{ onlineCount }} متصل الآن</span>
          </div>
        </div>
      </div>

      <div class="header-actions">
        <RouterLink to="/settings" class="icon-btn">⚙️</RouterLink>
        <button class="icon-btn" @click="logout">🚪</button>
      </div>
    </header>

    <!-- My Code -->
    <div class="code-card glass-card" @click="copyCode">
      <div class="code-label">كودي الخاص</div>
      <div class="code-value gradient-text">{{ user?.uniqueCode }}</div>
      <div class="copy-hint">{{ copied ? '✅ تم النسخ!' : '📋 اضغط للنسخ' }}</div>
    </div>

    <!-- Main Action -->
    <div class="main-section">
      <div class="pulse-wrapper">
        <div class="pulse-ring ring-1"></div>
        <div class="pulse-ring ring-2"></div>
        <div class="pulse-ring ring-3"></div>
        <button class="start-btn" @click="startRandom">
          <span class="start-icon">⚡</span>
          <span class="start-text">ابدأ محادثة</span>
          <span class="start-sub">عشوائية</span>
        </button>
      </div>

      <!-- Gender Filter -->
      <div class="filter-label text-secondary text-sm">فلتر المطابقة</div>
      <div class="gender-filters">
        <button
          v-for="f in genderFilters"
          :key="f.value"
          class="filter-btn"
          :class="{ active: matching.genderFilter === f.value }"
          @click="matching.genderFilter = f.value"
        >
          {{ f.icon }} {{ f.label }}
        </button>
      </div>
    </div>

    <!-- Divider -->
    <div class="divider">
      <span class="divider-line"></span>
      <span class="divider-text text-muted">أو</span>
      <span class="divider-line"></span>
    </div>

    <!-- Code Connect -->
    <div class="code-connect glass-card">
      <div class="code-connect-title text-sm text-secondary">اتصل بكود شخص معين</div>
      <div class="code-input-wrap">
        <input
          v-model="codeInput"
          class="input-field"
          placeholder="مثال: NX-A3B9"
          maxlength="7"
          @input="codeInput = codeInput.toUpperCase()"
          @keyup.enter="connectByCode"
        />
        <button class="connect-btn" @click="connectByCode" :disabled="!codeInput">
          اتصل
        </button>
      </div>
      <div v-if="codeError" class="code-error">⚠️ {{ codeError }}</div>
    </div>
  </div>
</template>

<style scoped>
.home {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  padding: 0;
  overflow-y: auto;
  overflow-x: hidden;
  position: relative;
}

.bg-orb {
  border-radius: 50%;
  filter: blur(80px);
  position: absolute;
  pointer-events: none;
  z-index: 0;
}
.bg-1 { background: rgba(108,99,255,0.15); width:250px; height:250px; top:-60px; right:-60px; }
.bg-2 { background: rgba(255,101,132,0.1); width:200px; height:200px; bottom:100px; left:-50px; }

.header {
  align-items: center;
  display: flex;
  justify-content: space-between;
  padding: 20px 20px 16px;
  position: relative;
  z-index: 10;
}

.user-info { display: flex; align-items: center; gap: 10px; }
.home-avatar { overflow: hidden; font-size: 20px; }
.home-avatar-img { width: 100%; height: 100%; object-fit: cover; border-radius: 50%; }

.user-name { font-size: 16px; font-weight: 600; }

.online-badge {
  align-items: center;
  color: #4ade80;
  display: flex;
  font-size: 12px;
  gap: 4px;
}
.dot {
  background: #4ade80;
  border-radius: 50%;
  height: 6px;
  width: 6px;
  animation: blink 1.5s ease-in-out infinite;
}
@keyframes blink { 0%,100%{opacity:1} 50%{opacity:0.4} }

.header-actions { display: flex; gap: 8px; }
.icon-btn {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 10px;
  cursor: pointer;
  font-size: 18px;
  padding: 8px;
  text-decoration: none;
  transition: 0.2s;
}
.icon-btn:hover { background: var(--bg-card-hover); }

.code-card {
  cursor: pointer;
  margin: 0 20px 16px;
  padding: 14px 18px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  position: relative;
  z-index: 10;
  transition: 0.2s;
}
.code-card:hover { background: var(--bg-card-hover); }
.code-label { color: var(--text-muted); font-size: 12px; }
.code-value { font-size: 22px; font-weight: 800; letter-spacing: 2px; }
.copy-hint { color: var(--text-muted); font-size: 12px; }

.main-section {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 20px;
  padding: 24px 20px 0;
  position: relative;
  z-index: 10;
}

.pulse-wrapper {
  position: relative;
  width: 180px;
  height: 180px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.pulse-ring {
  border-radius: 50%;
  border: 2px solid rgba(108, 99, 255, 0.3);
  position: absolute;
  animation: pulse-out 2.5s ease-out infinite;
}
.ring-1 { width: 140px; height: 140px; animation-delay: 0s; }
.ring-2 { width: 162px; height: 162px; animation-delay: 0.8s; }
.ring-3 { width: 180px; height: 180px; animation-delay: 1.6s; }

@keyframes pulse-out {
  0% { opacity: 0.8; transform: scale(0.95); }
  100% { opacity: 0; transform: scale(1.2); }
}

.start-btn {
  align-items: center;
  background: var(--gradient);
  border: none;
  border-radius: 50%;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  gap: 2px;
  height: 130px;
  justify-content: center;
  width: 130px;
  box-shadow: 0 0 40px rgba(108, 99, 255, 0.5), 0 0 80px rgba(108, 99, 255, 0.2);
  transition: 0.2s;
  z-index: 5;
}
.start-btn:hover { transform: scale(1.05); box-shadow: 0 0 60px rgba(108, 99, 255, 0.6); }
.start-btn:active { transform: scale(0.98); }

.start-icon { font-size: 32px; }
.start-text { color: white; font-size: 16px; font-weight: 700; }
.start-sub { color: rgba(255,255,255,0.75); font-size: 12px; }

.filter-label { margin-top: -4px; }

.gender-filters {
  display: flex;
  gap: 8px;
}

.filter-btn {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-full);
  color: var(--text-secondary);
  cursor: pointer;
  font-size: 13px;
  padding: 8px 16px;
  transition: 0.2s;
}
.filter-btn.active {
  background: rgba(108, 99, 255, 0.2);
  border-color: #6C63FF;
  color: white;
}

.divider {
  align-items: center;
  display: flex;
  gap: 12px;
  margin: 20px;
  position: relative;
  z-index: 10;
}
.divider-line {
  background: var(--border);
  flex: 1;
  height: 1px;
}
.divider-text { font-size: 12px; }

.code-connect {
  margin: 0 20px 24px;
  padding: 16px;
  position: relative;
  z-index: 10;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.code-connect-title { font-size: 13px; }

.code-input-wrap {
  display: flex;
  gap: 10px;
}

.code-input-wrap .input-field {
  flex: 1;
  letter-spacing: 2px;
  font-weight: 600;
}

.connect-btn {
  background: var(--gradient);
  border: none;
  border-radius: var(--radius-sm);
  color: white;
  cursor: pointer;
  font-size: 14px;
  font-weight: 600;
  padding: 0 20px;
  white-space: nowrap;
  transition: 0.2s;
}
.connect-btn:disabled { opacity: 0.4; cursor: not-allowed; }
.connect-btn:not(:disabled):hover { opacity: 0.9; }

.code-error {
  color: #FF6584;
  font-size: 13px;
}
</style>
