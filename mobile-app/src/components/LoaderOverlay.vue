<script setup>
import { Loader2 } from 'lucide-vue-next'

defineProps({
  show: { type: Boolean, default: false },
  text: { type: String, default: 'جاري التحميل...' }
})
</script>

<template>
  <Transition name="fade">
    <div v-if="show" class="loader-overlay">
      <div class="loader-box glass-card">
        <Loader2 :size="48" class="spin" />
        <p v-if="text" class="loader-text">{{ text }}</p>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.loader-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
  backdrop-filter: blur(4px);
}

.loader-box {
  padding: 28px 32px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 16px;
  min-width: 160px;
}

.loader-box :deep(.spin) {
  color: var(--primary);
  animation: spin 0.8s linear infinite;
}

.loader-text {
  margin: 0;
  font-size: 15px;
  color: var(--text-secondary);
  font-family: 'Cairo', sans-serif;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.fade-enter-active, .fade-leave-active { transition: opacity 0.2s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
