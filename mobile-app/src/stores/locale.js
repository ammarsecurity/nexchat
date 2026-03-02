import { defineStore } from 'pinia'

const LOCALE_KEY = 'nexchat_locale'
const DEFAULT_LOCALE = 'ar'

export const useLocaleStore = defineStore('locale', {
  state: () => ({
    locale: localStorage.getItem(LOCALE_KEY) || DEFAULT_LOCALE
  }),
  getters: {
    isRtl: (state) => state.locale === 'ar',
    htmlLang: (state) => state.locale,
    htmlDir: (state) => (state.locale === 'ar' ? 'rtl' : 'ltr')
  },
  actions: {
    setLocale(locale, i18n) {
      if (locale !== 'ar' && locale !== 'en') return
      this.locale = locale
      localStorage.setItem(LOCALE_KEY, locale)
      if (i18n) {
        i18n.global.locale.value = locale
      }
    },
    toggleLocale(i18n) {
      this.setLocale(this.locale === 'ar' ? 'en' : 'ar', i18n)
    }
  }
})
