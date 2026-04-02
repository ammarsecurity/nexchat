import { defineStore } from 'pinia'
import { ref } from 'vue'
import { getStoredNotifications, clearStoredNotifications } from '../services/notifications'

export const useNotificationsStore = defineStore('notifications', () => {
  const list = ref([])

  function load() {
    list.value = getStoredNotifications()
  }

  function add(notification) {
    const item = { ...notification, id: (notification.id || Date.now()).toString() }
    list.value.unshift(item)
    if (list.value.length > 100) list.value.length = 100
    const raw = JSON.parse(localStorage.getItem('nexchat_notifications') || '[]')
    raw.unshift(item)
    if (raw.length > 100) raw.length = 100
    localStorage.setItem('nexchat_notifications', JSON.stringify(raw))
  }

  function clear() {
    list.value = []
    clearStoredNotifications()
  }

  return { list, load, add, clear }
})
