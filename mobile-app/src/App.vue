<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { RouterView, useRouter, useRoute } from 'vue-router'
import NoConnectionView from './views/NoConnectionView.vue'
import { useAuthStore } from './stores/auth'

const isOnline = ref(navigator.onLine)
const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

function handleOnline() {
  isOnline.value = true
}
function handleOffline() {
  isOnline.value = false
}

function handleUnauthorized() {
  useAuthStore().logout()
  router.replace('/login')
}

function handleBackButton(event) {
  const path = route.path
  const canGoBack = event?.canGoBack ?? window.history.length > 1
  if (path === '/settings') {
    router.replace('/home')
  } else if (path === '/privacy') {
    router.replace(auth.token ? '/settings' : '/login')
  } else if (path.startsWith('/video/')) {
    const id = route.params.sessionId
    if (id) router.replace(`/chat/${id}`)
  } else if (path.startsWith('/chat/')) {
    router.replace('/home')
  } else if (path === '/matching') {
    router.replace('/home')
  } else if (canGoBack) {
    router.back()
  } else {
    import('@capacitor/app').then(({ App }) => App.minimizeApp?.()).catch(() => {})
  }
}

let backButtonListener = null

onMounted(() => {
  window.addEventListener('online', handleOnline)
  window.addEventListener('offline', handleOffline)
  window.addEventListener('nexchat:unauthorized', handleUnauthorized)

  import('@capacitor/app').then(({ App }) => {
    if (typeof App?.addListener === 'function') {
      App.addListener('backButton', (e) => handleBackButton(e)).then((l) => { backButtonListener = l })
    }
  }).catch(() => {})
})
onUnmounted(() => {
  window.removeEventListener('online', handleOnline)
  window.removeEventListener('offline', handleOffline)
  window.removeEventListener('nexchat:unauthorized', handleUnauthorized)
  backButtonListener?.remove?.()
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
