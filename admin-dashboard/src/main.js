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
  defaults: {
    VBtn: { rounded: 'lg' },
    VCard: { rounded: 'lg', elevation: 0 },
    VChip: { rounded: 'lg' },
    VTextField: { rounded: 'lg', variant: 'outlined', color: 'primary' },
    VSelect: { rounded: 'lg', variant: 'outlined', color: 'primary' },
    VTextarea: { rounded: 'lg', variant: 'outlined', color: 'primary' },
  },
  theme: {
    defaultTheme: 'nexchatLight',
    themes: {
      nexchatLight: {
        dark: false,
        colors: {
          background: '#F4F7FC',
          surface: '#FFFFFF',
          primary: '#2E86FB',
          secondary: '#0EA5E9',
          accent: '#22D3EE',
          error: '#EF4444',
          warning: '#F59E0B',
          success: '#22C55E',
          info: '#2E86FB',
          'on-background': '#0B1220',
          'on-surface': '#0B1220',
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
