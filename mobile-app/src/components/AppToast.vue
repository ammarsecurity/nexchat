<script setup>
import { computed } from 'vue'
import { CheckCircle, AlertCircle, Info } from 'lucide-vue-next'
import { useNotifyStore } from '../stores/notify'

const notify = useNotifyStore()

const Icon = computed(() => {
  if (notify.type === 'success') return CheckCircle
  if (notify.type === 'error') return AlertCircle
  return Info
})
</script>

<template>
  <Transition name="app-toast">
    <div
      v-if="notify.visible"
      class="app-toast"
      :class="`app-toast--${notify.type}`"
      role="status"
      @click="notify.close()"
    >
      <span class="app-toast__icon" aria-hidden="true">
        <component :is="Icon" :size="20" stroke-width="2" />
      </span>
      <span class="app-toast__text">{{ notify.message }}</span>
    </div>
  </Transition>
</template>

<style scoped>
.app-toast {
  position: fixed;
  top: max(12px, env(safe-area-inset-top, 0px));
  left: 12px;
  right: 12px;
  z-index: 10050;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  border-radius: 14px;
  font-size: 14px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  box-shadow: 0 8px 28px rgba(0, 0, 0, 0.22);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.app-toast--error {
  background: linear-gradient(135deg, rgba(255, 101, 132, 0.18) 0%, rgba(255, 101, 132, 0.08) 100%);
  border: 1px solid rgba(255, 101, 132, 0.4);
  color: var(--danger, #ff6584);
}

.app-toast--success {
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.2) 0%, rgba(108, 99, 255, 0.08) 100%);
  border: 1px solid rgba(108, 99, 255, 0.4);
  color: var(--primary, #6c63ff);
}

.app-toast--info {
  background: var(--bg-card, #fff);
  border: 1px solid var(--border, rgba(0, 0, 0, 0.08));
  color: var(--text-primary, #1a1a1a);
}

.app-toast__icon {
  flex-shrink: 0;
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 10px;
}

.app-toast--error .app-toast__icon {
  background: rgba(255, 101, 132, 0.2);
}

.app-toast--success .app-toast__icon {
  background: rgba(108, 99, 255, 0.18);
}

.app-toast--info .app-toast__icon {
  background: rgba(108, 99, 255, 0.12);
}

.app-toast__text {
  flex: 1;
  line-height: 1.35;
}

.app-toast-enter-active,
.app-toast-leave-active {
  transition: opacity 0.22s ease, transform 0.22s ease;
}

.app-toast-enter-from,
.app-toast-leave-to {
  opacity: 0;
  transform: translateY(-12px);
}
</style>
