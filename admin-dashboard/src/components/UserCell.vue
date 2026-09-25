<script setup>
import AvatarCircle from './AvatarCircle.vue'

defineProps({
  name: { type: String, default: '' },
  avatar: { type: String, default: null },
  subtitle: { type: String, default: '' },
  size: { type: [Number, String], default: 40 },
  color: { type: String, default: 'primary' },
})
</script>

<template>
  <div class="user-cell">
    <AvatarCircle :name="name" :avatar="avatar" :size="size" :color="color" />
    <div class="user-meta">
      <div class="user-name">{{ name || '—' }}</div>
      <div v-if="subtitle" class="user-sub">{{ subtitle }}</div>
    </div>
  </div>
</template>
