import { defineStore } from 'pinia'
import { ref, onMounted, onUnmounted } from 'vue'

export const useNetworkStore = defineStore('network', () => {
  const isOnline = ref(typeof navigator !== 'undefined' ? navigator.onLine : true)

  function setOnline(value) {
    isOnline.value = !!value
  }

  function setupListeners() {
    if (typeof window === 'undefined') return
    const onOnline = () => { isOnline.value = true }
    const onOffline = () => { isOnline.value = false }
    window.addEventListener('online', onOnline)
    window.addEventListener('offline', onOffline)
    return () => {
      window.removeEventListener('online', onOnline)
      window.removeEventListener('offline', onOffline)
    }
  }

  return { isOnline, setOnline, setupListeners }
})
