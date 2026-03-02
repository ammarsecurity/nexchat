import { createI18n } from 'vue-i18n'
import ar from './locales/ar'
import en from './locales/en'

const savedLocale = localStorage.getItem('nexchat_locale') || 'ar'

export const i18n = createI18n({
  legacy: false,
  locale: savedLocale,
  fallbackLocale: 'ar',
  messages: {
    ar,
    en
  }
})
