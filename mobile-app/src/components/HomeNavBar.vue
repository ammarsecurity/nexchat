<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { Rocket, Settings, Home } from 'lucide-vue-next'

const props = defineProps({
  loading: { type: Boolean, default: false }
})

const emit = defineEmits(['launch'])

const router = useRouter()
const isLaunching = ref(false)

async function onRocketClick() {
  if (props.loading || isLaunching.value) return
  isLaunching.value = true
  emit('launch')
  // انتظار انتهاء الحركة قبل إعادة التفعيل
  setTimeout(() => { isLaunching.value = false }, 800)
}
</script>

<template>
  <nav class="home-nav">
    <RouterLink to="/home" class="nav-item" aria-label="الرئيسية">
      <Home :size="24" stroke-width="2" />
      <span class="nav-label">الرئيسية</span>
    </RouterLink>

    <div class="nav-center">
      <button
        class="rocket-btn"
        :class="{ launching: isLaunching || loading }"
        :disabled="loading"
        aria-label="ابدأ محادثة عشوائية"
        @click="onRocketClick"
      >
        <div class="rocket-wrap">
          <Rocket :size="36" stroke-width="2" class="rocket-icon" />
          <div class="rocket-flame"></div>
        </div>
      </button>
    </div>

    <RouterLink to="/settings" class="nav-item" aria-label="الإعدادات">
      <Settings :size="24" stroke-width="2" />
      <span class="nav-label">الإعدادات</span>
    </RouterLink>
  </nav>
</template>

<style scoped>
.home-nav {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  display: flex;
  align-items: flex-end;
  justify-content: space-around;
  padding: 8px var(--spacing) calc(8px + var(--safe-bottom));
  background: var(--bg-card);
  border-top: 1px solid var(--border);
  z-index: 100;
}

.nav-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 8px 20px;
  color: var(--text-muted);
  text-decoration: none;
  border-radius: var(--radius-sm);
  transition: color 0.2s, background 0.2s;
  -webkit-tap-highlight-color: transparent;
}
.nav-item.router-link-active,
.nav-item:active {
  color: var(--primary);
}
.nav-label {
  font-size: 11px;
  font-family: 'Cairo', sans-serif;
  font-weight: 500;
}

.nav-center {
  flex: 0 0 auto;
  margin-top: -28px;
}

.rocket-btn {
  width: 72px;
  height: 72px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--primary) 0%, #5B52E8 100%);
  border: 3px solid var(--bg-card);
  box-shadow: 0 4px 20px rgba(108, 99, 255, 0.4), 0 0 0 1px rgba(255,255,255,0.1);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: transform 0.2s, box-shadow 0.2s;
  -webkit-tap-highlight-color: transparent;
}
.rocket-btn:active:not(:disabled) {
  transform: scale(0.95);
}
.rocket-btn:disabled {
  opacity: 0.8;
  cursor: not-allowed;
}

.rocket-wrap {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
}

.rocket-icon {
  color: white;
  transform: rotate(-45deg);
  transition: transform 0.6s cubic-bezier(0.34, 1.56, 0.64, 1),
    opacity 0.5s ease-out;
}

.rocket-flame {
  position: absolute;
  bottom: -10px;
  width: 14px;
  height: 18px;
  background: linear-gradient(to top, #FF6B35, #FF8C42, #FF6584);
  border-radius: 50% 50% 50% 50% / 60% 60% 40% 40%;
  opacity: 0.9;
  transform: scaleY(0.7);
  transition: transform 0.4s ease-out, opacity 0.3s;
  animation: flame-flicker 0.15s ease-in-out infinite alternate;
}

@keyframes flame-flicker {
  from { transform: scaleY(0.7) scaleX(1); }
  to { transform: scaleY(0.75) scaleX(1.05); }
}

/* حركة الانطلاق */
.rocket-btn.launching .rocket-icon {
  transform: rotate(-45deg) translateY(-50px);
  opacity: 0;
}
.rocket-btn.launching .rocket-flame {
  transform: scaleY(2) scaleX(1.5);
  opacity: 1;
  animation: flame-burst 0.5s ease-out;
}
.rocket-btn.launching {
  animation: rocket-pulse 0.8s ease-out;
}

@keyframes flame-burst {
  0% { transform: scaleY(0.7) scaleX(1); opacity: 0.9; }
  50% { transform: scaleY(2.5) scaleX(1.8); opacity: 1; }
  100% { transform: scaleY(2) scaleX(1.5); opacity: 0.3; }
}

@keyframes rocket-pulse {
  0% { box-shadow: 0 4px 20px rgba(108, 99, 255, 0.4); }
  40% { box-shadow: 0 0 50px rgba(108, 99, 255, 0.7), 0 0 80px rgba(255, 101, 132, 0.4); }
  100% { box-shadow: 0 4px 20px rgba(108, 99, 255, 0.4); }
}
</style>
