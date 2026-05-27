<script setup>
import { computed } from 'vue'
import { AlertCircle, Trash2, Info } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'

const open = defineModel('open', { type: Boolean, default: false })

const props = defineProps({
  mode: { type: String, default: 'alert' },
  variant: { type: String, default: 'error' },
  title: { type: String, default: '' },
  message: { type: String, default: '' },
  confirmText: { type: String, default: '' },
  cancelText: { type: String, default: '' },
  loading: { type: Boolean, default: false }
})

const emit = defineEmits(['confirm', 'cancel'])

const { t } = useI18n()

const isConfirm = computed(() => props.mode === 'confirm')

const resolvedTitle = computed(() => {
  if (props.title) return props.title
  if (props.variant === 'error') return t('common.error')
  if (props.variant === 'danger') return t('stories.deleteSlideTitle')
  return t('stories.dialogNotice')
})

const resolvedConfirm = computed(() => {
  if (props.confirmText) return props.confirmText
  if (isConfirm.value && props.variant === 'danger') return t('common.delete')
  return t('common.ok')
})

const resolvedCancel = computed(() => props.cancelText || t('common.cancel'))

const iconComponent = computed(() => {
  if (props.variant === 'danger') return Trash2
  if (props.variant === 'info') return Info
  return AlertCircle
})

function close() {
  if (props.loading) return
  open.value = false
  emit('cancel')
}

function onConfirm() {
  if (props.loading) return
  emit('confirm')
}
</script>

<template>
  <Teleport to="body">
    <Transition name="story-dialog">
      <div
        v-if="open"
        class="story-dialog-overlay"
        role="presentation"
        @click.self="close"
      >
        <div
          class="story-dialog glass-card"
          role="alertdialog"
          :aria-modal="true"
          :aria-labelledby="message ? 'story-dialog-title' : undefined"
          :aria-describedby="message ? 'story-dialog-message' : undefined"
          @click.stop
        >
          <div class="story-dialog-icon-wrap" :class="`story-dialog-icon-wrap--${variant}`">
            <component :is="iconComponent" :size="22" stroke-width="2" aria-hidden="true" />
          </div>
          <h3 v-if="resolvedTitle" id="story-dialog-title" class="story-dialog-title">
            {{ resolvedTitle }}
          </h3>
          <p v-if="message" id="story-dialog-message" class="story-dialog-message">{{ message }}</p>
          <div class="story-dialog-actions" :class="{ 'story-dialog-actions--single': !isConfirm }">
            <button
              v-if="isConfirm"
              type="button"
              class="story-dialog-btn story-dialog-btn--ghost"
              :disabled="loading"
              @click="close"
            >
              {{ resolvedCancel }}
            </button>
            <button
              type="button"
              class="story-dialog-btn"
              :class="isConfirm && variant === 'danger' ? 'story-dialog-btn--danger' : 'story-dialog-btn--primary'"
              :disabled="loading"
              @click="onConfirm"
            >
              <span v-if="loading" class="story-dialog-spinner" aria-hidden="true" />
              {{ loading ? t('common.loading') : resolvedConfirm }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.story-dialog-overlay {
  position: fixed;
  inset: 0;
  z-index: 10050;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
  background: rgba(0, 0, 0, 0.52);
  backdrop-filter: blur(6px);
  -webkit-backdrop-filter: blur(6px);
}

.story-dialog {
  width: 100%;
  max-width: 320px;
  padding: 22px 20px 18px;
  border-radius: var(--radius-lg);
  text-align: center;
  font-family: 'Cairo', sans-serif;
  box-shadow: var(--shadow-md);
}

.story-dialog-icon-wrap {
  width: 52px;
  height: 52px;
  margin: 0 auto 14px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
}

.story-dialog-icon-wrap--error {
  background: linear-gradient(135deg, rgba(255, 101, 132, 0.2), rgba(255, 101, 132, 0.08));
  color: var(--danger);
  border: 1px solid rgba(255, 101, 132, 0.28);
}

.story-dialog-icon-wrap--danger {
  background: linear-gradient(135deg, rgba(229, 57, 53, 0.18), rgba(255, 101, 132, 0.1));
  color: #e53935;
  border: 1px solid rgba(229, 57, 53, 0.25);
}

.story-dialog-icon-wrap--info {
  background: linear-gradient(135deg, rgba(37, 99, 235, 0.16), rgba(96, 165, 250, 0.1));
  color: var(--primary);
  border: 1px solid rgba(37, 99, 235, 0.22);
}

.story-dialog-title {
  margin: 0 0 8px;
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
  line-height: 1.35;
}

.story-dialog-message {
  margin: 0 0 20px;
  font-size: 14px;
  font-weight: 500;
  line-height: 1.55;
  color: var(--text-secondary);
}

.story-dialog-actions {
  display: flex;
  gap: 10px;
}

.story-dialog-actions--single .story-dialog-btn {
  width: 100%;
}

.story-dialog-btn {
  flex: 1;
  min-height: 44px;
  padding: 0 16px;
  border-radius: 999px;
  border: none;
  font-family: 'Cairo', sans-serif;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  -webkit-tap-highlight-color: transparent;
  transition: opacity 0.15s ease, transform 0.12s ease;
}

.story-dialog-btn:active:not(:disabled) {
  transform: scale(0.98);
}

.story-dialog-btn:disabled {
  opacity: 0.75;
  cursor: wait;
}

.story-dialog-btn--ghost {
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  color: var(--text-primary);
}

.story-dialog-btn--primary {
  background: var(--primary);
  color: #fff;
}

.story-dialog-btn--danger {
  background: var(--danger);
  color: #fff;
}

.story-dialog-spinner {
  width: 16px;
  height: 16px;
  border: 2px solid rgba(255, 255, 255, 0.35);
  border-top-color: #fff;
  border-radius: 50%;
  animation: story-dialog-spin 0.7s linear infinite;
}

@keyframes story-dialog-spin {
  to {
    transform: rotate(360deg);
  }
}

.story-dialog-enter-active,
.story-dialog-leave-active {
  transition: opacity 0.22s ease;
}

.story-dialog-enter-active .story-dialog,
.story-dialog-leave-active .story-dialog {
  transition: transform 0.22s ease, opacity 0.22s ease;
}

.story-dialog-enter-from,
.story-dialog-leave-to {
  opacity: 0;
}

.story-dialog-enter-from .story-dialog,
.story-dialog-leave-to .story-dialog {
  opacity: 0;
  transform: scale(0.94) translateY(8px);
}
</style>
