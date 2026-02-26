import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useChatStore = defineStore('chat', () => {
  const session = ref(null)
  const partner = ref(null)
  const messages = ref([])
  const partnerTyping = ref(false)
  const sessionTimer = ref(0)

  function setSession(sessionId, partnerInfo) {
    session.value = sessionId
    partner.value = partnerInfo
    messages.value = []
    partnerTyping.value = false
    sessionTimer.value = 0
  }

  function addMessage(msg) {
    messages.value.push(msg)
  }

  function clearSession() {
    session.value = null
    partner.value = null
    messages.value = []
    partnerTyping.value = false
    sessionTimer.value = 0
  }

  return { session, partner, messages, partnerTyping, sessionTimer, setSession, addMessage, clearSession }
})
