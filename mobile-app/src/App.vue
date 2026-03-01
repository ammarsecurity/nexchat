<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { RouterView, useRouter, useRoute } from 'vue-router'
import { Capacitor } from '@capacitor/core'
import { App } from '@capacitor/app'
import NoConnectionView from './views/NoConnectionView.vue'
import { useAuthStore } from './stores/auth'
import { matchingHub, startHub, stopHub } from './services/signalr'

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
  stopHub(matchingHub)
  useAuthStore().logout()
  router.replace('/login')
}

// إبقاء MatchingHub متصلاً عند المستخدم المسجّل - لاستقبال طلبات الاتصال بالكود من أي صفحة
watch([isOnline, () => auth.token], ([online, token]) => {
  if (online && token) {
    startHub(matchingHub).catch(() => {})
  } else {
    stopHub(matchingHub)
  }
}, { immediate: true })

// الصفحات الرئيسية: الضغط على الرجوع لا يخرج التطبيق
const tabRoots = ['/', '/onboarding', '/login', '/register', '/home', '/matching']

let backButtonListener = null

onMounted(() => {
  window.addEventListener('online', handleOnline)
  window.addEventListener('offline', handleOffline)
  window.addEventListener('nexchat:unauthorized', handleUnauthorized)

  if (Capacitor.isNativePlatform() && typeof App?.addListener === 'function') {
    App.addListener('backButton', () => {
      const path = route.path
      const isAtTabRoot = path === '/' || tabRoots.includes(path)

      if (!isAtTabRoot) {
        router.back()
      }
      // في الصفحات الرئيسية: لا نخرج التطبيق
    }).then((l) => { backButtonListener = l })
  }
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
