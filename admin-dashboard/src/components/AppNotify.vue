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
  border: 1px solid rgba(255, 255, 255, 0.1);
  background: rgba(19, 19, 42, 0.96);
  backdrop-filter: blur(16px);
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.35);
}

.app-notify--success .app-notify__inner {
  border-color: rgba(76, 175, 80, 0.45);
  background: linear-gradient(135deg, rgba(76, 175, 80, 0.18), rgba(19, 19, 42, 0.96));
}

.app-notify--error .app-notify__inner {
  border-color: rgba(255, 101, 132, 0.45);
  background: linear-gradient(135deg, rgba(255, 101, 132, 0.16), rgba(19, 19, 42, 0.96));
}

.app-notify--warning .app-notify__inner {
  border-color: rgba(255, 183, 77, 0.45);
  background: linear-gradient(135deg, rgba(255, 183, 77, 0.14), rgba(19, 19, 42, 0.96));
}

.app-notify--info .app-notify__inner {
  border-color: rgba(108, 99, 255, 0.45);
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.16), rgba(19, 19, 42, 0.96));
}

.app-notify--success .app-notify__icon {
  color: #4caf50;
}

.app-notify--error .app-notify__icon {
  color: #ff6584;
}

.app-notify--warning .app-notify__icon {
  color: #ffb74d;
}

.app-notify--info .app-notify__icon {
  color: #6c63ff;
}

.app-notify__text {
  flex: 1;
  font-size: 14px;
  font-weight: 600;
  line-height: 1.4;
  color: #fff;
}

.app-notify__close {
  opacity: 0.7;
  color: #b0b0c3 !important;
}
</style>
