<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { Settings, LogOut, Zap, Globe, User, Users } from 'lucide-vue-next'
import BannerStrip from '../components/BannerStrip.vue'
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
  { value: 'all', label: 'الكل', Icon: Globe },
  { value: 'male', label: 'ذكور', Icon: User },
  { value: 'female', label: 'إناث', Icon: Users }
]
</script>

<template>
  <div class="home page">
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
        <RouterLink to="/settings" class="icon-btn"><Settings :size="20" /></RouterLink>
        <button class="icon-btn" @click="logout"><LogOut :size="20" /></button>
      </div>
    </header>

    <!-- My Code -->
    <div class="code-card glass-card" @click="copyCode">
      <div class="code-label">كودي الخاص</div>
      <div class="code-value gradient-text">{{ user?.uniqueCode }}</div>
      <div class="copy-hint">{{ copied ? 'تم النسخ!' : 'اضغط للنسخ' }}</div>
    </div>

    <!-- Main Action -->
    <div class="main-section">
      <button class="start-btn" @click="startRandom">
        <Zap :size="28" class="start-icon" />
        <span class="start-text">ابدأ محادثة</span>
        <span class="start-sub">عشوائية</span>
      </button>

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
          <component :is="f.Icon" :size="16" />
          <span>{{ f.label }}</span>
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
      <input
        v-model="codeInput"
        class="input-field code-input"
        placeholder="مثال: NX-A3B9"
        maxlength="7"
        @input="codeInput = codeInput.toUpperCase()"
        @keyup.enter="connectByCode"
      />
      <button class="connect-btn" @click="connectByCode" :disabled="!codeInput">
        اتصل
      </button>
      <div v-if="codeError" class="code-error">{{ codeError }}</div>
    </div>

    <BannerStrip placement="home" />
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
}

.header {
  align-items: center;
  display: flex;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 12px;
}

.user-info { display: flex; align-items: center; gap: 12px; }
.home-avatar { overflow: hidden; font-size: 18px; }
.home-avatar-img { width: 100%; height: 100%; object-fit: cover; border-radius: 50%; }

.user-name { font-size: 17px; font-weight: 600; }

.online-badge {
  align-items: center;
  color: var(--success);
  display: flex;
  font-size: 13px;
  gap: 6px;
}
.dot {
  background: var(--success);
  border-radius: 50%;
  height: 6px;
  width: 6px;
  animation: blink 1.5s ease-in-out infinite;
}
@keyframes blink { 0%,100%{opacity:1} 50%{opacity:0.4} }

.header-actions { display: flex; gap: 8px; }
.icon-btn {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  height: var(--touch-min);
  justify-content: center;
  min-width: var(--touch-min);
  padding: 0;
  text-decoration: none;
  transition: background 0.2s;
}
.icon-btn:active { background: var(--bg-card-hover); }

.code-card {
  cursor: pointer;
  margin: 0 var(--spacing) var(--spacing);
  padding: var(--spacing);
  display: flex;
  align-items: center;
  justify-content: space-between;
  transition: background 0.2s;
}
.code-card:active { background: var(--bg-card-hover); }
.code-label { color: var(--text-muted); font-size: 12px; }
.code-value { font-size: 18px; font-weight: 700; letter-spacing: 2px; }
.copy-hint { color: var(--text-muted); font-size: 12px; }

.main-section {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: var(--spacing-lg);
  padding: var(--spacing) var(--spacing) 0;
}

.start-btn {
  align-items: center;
  background: var(--primary);
  border: none;
  border-radius: var(--radius);
  cursor: pointer;
  display: flex;
  flex-direction: column;
  font-family: 'Cairo';
  gap: 4px;
  min-height: 120px;
  padding: 24px 48px;
  transition: opacity 0.2s;
}
.start-btn:active { opacity: 0.9; }

.start-icon { color: white; }
.start-text { color: white; font-size: 17px; font-weight: 600; }
.start-sub { color: rgba(255,255,255,0.8); font-size: 13px; }

.filter-label { margin-top: 0; }

.gender-filters {
  display: flex;
  gap: 8px;
}

.filter-btn {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-full);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  font-family: 'Cairo';
  font-size: 14px;
  gap: 6px;
  min-height: 36px;
  padding: 0 14px;
  transition: 0.2s;
}
.filter-btn.active {
  background: rgba(108, 99, 255, 0.2);
  border-color: var(--primary);
  color: white;
}

.divider {
  align-items: center;
  display: flex;
  gap: 12px;
  margin: 24px var(--spacing);
}
.divider-line {
  background: var(--border);
  flex: 1;
  height: 1px;
}
.divider-text { font-size: 12px; color: var(--text-muted); }

.code-connect {
  margin: 0 var(--spacing) calc(var(--spacing) + var(--safe-bottom));
  padding: var(--spacing);
  display: flex;
  flex-direction: column;
  gap: var(--spacing-sm);
}

.code-connect-title {
  font-size: 13px;
  margin-bottom: 4px;
}

.code-input {
  letter-spacing: 2px;
  font-weight: 600;
  text-align: center;
}

.connect-btn {
  background: var(--primary);
  border: none;
  border-radius: var(--radius-sm);
  color: white;
  cursor: pointer;
  font-family: 'Cairo';
  font-size: 15px;
  font-weight: 600;
  min-height: var(--touch-min);
  padding: 0 var(--spacing);
  width: 100%;
  transition: opacity 0.2s;
}
.connect-btn:disabled { opacity: 0.5; cursor: not-allowed; }
.connect-btn:not(:disabled):active { opacity: 0.9; }

.code-error {
  color: var(--danger);
  font-size: 13px;
}
</style>
