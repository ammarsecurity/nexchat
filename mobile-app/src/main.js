import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import { useThemeStore } from './stores/theme'
import { initNotifications, clearUser } from './services/notifications'
import './assets/main.css'

const pinia = createPinia()
const app = createApp(App)
app.use(pinia)
app.use(router)

// Expose router for notification click handler
window.__nexchat_router__ = router

// Apply saved theme before mount
useThemeStore().applyTheme()
app.mount('#app')

// OneSignal: تهيئة عند وجود مستخدم مسجّل
const userStr = localStorage.getItem('nexchat_user')
if (userStr) {
  try {
    const user = JSON.parse(userStr)
    if (user?.id) initNotifications(user.id)
  } catch {}
}
