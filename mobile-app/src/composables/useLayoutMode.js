import { ref, computed, onMounted, onUnmounted } from 'vue'

export const DESKTOP_MIN_WIDTH = 1024
export const DESKTOP_MEDIA_QUERY = `(min-width: ${DESKTOP_MIN_WIDTH}px)`

const isDesktop = ref(
  typeof window !== 'undefined' && window.matchMedia(DESKTOP_MEDIA_QUERY).matches
)

let mq = null
let listenerCount = 0

function syncLayoutClass() {
  const desktop = mq?.matches ?? (typeof window !== 'undefined' && window.innerWidth >= DESKTOP_MIN_WIDTH)
  isDesktop.value = desktop
  if (typeof document !== 'undefined') {
    document.documentElement.classList.toggle('layout-desktop', desktop)
  }
}

function attachListener() {
  if (typeof window === 'undefined' || mq) return
  mq = window.matchMedia(DESKTOP_MEDIA_QUERY)
  syncLayoutClass()
  mq.addEventListener('change', syncLayoutClass)
}

function detachListener() {
  if (listenerCount > 0 || !mq) return
  mq.removeEventListener('change', syncLayoutClass)
  mq = null
}

function subscribe() {
  listenerCount += 1
  if (listenerCount === 1) attachListener()
}

function unsubscribe() {
  listenerCount = Math.max(0, listenerCount - 1)
  if (listenerCount === 0) detachListener()
}

/** Shared layout mode — safe to call from multiple components (ref-counted listener). */
export function useLayoutMode() {
  onMounted(subscribe)
  onUnmounted(unsubscribe)

  return {
    isDesktop,
    isMobile: computed(() => !isDesktop.value)
  }
}

// Apply class before first paint when possible
if (typeof window !== 'undefined') {
  syncLayoutClass()
}
