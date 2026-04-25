import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { getStoredNotifications, clearStoredNotifications, markNotificationRead, markAllNotificationsRead } from '../services/notifications'

export const useNotificationsStore = defineStore('notifications', () => {
  const list = ref([])
  const unreadCount = computed(() => list.value.filter(x => !x.isRead).length)

  function load() {
    list.value = getStoredNotifications()
  }

  function add(notification) {
    const item = { ...notification, id: (notification.id || Date.now()).toString(), isRead: notification.isRead === true ? true : false }
    if (list.value.some(x => String(x.id) === String(item.id))) return
    list.value.unshift(item)
    if (list.value.length > 100) list.value.length = 100
    const raw = JSON.parse(localStorage.getItem('nexchat_notifications') || '[]')
    raw.unshift(item)
    if (raw.length > 100) raw.length = 100
    localStorage.setItem('nexchat_notifications', JSON.stringify(raw))
  }

  function markRead(id) {
    const idx = list.value.findIndex(x => String(x.id) === String(id))
    if (idx >= 0 && !list.value[idx].isRead) {
      list.value[idx].isRead = true
      markNotificationRead(id)
    }
  }

  function markAllRead() {
    list.value = list.value.map(x => ({ ...x, isRead: true }))
    markAllNotificationsRead()
  }

  function clear() {
    list.value = []
    clearStoredNotifications()
  }

  return { list, unreadCount, load, add, clear, markRead, markAllRead }
})
