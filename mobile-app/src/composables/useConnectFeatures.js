import { ref, computed } from 'vue'
import api from '../services/api'
import {
  getRandomChatEnabled,
  getCodeConnectFeaturesEnabled,
  getConnectHubEnabled,
  getMessagingOnlyMode,
  resetConnectFeaturesCache
} from '../services/siteContentFlags'

const randomChatEnabled = ref(false)
const codeConnectEnabled = ref(false)
const loaded = ref(false)
let loadPromise = null

export function useConnectFeatures() {
  const messagingOnlyMode = computed(
    () => loaded.value && !randomChatEnabled.value && !codeConnectEnabled.value
  )
  const connectHubEnabled = computed(
    () => loaded.value && (randomChatEnabled.value || codeConnectEnabled.value)
  )

  async function loadConnectFeatures() {
    if (loaded.value) {
      return {
        randomChatEnabled: randomChatEnabled.value,
        codeConnectEnabled: codeConnectEnabled.value,
        messagingOnlyMode: messagingOnlyMode.value,
        connectHubEnabled: connectHubEnabled.value
      }
    }
    if (!loadPromise) {
      loadPromise = Promise.all([
        getRandomChatEnabled(api),
        getCodeConnectFeaturesEnabled(api)
      ]).then(([random, code]) => {
        randomChatEnabled.value = random
        codeConnectEnabled.value = code
        loaded.value = true
        return {
          randomChatEnabled: random,
          codeConnectEnabled: code,
          messagingOnlyMode: !random && !code,
          connectHubEnabled: random || code
        }
      }).finally(() => {
        loadPromise = null
      })
    }
    return loadPromise
  }

  async function refreshConnectFeatures() {
    resetConnectFeaturesCache()
    loaded.value = false
    loadPromise = null
    return loadConnectFeatures()
  }

  return {
    randomChatEnabled,
    codeConnectEnabled,
    loaded,
    messagingOnlyMode,
    connectHubEnabled,
    loadConnectFeatures,
    refreshConnectFeatures,
    getConnectHubEnabled: () => getConnectHubEnabled(api),
    getMessagingOnlyMode: () => getMessagingOnlyMode(api)
  }
}
