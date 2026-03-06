import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { Capacitor } from '@capacitor/core'
import api from '../services/api'
import { initNotifications, clearUser } from '../services/notifications'

export const useAuthStore = defineStore('auth', () => {
  const token = ref(localStorage.getItem('nexchat_token') || '')
  const user = ref(JSON.parse(localStorage.getItem('nexchat_user') || 'null'))
  const avatar = ref(localStorage.getItem('nexchat_avatar') || null)
  const shouldPromptNotifications = ref(false)

  const isLoggedIn = computed(() => !!token.value)
  const avatarColor = computed(() => {
    if (!user.value) return '#6C63FF'
    const colors = ['#6C63FF', '#FF6584', '#00D4FF', '#FF8C42', '#A8FF78']
    const idx = user.value.name.charCodeAt(0) % colors.length
    return colors[idx]
  })

  async function register(name, password, gender, birthDate) {
    const res = await api.post('/auth/register', { name, password, gender, birthDate })
    await setAuth(res.data)
  }

  async function login(name, password) {
    const res = await api.post('/auth/login', { name, password })
    await setAuth(res.data)
  }

  async function setAuth(data) {
    token.value = data.token
    user.value = {
      id: data.userId,
      name: data.name,
      gender: data.gender,
      uniqueCode: data.uniqueCode,
      isFeatured: data.isFeatured ?? false
    }
    localStorage.setItem('nexchat_token', data.token)
    localStorage.setItem('nexchat_user', JSON.stringify(user.value))

    const isNative = Capacitor.isNativePlatform() && typeof window.cordova !== 'undefined'
    if (isNative) {
      const granted = await initNotifications(data.userId)
      if (!granted) shouldPromptNotifications.value = true
    }

    // Sync avatar from backend on login/register
    if (data.avatar !== undefined) {
      avatar.value = data.avatar || null
      if (data.avatar) localStorage.setItem('nexchat_avatar', data.avatar)
      else localStorage.removeItem('nexchat_avatar')
    }
  }

  async function setAvatar(val) {
    avatar.value = val
    if (val) localStorage.setItem('nexchat_avatar', val)
    else localStorage.removeItem('nexchat_avatar')
    // Persist to backend so partner sees it
    try { await api.put('/user/avatar', { avatar: val }) } catch {}
  }

  function logout() {
    clearUser()
    token.value = ''
    user.value = null
    avatar.value = null
    localStorage.removeItem('nexchat_token')
    localStorage.removeItem('nexchat_user')
    localStorage.removeItem('nexchat_avatar')
  }

  function dismissNotificationPrompt() {
    shouldPromptNotifications.value = false
  }

  return { token, user, avatar, isLoggedIn, avatarColor, shouldPromptNotifications, register, login, setAvatar, logout, dismissNotificationPrompt }
})
