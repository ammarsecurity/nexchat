import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useConversationStore = defineStore('conversation', () => {
  const conversationId = ref(null)
  const partner = ref(null)
  const messages = ref([])
  const partnerTyping = ref(false)
  const partnerLastReadAt = ref(null)

  function setConversation(id, partnerInfo) {
    conversationId.value = id
    partner.value = partnerInfo
    messages.value = []
    partnerTyping.value = false
    partnerLastReadAt.value = null
  }

  function setPartnerLastReadAt(at) {
    partnerLastReadAt.value = at
  }

  function setMessagesRead(messageIds) {
    const ids = new Set((messageIds || []).map(String))
    messages.value.forEach(m => {
      if (ids.has(String(m.id || m.Id))) m.isRead = true
    })
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

  function removeMessage(messageId) {
    messages.value = messages.value.filter(m => m.id !== messageId && m.Id !== messageId)
  }

  function setMessageDeletedForEveryone(messageId) {
    const m = messages.value.find(x => (x.id || x.Id) === messageId)
    if (m) m.deletedForEveryone = true
  }

  function updatePendingMessage(serverMsg) {
    const type = serverMsg.type || 'text'
    const serverSender = String(serverMsg.senderId || '')
    const isMediaType = type === 'audio' || type === 'image'
    const idx = messages.value.findIndex(m => {
      if (m.status !== 'pending' || String(m.senderId || '') !== serverSender || (m.type || 'text') !== type) return false
      if (isMediaType) return true
      return m.content === serverMsg.content
    })
    if (idx >= 0) {
      messages.value[idx] = { ...serverMsg, status: 'sent' }
    }
  }

  function clearConversation() {
    conversationId.value = null
    partner.value = null
    messages.value = []
    partnerTyping.value = false
    partnerLastReadAt.value = null
  }

  return {
    conversationId,
    partner,
    messages,
    partnerTyping,
    partnerLastReadAt,
    setConversation,
    setPartnerLastReadAt,
    setMessagesRead,
    addMessage,
    updateMessage,
    removeMessage,
    setMessageDeletedForEveryone,
    updatePendingMessage,
    clearConversation
  }
})
