import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { createVuetify } from 'vuetify'
import { ar, en } from 'vuetify/locale'
import * as components from 'vuetify/components'
import * as directives from 'vuetify/directives'
import 'vuetify/styles'
import '@mdi/font/css/materialdesignicons.css'
import App from './App.vue'
import router from './router'
import './assets/main.css'

const vuetify = createVuetify({
  components,
  directives,
  locale: {
    locale: 'ar',
    fallback: 'en',
    messages: { ar, en }
  },
  theme: {
    defaultTheme: 'nexchatDark',
    themes: {
      nexchatDark: {
        dark: true,
        colors: {
          background: '#0D0D1A',
          surface: '#13132A',
          primary: '#6C63FF',
          secondary: '#FF6584',
          accent: '#00D4FF',
          error: '#FF5252',
          warning: '#FFB74D',
          success: '#4CAF50',
        }
      }
    }
  }
})

const app = createApp(App)
app.use(createPinia())
app.use(router)
app.use(vuetify)
app.mount('#app')
