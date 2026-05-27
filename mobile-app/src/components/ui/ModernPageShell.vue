<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronLeft, ChevronRight } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../../stores/locale'

const props = defineProps({
  title: { type: String, default: '' },
  showBack: { type: Boolean, default: true },
  backTo: { type: String, default: '' },
  overlayNav: { type: Boolean, default: false }
})

const router = useRouter()
const { t } = useI18n()
const localeStore = useLocaleStore()
const scrollEl = ref(null)

const BackIcon = computed(() => (localeStore.isRtl ? ChevronRight : ChevronLeft))

function onBack() {
  if (props.backTo) router.replace(props.backTo)
  else router.back()
}

defineExpose({ scrollEl })
</script>

<template>
  <div class="modern-page page">
    <header
      class="modern-page__nav"
      :class="{ 'modern-page__nav--overlay': overlayNav }"
    >
      <button
        v-if="showBack"
        type="button"
        class="modern-glass-btn"
        :aria-label="t('common.back')"
        @click="onBack"
      >
        <component :is="BackIcon" :size="22" stroke-width="2" />
      </button>
      <span v-else class="modern-page__nav-spacer" aria-hidden="true" />

      <h1 v-if="title" class="modern-page__title">{{ title }}</h1>
      <div v-else class="modern-page__nav-spacer" aria-hidden="true" />

      <div class="modern-page__actions">
        <slot name="actions" />
        <span v-if="!$slots.actions" class="modern-page__nav-spacer" aria-hidden="true" />
      </div>
    </header>

    <slot name="before-scroll" />

    <div ref="scrollEl" class="modern-page__scroll">
      <slot />
    </div>
  </div>
</template>

<style scoped>
.modern-page__actions {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: var(--header-btn-size);
  justify-content: flex-end;
}
</style>
