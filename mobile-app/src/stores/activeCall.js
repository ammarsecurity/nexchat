import { defineStore } from 'pinia'

/**
 * حالة مكالمة LiveKit عند التصغير والانتقال لشاشة الدردشة النصية.
 */
export const useActiveCallStore = defineStore('activeCall', {
  state: () => ({
    minimized: false,
    sessionId: null,
    voiceOnly: false,
    isConversation: false,
    partnerName: '',
    partnerAvatar: null,
    /** لتحديث الصورة لحظياً عند UserAvatarUpdated */
    partnerUserId: null,
    /** وقت بدء المكالمة (لحساب المدة) */
    startedAt: null
  }),
  getters: {
    showFloatingBar: (s) => s.minimized && !!s.sessionId
  },
  actions: {
    /**
     * يُستدعى عند بدء واجهة المكالمة أو عند التصغير لضمان حفظ البيانات.
     */
    syncMeta({ sessionId, voiceOnly, isConversation, partnerName, partnerAvatar, partnerUserId }) {
      this.sessionId = sessionId
      this.voiceOnly = voiceOnly
      this.isConversation = isConversation
      this.partnerName = partnerName || ''
      this.partnerAvatar = partnerAvatar || null
      this.partnerUserId = partnerUserId ?? null
      if (!this.startedAt) this.startedAt = Date.now()
    },
    minimize() {
      this.minimized = true
    },
    expand() {
      this.minimized = false
    },
    clear() {
      this.minimized = false
      this.sessionId = null
      this.voiceOnly = false
      this.isConversation = false
      this.partnerName = ''
      this.partnerAvatar = null
      this.partnerUserId = null
      this.startedAt = null
    }
  }
})
