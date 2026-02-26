<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { RouterView } from 'vue-router'
import NoConnectionView from './views/NoConnectionView.vue'

const isOnline = ref(navigator.onLine)

function handleOnline() {
  isOnline.value = true
}
function handleOffline() {
  isOnline.value = false
}

onMounted(() => {
  window.addEventListener('online', handleOnline)
  window.addEventListener('offline', handleOffline)
})
onUnmounted(() => {
  window.removeEventListener('online', handleOnline)
  window.removeEventListener('offline', handleOffline)
})
</script>

<template>
  <div id="app-root">
    <NoConnectionView v-if="!isOnline" />
    <RouterView v-else v-slot="{ Component }">
      <Transition name="page" mode="out-in">
        <component :is="Component" />
      </Transition>
    </RouterView>
  </div>
</template>

<style>
#app-root {
  height: 100%;
  width: 100%;
  position: relative;
  overflow: hidden;
}
</style>
