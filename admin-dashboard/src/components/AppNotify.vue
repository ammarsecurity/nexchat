<script setup>
import { computed } from 'vue'
import { useNotifyStore } from '../stores/notify'

const notify = useNotifyStore()

const icon = computed(() => {
  switch (notify.type) {
    case 'success':
      return 'mdi-check-circle'
    case 'error':
      return 'mdi-alert-circle'
    case 'warning':
      return 'mdi-alert'
    default:
      return 'mdi-information'
  }
})
</script>

<template>
  <v-snackbar
    v-model="notify.visible"
    location="top"
    :timeout="-1"
    rounded="lg"
    elevation="0"
    class="app-notify"
    :class="`app-notify--${notify.type}`"
    @click="notify.close()"
  >
    <div class="app-notify__inner">
      <v-icon :icon="icon" size="22" class="app-notify__icon" />
      <span class="app-notify__text">{{ notify.message }}</span>
      <v-btn
        icon="mdi-close"
        size="x-small"
        variant="text"
        class="app-notify__close"
        @click.stop="notify.close()"
      />
    </div>
  </v-snackbar>
</template>

<style scoped>
.app-notify :deep(.v-snackbar__wrapper) {
  margin-top: 12px;
  max-width: min(520px, calc(100vw - 24px));
}

.app-notify :deep(.v-snackbar__content) {
  padding: 0;
  width: 100%;
}

.app-notify__inner {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  padding: 12px 14px;
  border-radius: 14px;
  border: 1px solid rgba(15, 23, 42, 0.08);
  background: #FFFFFF;
  box-shadow: 0 12px 32px rgba(15, 35, 80, 0.12);
}

.app-notify--success .app-notify__inner {
  border-color: rgba(34, 197, 94, 0.35);
  background: #F0FDF4;
}

.app-notify--error .app-notify__inner {
  border-color: rgba(239, 68, 68, 0.35);
  background: #FEF2F2;
}

.app-notify--warning .app-notify__inner {
  border-color: rgba(245, 158, 11, 0.4);
  background: #FFFBEB;
}

.app-notify--info .app-notify__inner {
  border-color: rgba(46, 134, 251, 0.35);
  background: #EFF6FF;
}

.app-notify--success .app-notify__icon { color: #22C55E; }
.app-notify--error .app-notify__icon { color: #EF4444; }
.app-notify--warning .app-notify__icon { color: #F59E0B; }
.app-notify--info .app-notify__icon { color: #2E86FB; }

.app-notify__text {
  flex: 1;
  font-size: 14px;
  font-weight: 600;
  line-height: 1.4;
  color: #0B1220;
}

.app-notify__close {
  opacity: 0.7;
  color: #5B6577 !important;
}
</style>
