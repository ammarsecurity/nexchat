<script setup>
defineProps({
  rows: { type: Number, default: 6 }
})
</script>

<template>
  <div class="list-skeleton" aria-hidden="true">
    <div v-for="i in rows" :key="i" class="list-skeleton__row">
      <div class="list-skeleton__avatar skeleton-shimmer" />
      <div class="list-skeleton__body">
        <div class="list-skeleton__line skeleton-shimmer" style="width: 55%" />
        <div class="list-skeleton__line skeleton-shimmer list-skeleton__line--short" />
      </div>
    </div>
  </div>
</template>

<style scoped>
.list-skeleton {
  padding: 8px 0;
}

.list-skeleton__row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px var(--spacing);
}

.list-skeleton__avatar {
  width: 52px;
  height: 52px;
  border-radius: 50%;
  flex-shrink: 0;
}

.list-skeleton__body {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.list-skeleton__line {
  height: 12px;
  border-radius: 6px;
}

.list-skeleton__line--short {
  width: 72%;
}
</style>
