import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useConversationStore = defineStore('conversation', () => {
  const conversationId = ref(null)
  const partner = ref(null)
  const isGroup = ref(false)
  const messages = ref([])
  const partnerTyping = ref(false)
  const partnerLastReadAt = ref(null)

  function setConversation(id, partnerInfo, options = {}) {
    conversationId.value = id
    partner.value = partnerInfo
    isGroup.value = options.isGroup ?? false
    messages.value = []
    partnerTyping.value = false
    partnerLastReadAt.value = null
  }

  function setMessages(msgs) {
    messages.value = Array.isArray(msgs) ? [...msgs] : []
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

  function updateMessageReactions(messageId, reactions) {
    const m = messages.value.find(x => String(x.id || x.Id) === String(messageId))
    if (m) m.reactions = Array.isArray(reactions) ? reactions : []
  }

  /**
   * Optimistic update: apply user's reaction locally before server confirms.
   * @param {string} messageId
   * @param {string} userId - current user id
   * @param {string} emoji - e.g. "❤️"
   */
  function applyOptimisticReaction(messageId, userId, emoji) {
    const m = messages.value.find(x => String(x.id || x.Id) === String(messageId))
    if (!m || !userId || !emoji) return
    const idStr = String(userId)
    const list = Array.isArray(m.reactions) ? m.reactions.map(r => ({
      emoji: r.emoji ?? r.Emoji,
      count: r.count ?? r.Count ?? 0,
      userIds: [...(r.userIds ?? r.UserIds ?? []).map(String)]
    })) : []
    const withoutMe = list.map(r => {
      const idx = r.userIds.indexOf(idStr)
      if (idx === -1) return r
      const next = { ...r, userIds: r.userIds.filter(u => u !== idStr), count: r.count - 1 }
      return next.count <= 0 ? null : next
    }).filter(Boolean)
    const wasMyEmoji = list.some(r => (r.emoji === emoji) && r.userIds.includes(idStr))
    if (wasMyEmoji) {
      m.reactions = withoutMe
      return
    }
    let found = false
    const nextList = withoutMe.map(r => {
      if (r.emoji !== emoji) return r
      found = true
      return { emoji: r.emoji, count: r.count + 1, userIds: [...r.userIds, idStr] }
    })
    if (!found) nextList.push({ emoji, count: 1, userIds: [idStr] })
    m.reactions = nextList
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
      return true
    }
    return false
  }

  function clearConversation() {
    conversationId.value = null
    partner.value = null
    isGroup.value = false
    messages.value = []
    partnerTyping.value = false
    partnerLastReadAt.value = null
  }

  return {
    conversationId,
    partner,
    isGroup,
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
    updateMessageReactions,
    applyOptimisticReaction,
    updatePendingMessage,
    clearConversation,
    setMessages
  }
})
