<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { RouterView, useRouter, useRoute } from 'vue-router'
import { useLocaleStore } from './stores/locale'
import { Capacitor } from '@capacitor/core'
import { App } from '@capacitor/app'
import NoConnectionView from './views/NoConnectionView.vue'
import IncomingConnectionRequestDialog from './components/IncomingConnectionRequestDialog.vue'
import { useAuthStore } from './stores/auth'
import { useMatchingStore } from './stores/matching'
import { useChatStore } from './stores/chat'
import { matchingHub, startHub, stopHub } from './services/signalr'
import { startIncomingCallSound, stopIncomingCallSound } from './utils/sounds'

const isOnline = ref(navigator.onLine)
const auth = useAuthStore()
const localeStore = useLocaleStore()

function applyHtmlLocale() {
  const html = document.documentElement
  if (html) {
    html.setAttribute('lang', localeStore.htmlLang)
    html.setAttribute('dir', localeStore.htmlDir)
  }
}

watch(() => localeStore.locale, applyHtmlLocale, { immediate: false })
const matching = useMatchingStore()
const chat = useChatStore()
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

function setupMatchingHubListeners() {
  matchingHub.off('IncomingConnectionRequest')
  matchingHub.on('IncomingConnectionRequest', (data) => {
    matching.setIncomingConnectionRequest({
      requesterId: data.requesterId ?? data.RequesterId,
      requesterName: data.requesterName ?? data.RequesterName,
      requesterGender: data.requesterGender ?? data.RequesterGender,
      requesterAvatar: data.requesterAvatar ?? data.RequesterAvatar,
      requesterIsFeatured: data.requesterIsFeatured ?? data.RequesterIsFeatured ?? false
    })
    startIncomingCallSound()
  })

  matchingHub.off('ConnectionRequestExpired')
  matchingHub.on('ConnectionRequestExpired', () => {
    stopIncomingCallSound()
    matching.clearIncomingConnectionRequest()
  })

  matchingHub.off('MatchFound')
  matchingHub.on('MatchFound', (data) => {
    const sessionId = data.sessionId ?? data.SessionId
    const partner = data.partner ?? data.Partner
    chat.setSession(sessionId, partner)
    matching.setMatched()
    router.push(`/chat/${sessionId}`)
  })
}

// إبقاء MatchingHub متصلاً عند المستخدم المسجّل - لاستقبال طلبات الاتصال بالكود من أي صفحة
watch([isOnline, () => auth.token], ([online, token]) => {
  if (online && token) {
    setupMatchingHubListeners()
    startHub(matchingHub).catch(() => {})
  } else {
    stopHub(matchingHub)
  }
}, { immediate: true })

// الصفحات الرئيسية: الضغط على الرجوع لا يخرج التطبيق
const tabRoots = ['/', '/onboarding', '/login', '/register', '/home', '/matching']

let backButtonListener = null

onMounted(() => {
  applyHtmlLocale()
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
    <IncomingConnectionRequestDialog v-if="auth.token" />
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
