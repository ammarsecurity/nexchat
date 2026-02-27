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

  function updateMessage(tempId, updates) {
    const idx = messages.value.findIndex(m => m.tempId === tempId)
    if (idx >= 0) {
      messages.value[idx] = { ...messages.value[idx], ...updates }
    }
  }

  function updatePendingMessage(serverMsg) {
    const type = serverMsg.type || 'text'
    const serverSender = String(serverMsg.senderId || '')
    let idx = messages.value.findIndex(m =>
      m.status === 'pending' &&
      String(m.senderId || '') === serverSender &&
      m.content === serverMsg.content &&
      (m.type || 'text') === type
    )
    if (idx < 0) {
      idx = messages.value.findIndex(m =>
        m.status === 'pending' &&
        m.content === serverMsg.content &&
        (m.type || 'text') === type
      )
    }
    if (idx >= 0) {
      messages.value[idx] = {
        ...serverMsg,
        status: 'sent'
      }
    }
  }

  function clearSession() {
    session.value = null
    partner.value = null
    messages.value = []
    partnerTyping.value = false
    sessionTimer.value = 0
  }

  return { session, partner, messages, partnerTyping, sessionTimer, setSession, addMessage, updateMessage, updatePendingMessage, clearSession }
})
