<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, ChevronRight } from 'lucide-vue-next'
import { useAuthStore } from '../stores/auth'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import logoImg from '../assets/logo.png'

const router = useRouter()
const auth = useAuthStore()
const currentIndex = ref(0)
const slides = ref([])
const loading = ref(true)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'
const ONBOARDING_SEEN = 'nexchat_onboarding_seen'

const defaultSlides = [
  { title: 'مرحباً بك في NexChat', description: 'تواصل مع أشخاص جدد من حول العالم', imageUrl: '' },
  { title: 'محادثات عشوائية', description: 'ابدأ محادثة مع شخص جديد بنقرة واحدة', imageUrl: '' },
  { title: 'مكالمات فيديو', description: 'تواصل وجهًا لوجه مع من تتحدث', imageUrl: '' }
]

const currentSlide = computed(() => slides.value[currentIndex.value] || defaultSlides[0])
const isLast = computed(() => currentIndex.value >= slides.value.length - 1)
const isFirst = computed(() => currentIndex.value <= 0)

onMounted(async () => {
  try {
    const res = await fetch(`${API_BASE}/sitecontent/onboarding`)
    const data = await res.json()
    const content = data?.content ?? data?.Content ?? ''
    if (content) {
      try {
        const parsed = JSON.parse(content)
        if (parsed.enabled === false) {
          finish()
          return
        }
        if (Array.isArray(parsed.slides) && parsed.slides.length > 0) {
          slides.value = parsed.slides.sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
        } else {
          slides.value = [...defaultSlides]
        }
      } catch {
        slides.value = [...defaultSlides]
      }
    } else {
      slides.value = [...defaultSlides]
    }
  } catch {
    slides.value = [...defaultSlides]
  } finally {
    loading.value = false
  }
})

function finish() {
  localStorage.setItem(ONBOARDING_SEEN, '1')
  router.replace(auth.isLoggedIn ? '/home' : '/login')
}

function next() {
  if (isLast.value) {
    finish()
  } else {
    currentIndex.value++
  }
}

function prev() {
  if (!isFirst.value) currentIndex.value--
}

function skip() {
  finish()
}
</script>

<template>
  <div class="onboarding page auth-pattern">
    <LoaderOverlay :show="loading" text="جاري تحميل المحتوى..." />

    <template v-if="!loading">
      <button class="skip-btn" @click="skip">تخطي</button>

      <div class="slides-wrap">
        <Transition name="slide" mode="out-in">
          <div :key="currentIndex" class="slide-content">
            <div v-if="currentSlide.imageUrl" class="slide-image-wrap">
              <img :src="currentSlide.imageUrl" :alt="currentSlide.title" class="slide-image" />
            </div>
            <div v-else class="slide-placeholder">
              <img :src="logoImg" alt="NexChat" class="slide-logo" />
            </div>
            <h2 class="slide-title">{{ currentSlide.title }}</h2>
            <p class="slide-desc">{{ currentSlide.description }}</p>
          </div>
        </Transition>
      </div>

      <div class="dots">
        <button
          v-for="(_, i) in slides"
          :key="i"
          class="dot"
          :class="{ active: i === currentIndex }"
          :aria-label="`شريحة ${i + 1}`"
          @click="currentIndex = i"
        />
      </div>

      <div class="nav-buttons">
        <button class="nav-btn prev" :disabled="isFirst" @click="prev">
          <ChevronRight :size="24" />
        </button>
        <button class="nav-btn next primary" @click="next">
          <span>{{ isLast ? 'ابدأ' : 'التالي' }}</span>
          <ChevronLeft :size="20" />
        </button>
      </div>
    </template>
  </div>
</template>

<style scoped>
.onboarding {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: space-between;
  min-height: 100%;
  padding: calc(var(--safe-top) + 16px) var(--spacing) calc(var(--safe-bottom) + 24px);
  position: relative;
}

.onboarding-loading {
  display: flex;
  align-items: center;
  justify-content: center;
  flex: 1;
}
.loader {
  width: 40px;
  height: 40px;
  border: 3px solid var(--border);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

.skip-btn {
  position: absolute;
  top: calc(var(--safe-top) + 16px);
  left: var(--spacing);
  background: none;
  border: none;
  color: var(--text-muted);
  font-size: 15px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.skip-btn:active { opacity: 0.8; }

.slides-wrap {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  padding-top: 48px;
}

.slide-content {
  text-align: center;
  max-width: 320px;
}

.slide-image-wrap {
  width: 200px;
  height: 200px;
  margin: 0 auto 24px;
  border-radius: 20px;
  overflow: hidden;
  background: var(--bg-card);
}
.slide-image {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.slide-placeholder {
  width: 140px;
  height: 140px;
  margin: 0 auto 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--bg-card);
  border-radius: 24px;
}
.slide-logo {
  height: 80px;
  width: auto;
  object-fit: contain;
}

.slide-title {
  font-size: 22px;
  font-weight: 700;
  margin-bottom: 12px;
  color: var(--text-primary);
}

.slide-desc {
  font-size: 15px;
  color: var(--text-secondary);
  line-height: 1.6;
  margin: 0;
}

.slide-enter-active, .slide-leave-active { transition: all 0.3s ease; }
.slide-enter-from { opacity: 0; transform: translateX(20px); }
.slide-leave-to { opacity: 0; transform: translateX(-20px); }

.dots {
  display: flex;
  gap: 8px;
  justify-content: center;
  padding: 16px 0;
}

.dot {
  width: 8px;
  height: 8px;
  min-width: 8px;
  border-radius: 50%;
  background: var(--border);
  border: none;
  cursor: pointer;
  padding: 0;
  transition: all 0.2s;
}
.dot.active {
  background: var(--primary);
  width: 8px !important;
  min-width: 8px;
}

.nav-buttons {
  display: flex;
  gap: 12px;
  width: 100%;
  max-width: 320px;
}

.nav-btn {
  flex: 1;
  min-height: 52px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  border: none;
  border-radius: 14px;
  font-size: 16px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.nav-btn.prev {
  background: var(--bg-card);
  color: var(--text-secondary);
  flex: 0;
  min-width: 52px;
}
.nav-btn.prev:disabled { opacity: 0.4; cursor: not-allowed; }
.nav-btn.next {
  background: var(--primary);
  color: white;
}
.nav-btn.next:active { opacity: 0.9; }
</style>
