<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { RouterView, useRouter, useRoute } from 'vue-router'
import { useLocaleStore } from './stores/locale'
import { Capacitor } from '@capacitor/core'
import { App } from '@capacitor/app'
import NoConnectionView from './views/NoConnectionView.vue'
import IncomingConnectionRequestDialog from './components/IncomingConnectionRequestDialog.vue'
import RandomMatchConsentDialog from './components/RandomMatchConsentDialog.vue'
import IncomingConversationCallDialog from './components/IncomingConversationCallDialog.vue'
import UpdateRequiredModal from './components/UpdateRequiredModal.vue'
import LoaderOverlay from './components/LoaderOverlay.vue'
import { useApiLoadingStore } from './stores/apiLoading'
import { checkUpdateRequired } from './services/updateCheck'
import { useAuthStore } from './stores/auth'
import { useMatchingStore } from './stores/matching'
import { useChatStore } from './stores/chat'
import { matchingHub, conversationHub, startHub, stopHub, ensureConnected } from './services/signalr'
import { startIncomingCallSound, stopIncomingCallSound } from './utils/sounds'
import { useNetworkStore } from './stores/network'
import { useIncomingConversationCallStore } from './stores/incomingConversationCall'
import { useConversationsListStore } from './stores/conversationsList'
import { useActiveCallStore } from './stores/activeCall'
import { useUserAvatarOverridesStore } from './stores/userAvatarOverrides'
import { useConversationStore } from './stores/conversation'
import {
  parseIncomingConversationCallPayload,
  parseVideoCallAcceptedPayload
} from './utils/incomingSignalrPayload'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
const network = useNetworkStore()
const isOnline = computed(() => network.isOnline)
const showUpdateModal = ref(false)
const updateDownloadUrl = ref('')
const auth = useAuthStore()

async function runUpdateCheck() {
  if (!isOnline.value) return
  const { required, downloadUrl } = await checkUpdateRequired()
  if (required && downloadUrl) {
    updateDownloadUrl.value = downloadUrl
    showUpdateModal.value = true
  }
}

const apiLoading = useApiLoadingStore()
const showUpdateOnCurrentPage = computed(() => {
  const path = route.path
  if (path.startsWith('/chat/') || path.startsWith('/video/')) return false
  return showUpdateModal.value
})
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
const incomingConvCall = useIncomingConversationCallStore()
const conversationsList = useConversationsListStore()
const activeCall = useActiveCallStore()
const userAvatarOverrides = useUserAvatarOverridesStore()
const convStore = useConversationStore()

function handleOnline() {
  network.setOnline(true)
  runUpdateCheck()
}
function handleOffline() {
  network.setOnline(false)
}

function retryConnection() {
  if (navigator.onLine) {
    network.setOnline(true)
    window.location.reload()
  }
}

function handleUnauthorized() {
  stopHub(matchingHub)
  stopHub(conversationHub)
  incomingConvCall.clear()
  matching.clearPendingRandomMatch()
  stopIncomingCallSound()
  useAuthStore().logout()
  router.replace('/login')
}

async function restartRandomSearch() {
  matching.setSearching()
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('StartSearching', matching.genderFilter)
  } catch {}
}

function applyUserAvatarUpdated(payload) {
  const userId = payload?.userId ?? payload?.UserId
  const avatar = payload?.avatar ?? payload?.Avatar
  const uniqueCode = payload?.uniqueCode ?? payload?.UniqueCode
  if (userId == null) return
  userAvatarOverrides.setAvatar(userId, avatar)
  conversationsList.updatePartnerAvatarByUserId(userId, avatar)
  chat.patchPartnerFromBroadcast(userId, avatar, uniqueCode)
  convStore.patchPartnerAvatarFromBroadcast(userId, avatar, uniqueCode)
  matching.patchIncomingRequesterAvatar(userId, avatar)
  matching.patchPendingRandomPartnerAvatar(userId, avatar, uniqueCode)
  if (activeCall.partnerUserId && String(activeCall.partnerUserId) === String(userId)) {
    activeCall.partnerAvatar = avatar
  }
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
    const requiresPairingAccept = data.requiresPairingAccept ?? data.RequiresPairingAccept ?? false
    if (requiresPairingAccept) {
      matching.setPendingRandomMatch({ sessionId, partner })
      return
    }
    matching.armSkipNextMatchingUnmountCancel()
    chat.setSession(sessionId, partner)
    matching.setMatched()
    router.push(`/chat/${sessionId}`)
  })

  matchingHub.off('RandomMatchReady')
  matchingHub.on('RandomMatchReady', (data) => {
    const sessionId = data.sessionId ?? data.SessionId
    const partner = data.partner ?? data.Partner
    matching.clearPendingRandomMatch()
    matching.armSkipNextMatchingUnmountCancel()
    chat.setSession(sessionId, partner)
    matching.setMatched()
    router.push(`/chat/${sessionId}`)
  })

  matchingHub.off('RandomMatchPartnerDeclined')
  matchingHub.on('RandomMatchPartnerDeclined', () => {
    matching.clearPendingRandomMatch()
    restartRandomSearch()
  })

  matchingHub.off('RandomMatchDeclined')
  matchingHub.on('RandomMatchDeclined', () => {
    matching.clearPendingRandomMatch()
    restartRandomSearch()
  })

}

function setupConversationHubGlobalListeners() {
  conversationHub.off('IncomingVideoCall')
  conversationHub.on('IncomingVideoCall', (cid, voiceOnly, callerName, callerAvatar) => {
    const parsed = parseIncomingConversationCallPayload(cid, voiceOnly, callerName, callerAvatar)
    if (!parsed) return
    if (route.path.startsWith('/video/')) {
      const vid = route.params.sessionId
      if (vid != null && String(vid) === String(parsed.conversationId)) return
    }
    incomingConvCall.setIncoming(parsed)
  })

  conversationHub.off('VideoCallAccepted')
  conversationHub.on('VideoCallAccepted', (cidStr, voiceOnly) => {
    const parsed = parseVideoCallAcceptedPayload(cidStr, voiceOnly)
    if (!parsed) return
    const cid = parsed.conversationId
    const vo = parsed.voiceOnly
    const list = conversationsList.list
    const item = list.find((c) => String(c.id ?? c.Id) === cid)
    const partnerName = item?.partnerName ?? item?.PartnerName ?? ''
    const partnerAvatar = item?.partnerAvatar ?? item?.PartnerAvatar ?? null
    const partnerUserId = item?.partnerId ?? item?.PartnerId ?? null
    activeCall.syncMeta({
      sessionId: cid,
      voiceOnly: vo,
      isConversation: true,
      partnerName,
      partnerAvatar,
      partnerUserId
    })
    router.push({
      path: `/video/${cid}`,
      state: { initiator: true, voiceOnly: vo, fromConversation: true }
    })
  })

  conversationHub.off('UserAvatarUpdated')
  conversationHub.on('UserAvatarUpdated', applyUserAvatarUpdated)
}

// إبقاء MatchingHub و ConversationHub متصلين عند المستخدم المسجّل — طلبات من أي صفحة
watch([() => network.isOnline, () => auth.token], ([online, token]) => {
  if (online && token) {
    setupMatchingHubListeners()
    setupConversationHubGlobalListeners()
    startHub(matchingHub).catch(() => {})
    startHub(conversationHub).catch(() => {})
  } else {
    stopHub(matchingHub)
    stopHub(conversationHub)
    incomingConvCall.clear()
    matching.clearPendingRandomMatch()
    stopIncomingCallSound()
  }
}, { immediate: true })

// الصفحات الرئيسية: الضغط على الرجوع لا يخرج التطبيق
const tabRoots = ['/', '/onboarding', '/login', '/register', '/home', '/matching']

let backButtonListener = null

onMounted(() => {
  network.setOnline(navigator.onLine)
  applyHtmlLocale()
  runUpdateCheck()
  window.addEventListener('online', handleOnline)
  window.addEventListener('offline', handleOffline)
  window.addEventListener('nexchat:unauthorized', handleUnauthorized)

  conversationHub.onreconnected(() => {
    if (auth.token) setupConversationHubGlobalListeners()
  })
  matchingHub.onreconnected(() => {
    if (auth.token) setupMatchingHubListeners()
  })

  if (Capacitor.isNativePlatform() && typeof App?.addListener === 'function') {
    App.addListener('appStateChange', ({ isActive }) => {
      if (isActive) runUpdateCheck()
    }).then(() => {})

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
    <NoConnectionView v-if="!isOnline && !auth.token" />
    <template v-else>
      <div v-if="!isOnline" class="offline-banner">
        <span>{{ t('noConnection.offlineBanner') }}</span>
        <button type="button" class="offline-retry" @click="retryConnection">
          {{ t('noConnection.retry') }}
        </button>
      </div>
      <div
        class="app-content"
        :class="{ 'has-offline-banner': !isOnline }"
      >
      <RouterView v-slot="{ Component }">
        <Transition name="page" mode="out-in">
          <component :is="Component" />
        </Transition>
      </RouterView>
      </div>
    </template>
    <IncomingConnectionRequestDialog v-if="auth.token" />
    <RandomMatchConsentDialog v-if="auth.token" />
    <IncomingConversationCallDialog v-if="auth.token" />
    <UpdateRequiredModal v-if="showUpdateOnCurrentPage" :download-url="updateDownloadUrl" />
    <LoaderOverlay :show="apiLoading.showOverlay" />
  </div>
</template>

<style>
#app-root {
  height: 100%;
  width: 100%;
  position: relative;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.app-content {
  flex: 1;
  min-height: 0;
  overflow: hidden;
  position: relative;
}

.offline-banner {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 10px 16px;
  background: var(--text-primary, #1a1a1a);
  color: var(--bg-primary, #fff);
  font-size: 14px;
  flex-wrap: wrap;
}
.offline-retry {
  padding: 6px 14px;
  border-radius: 8px;
  border: 1px solid currentColor;
  background: transparent;
  color: inherit;
  font-size: 13px;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.app-content.has-offline-banner {
  padding-top: 48px;
}
</style>
