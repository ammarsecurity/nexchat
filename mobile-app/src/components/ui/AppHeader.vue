<script setup>
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, ChevronRight } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../../stores/locale'

const props = defineProps({
  title: { type: String, default: '' },
  showBack: { type: Boolean, default: true },
  backTo: { type: String, default: '' },
  bordered: { type: Boolean, default: true }
})

const router = useRouter()
const { t } = useI18n()
const localeStore = useLocaleStore()

const BackIcon = computed(() => (localeStore.isRtl ? ChevronRight : ChevronLeft))

function onBack() {
  if (props.backTo) router.replace(props.backTo)
  else router.back()
}
</script>

<template>
  <header class="app-header" :class="{ 'app-header--flat': !bordered }">
    <button
      v-if="showBack"
      type="button"
      class="app-header__back"
      :aria-label="t('common.back')"
      @click="onBack"
    >
      <component :is="BackIcon" :size="22" stroke-width="2" />
    </button>
    <span v-else class="app-header__spacer" aria-hidden="true" />

    <h1 v-if="title" class="app-header__title">{{ title }}</h1>
    <div v-else class="app-header__title-slot">
      <slot name="title" />
    </div>

    <div class="app-header__actions">
      <slot name="actions" />
      <span v-if="!$slots.actions" class="app-header__spacer" aria-hidden="true" />
    </div>
  </header>
</template>

<style scoped>
.app-header {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-shrink: 0;
  padding: calc(var(--safe-top) + 10px) var(--spacing) 14px;
  background: var(--bg-card);
  border-bottom: none;
  box-shadow: var(--shadow-sm);
}

.app-header--flat {
  background: transparent;
  border-bottom: none;
  box-shadow: none;
}

.app-header__back {
  width: var(--header-btn-size);
  height: var(--header-btn-size);
  min-width: var(--header-btn-size);
  border: none;
  border-radius: var(--radius-full);
  background: var(--bg-elevated);
  color: var(--text-secondary);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  box-shadow: var(--shadow-sm);
  -webkit-tap-highlight-color: transparent;
}

.app-header__back:active {
  background: var(--bg-card-hover);
  color: var(--primary);
}

.app-header__spacer {
  width: var(--touch-min);
  min-width: var(--touch-min);
  flex-shrink: 0;
}

.app-header__title {
  flex: 1;
  min-width: 0;
  margin: 0;
  font-size: var(--top-title-size);
  font-weight: var(--top-title-weight);
  color: var(--text-primary);
  line-height: 1.25;
  text-align: start;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.app-header__title-slot {
  flex: 1;
  min-width: 0;
  display: flex;
  justify-content: center;
}

.app-header__actions {
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: var(--touch-min);
  justify-content: flex-end;
}
</style>
