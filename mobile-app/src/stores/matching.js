import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useMatchingStore = defineStore('matching', () => {
  const status = ref('idle') // idle | searching | matched
  const genderFilter = ref('all') // all | male | female
  const incomingConnectionRequest = ref(null)

  function setSearching() { status.value = 'searching' }
  function setMatched() { status.value = 'matched' }
  function setIdle() { status.value = 'idle' }
  function setIncomingConnectionRequest(data) { incomingConnectionRequest.value = data }
  function clearIncomingConnectionRequest() { incomingConnectionRequest.value = null }

  return { status, genderFilter, incomingConnectionRequest, setSearching, setMatched, setIdle, setIncomingConnectionRequest, clearIncomingConnectionRequest }
})
