import { defineStore } from 'pinia'
import { ref } from 'vue'
import api from '../services/api'

export const useMessageRequestsStore = defineStore('messageRequests', () => {
  const pendingCount = ref(0)

  async function fetchPendingCount() {
    try {
      const { data } = await api.get('/message-requests/pending-count', { skipGlobalLoader: true })
      pendingCount.value = typeof data === 'number' ? data : parseInt(data, 10) || 0
    } catch {
      pendingCount.value = 0
    }
  }

  function setPendingCount(n) {
    pendingCount.value = typeof n === 'number' ? n : parseInt(n, 10) || 0
  }

  return { pendingCount, fetchPendingCount, setPendingCount }
})
