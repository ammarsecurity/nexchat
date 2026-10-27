import { ref, computed } from 'vue'
import api from '../services/api'
import {
  getRandomChatEnabled,
  getCodeConnectFeaturesEnabled,
  getDiscoverSwipeEnabled,
  getConnectHubEnabled,
  getMessagingOnlyMode,
  resetConnectFeaturesCache
} from '../services/siteContentFlags'

const randomChatEnabled = ref(false)
const codeConnectEnabled = ref(false)
const discoverSwipeEnabled = ref(false)
const loaded = ref(false)
let loadPromise = null

export function useConnectFeatures() {
  const messagingOnlyMode = computed(
    () =>
      loaded.value &&
      !randomChatEnabled.value &&
      !codeConnectEnabled.value &&
      !discoverSwipeEnabled.value
  )
  const connectHubEnabled = computed(
    () =>
      loaded.value &&
      (randomChatEnabled.value || codeConnectEnabled.value || discoverSwipeEnabled.value)
  )

  async function loadConnectFeatures() {
    if (loaded.value) {
      return {
        randomChatEnabled: randomChatEnabled.value,
        codeConnectEnabled: codeConnectEnabled.value,
        discoverSwipeEnabled: discoverSwipeEnabled.value,
        messagingOnlyMode: messagingOnlyMode.value,
        connectHubEnabled: connectHubEnabled.value
      }
    }
    if (!loadPromise) {
      loadPromise = Promise.all([
        getRandomChatEnabled(api),
        getCodeConnectFeaturesEnabled(api),
        getDiscoverSwipeEnabled(api)
      ]).then(([random, code, discover]) => {
        randomChatEnabled.value = random
        codeConnectEnabled.value = code
        discoverSwipeEnabled.value = discover
        loaded.value = true
        return {
          randomChatEnabled: random,
          codeConnectEnabled: code,
          discoverSwipeEnabled: discover,
          messagingOnlyMode: !random && !code && !discover,
          connectHubEnabled: random || code || discover
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
    discoverSwipeEnabled,
    loaded,
    messagingOnlyMode,
    connectHubEnabled,
    loadConnectFeatures,
    refreshConnectFeatures,
    getConnectHubEnabled: () => getConnectHubEnabled(api),
    getMessagingOnlyMode: () => getMessagingOnlyMode(api)
  }
}
