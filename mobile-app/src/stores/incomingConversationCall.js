import { defineStore } from 'pinia'

/**
 * طلب مكالمة فيديو/صوت وارد من محادثة خاصة — يُعرض من أي صفحة (SignalR Clients.User).
 */
export const useIncomingConversationCallStore = defineStore('incomingConversationCall', {
  state: () => ({
    conversationId: null,
    voiceOnly: false,
    callerName: '',
    callerAvatar: null
  }),
  getters: {
    visible: (s) => !!s.conversationId
  },
  actions: {
    setIncoming({ conversationId, voiceOnly, callerName, callerAvatar }) {
      this.conversationId = conversationId ? String(conversationId) : null
      this.voiceOnly = !!voiceOnly
      this.callerName = callerName || ''
      this.callerAvatar = callerAvatar || null
    },
    clear() {
      this.conversationId = null
      this.voiceOnly = false
      this.callerName = ''
      this.callerAvatar = null
    }
  }
})
