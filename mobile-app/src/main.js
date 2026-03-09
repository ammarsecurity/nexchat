import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import { i18n } from './i18n'
import { useThemeStore } from './stores/theme'
import { useLocaleStore } from './stores/locale'
import { initNotifications, clearUser } from './services/notifications'
import './assets/main.css'

const pinia = createPinia()
const app = createApp(App)
app.use(pinia)
app.use(i18n)
app.use(router)

// Sync locale store with i18n and apply saved locale
const localeStore = useLocaleStore()
i18n.global.locale.value = localeStore.locale

// Expose router for notification click handler
window.__nexchat_router__ = router

// Apply saved theme before mount
useThemeStore().applyTheme()
app.mount('#app')

// OneSignal + fetch profile contact status for existing sessions
;(async () => {
  const userStr = localStorage.getItem('nexchat_user')
  if (!userStr) return
  try {
    const { useAuthStore } = await import('./stores/auth')
    const auth = useAuthStore()
    if (auth.token && !auth.needsProfileContactRedirect) {
      await auth.fetchProfileContactStatus()
    }
    const user = JSON.parse(userStr)
    if (user?.id) {
      const granted = await initNotifications(user.id)
      if (!granted) auth.shouldPromptNotifications = true
    }
  } catch {}
})()
