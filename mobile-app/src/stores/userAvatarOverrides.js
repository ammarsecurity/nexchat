import { defineStore } from 'pinia'
import { ref } from 'vue'

/**
 * صور المستخدمين المحدّثة عبر SignalR (UserAvatarUpdated) لعرضها فوراً في جهات الاتصال والبروفايل.
 */
export const useUserAvatarOverridesStore = defineStore('userAvatarOverrides', () => {
  const byUserId = ref({})

  function setAvatar(userId, avatar) {
    const id = String(userId)
    byUserId.value = { ...byUserId.value, [id]: avatar }
  }

  function avatarFor(userId) {
    if (userId == null) return null
    return byUserId.value[String(userId)] ?? null
  }

  return { byUserId, setAvatar, avatarFor }
})
