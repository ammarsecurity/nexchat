import { defineStore } from 'pinia'
import { ref } from 'vue'

const STORAGE_KEY = 'nexchat_theme'

export const useThemeStore = defineStore('theme', () => {
  const isLight = ref(localStorage.getItem(STORAGE_KEY) === 'light')

  function toggleTheme() {
    isLight.value = !isLight.value
    applyTheme()
    localStorage.setItem(STORAGE_KEY, isLight.value ? 'light' : 'dark')
  }

  function applyTheme() {
    if (typeof document === 'undefined') return
    const html = document.documentElement
    if (isLight.value) {
      html.classList.add('light')
      html.setAttribute('data-theme', 'light')
    } else {
      html.classList.remove('light')
      html.removeAttribute('data-theme')
    }
    // theme-color for mobile browser bar
    const meta = document.querySelector('meta[name="theme-color"]')
    if (meta) meta.content = isLight.value ? '#F5F5FA' : '#0D0D1A'
    // favicon based on theme
    const favicon = document.querySelector('link[rel="icon"]')
    if (favicon) favicon.href = isLight.value ? '/logo-light.png' : '/logo.png'
  }

  // Apply on init
  applyTheme()

  return { isLight, toggleTheme, applyTheme }
})
