<script setup>
import { hasAvatarImage, fullMediaUrl, userInitial } from '../utils/media'

defineProps({
  name: { type: String, default: '' },
  avatar: { type: String, default: null },
  size: { type: [Number, String], default: 36 },
  color: { type: String, default: 'primary' },
})
</script>

<template>
  <v-avatar
    :size="size"
    :color="hasAvatarImage(avatar) ? undefined : color"
    :variant="hasAvatarImage(avatar) ? undefined : 'tonal'"
    class="avatar-circle"
  >
    <v-img
      v-if="hasAvatarImage(avatar)"
      :src="fullMediaUrl(avatar)"
      cover
      alt=""
    >
      <template #error>
        <div class="avatar-fallback">{{ userInitial(name) }}</div>
      </template>
    </v-img>
    <span v-else class="font-weight-bold">{{ userInitial(name) }}</span>
  </v-avatar>
</template>

<style scoped>
.avatar-circle {
  flex-shrink: 0;
  overflow: hidden;
}

.avatar-fallback {
  width: 100%;
  height: 100%;
  display: grid;
  place-items: center;
  background: rgba(46, 134, 251, 0.12);
  color: #2E86FB;
  font-weight: 700;
}
</style>
