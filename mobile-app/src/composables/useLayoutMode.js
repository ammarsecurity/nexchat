import { ref, computed, onMounted, onUnmounted } from 'vue'

export const DESKTOP_MIN_WIDTH = 1024
export const DESKTOP_MEDIA_QUERY = `(min-width: ${DESKTOP_MIN_WIDTH}px)`

export function useLayoutMode() {
  const isDesktop = ref(
    typeof window !== 'undefined' && window.matchMedia(DESKTOP_MEDIA_QUERY).matches
  )
  let mq = null

  function sync() {
    isDesktop.value = mq?.matches ?? window.innerWidth >= DESKTOP_MIN_WIDTH
    const html = document.documentElement
    if (html) {
      html.classList.toggle('layout-desktop', isDesktop.value)
    }
  }

  onMounted(() => {
    mq = window.matchMedia(DESKTOP_MEDIA_QUERY)
    sync()
    if (typeof window !== 'undefined') {
      document.documentElement.classList.toggle('layout-desktop', isDesktop.value)
    }
    mq.addEventListener('change', sync)
  })

  onUnmounted(() => {
    mq?.removeEventListener('change', sync)
    document.documentElement?.classList.remove('layout-desktop')
  })

  const isMobile = computed(() => !isDesktop.value)

  return { isDesktop, isMobile }
}
