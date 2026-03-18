import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useConversationsListStore = defineStore('conversationsList', () => {
  const list = ref([])

  function setList(items) {
    list.value = items ?? []
  }

  function updateConversation(conversationId, updates, incrementUnreadForRecipient = false) {
    const id = String(conversationId)
    const idx = list.value.findIndex(c => String(c.id ?? c.Id) === id)
    if (idx < 0) return false
    const oldItem = list.value[idx]
    const item = { ...oldItem, ...updates }
    if (incrementUnreadForRecipient) {
      const current = item.unreadCount ?? item.UnreadCount ?? 0
      item.unreadCount = current + 1
      item.UnreadCount = item.unreadCount
    }
    const hasNewMessage = updates.lastMessageAt != null || updates.LastMessageAt != null
    if (hasNewMessage) {
      list.value.splice(idx, 1)
      list.value.unshift(item)
    } else {
      list.value[idx] = item
    }
    list.value.sort((a, b) => {
      const aPinned = a.isPinned ?? a.IsPinned ?? false
      const bPinned = b.isPinned ?? b.IsPinned ?? false
      if (aPinned !== bPinned) return bPinned ? 1 : -1
      const ta = a.lastMessageAt ?? a.LastMessageAt ?? 0
      const tb = b.lastMessageAt ?? b.LastMessageAt ?? 0
      return new Date(tb) - new Date(ta)
    })
    return true
  }

  function removeConversation(conversationId) {
    const id = String(conversationId)
    list.value = list.value.filter(c => String(c.id || c.Id) !== id)
  }

  return {
    list,
    setList,
    updateConversation,
    removeConversation
  }
})
