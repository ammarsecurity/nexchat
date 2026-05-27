<script setup>
defineProps({
  title: { type: String, default: '' },
  description: { type: String, default: '' },
  compact: { type: Boolean, default: false }
})
</script>

<template>
  <div class="empty-state-ui" :class="{ 'empty-state-ui--compact': compact }">
    <div v-if="$slots.icon" class="empty-state-ui__icon">
      <slot name="icon" />
    </div>
    <h2 v-if="title" class="empty-state-ui__title">{{ title }}</h2>
    <p v-if="description" class="empty-state-ui__desc">{{ description }}</p>
    <div v-if="$slots.action" class="empty-state-ui__action">
      <slot name="action" />
    </div>
  </div>
</template>

<style scoped>
.empty-state-ui {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 40px var(--spacing) 32px;
  gap: 12px;
}

.empty-state-ui--compact {
  padding: 24px var(--spacing);
}

.empty-state-ui__icon {
  width: 72px;
  height: 72px;
  border-radius: var(--radius-xl);
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--primary-soft);
  color: var(--primary);
  margin-bottom: 4px;
  box-shadow: var(--shadow-sm);
}

.empty-state-ui__icon :deep(svg) {
  width: 32px;
  height: 32px;
}

.empty-state-ui__title {
  margin: 0;
  font-size: var(--text-lg);
  font-weight: 700;
  color: var(--text-primary);
  line-height: 1.35;
}

.empty-state-ui__desc {
  margin: 0;
  font-size: var(--text-sm);
  color: var(--text-secondary);
  line-height: 1.5;
  max-width: 280px;
}

.empty-state-ui__action {
  margin-top: 8px;
}
</style>
