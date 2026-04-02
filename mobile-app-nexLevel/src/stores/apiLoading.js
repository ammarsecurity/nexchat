import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export const useApiLoadingStore = defineStore('apiLoading', () => {
  const activeCount = ref(0)
  const showDelay = 300
  let showTimer = null

  const isLoading = computed(() => activeCount.value > 0)
  const _showOverlay = ref(false)

  const showOverlay = computed(() => _showOverlay.value)

  function startRequest() {
    activeCount.value++
    if (activeCount.value === 1 && !showTimer) {
      showTimer = setTimeout(() => {
        _showOverlay.value = true
        showTimer = null
      }, showDelay)
    }
  }

  function endRequest() {
    if (activeCount.value > 0) activeCount.value--
    if (activeCount.value === 0) {
      if (showTimer) {
        clearTimeout(showTimer)
        showTimer = null
      }
      _showOverlay.value = false
    }
  }

  return {
    activeCount,
    isLoading,
    showOverlay,
    startRequest,
    endRequest
  }
})
