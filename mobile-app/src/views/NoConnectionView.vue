<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { WifiOff, RefreshCw } from 'lucide-vue-next'

const isOnline = ref(navigator.onLine)

function checkConnection() {
  isOnline.value = navigator.onLine
  return isOnline.value
}

function handleOffline() {
  isOnline.value = false
}

function retry() {
  if (checkConnection()) {
    window.location.reload()
  }
}

onMounted(() => {
  window.addEventListener('online', checkConnection)
  window.addEventListener('offline', handleOffline)
})
onUnmounted(() => {
  window.removeEventListener('online', checkConnection)
  window.removeEventListener('offline', handleOffline)
})
</script>

<template>
  <div class="no-connection page auth-pattern">
    <div class="no-conn-content">
      <div class="no-conn-icon">
        <WifiOff :size="80" stroke-width="1.5" />
      </div>
      <h1 class="no-conn-title">لا يوجد اتصال بالإنترنت</h1>
      <p class="no-conn-desc">
        تحقق من اتصالك بالشبكة وحاول مرة أخرى
      </p>
      <button class="retry-btn" @click="retry">
        <RefreshCw :size="20" />
        <span>إعادة المحاولة</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.no-connection {
  background: var(--bg-primary);
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100%;
  padding: var(--spacing);
}

.no-conn-content {
  text-align: center;
  max-width: 320px;
}

.no-conn-icon {
  color: var(--text-muted);
  margin-bottom: 24px;
  opacity: 0.8;
}

.no-conn-title {
  font-size: 22px;
  font-weight: 700;
  margin-bottom: 12px;
  color: var(--text-primary);
}

.no-conn-desc {
  font-size: 15px;
  color: var(--text-secondary);
  line-height: 1.6;
  margin-bottom: 28px;
}

.retry-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  min-height: 52px;
  padding: 0 28px;
  background: var(--primary);
  border: none;
  border-radius: 14px;
  color: white;
  font-size: 16px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.retry-btn:active { opacity: 0.9; }
</style>
