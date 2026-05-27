import { ref, onMounted, onUnmounted } from 'vue'

export function useReducedMotion() {
  const reducedMotion = ref(false)
  let mq = null

  onMounted(() => {
    if (typeof window === 'undefined' || !window.matchMedia) return
    mq = window.matchMedia('(prefers-reduced-motion: reduce)')
    reducedMotion.value = mq.matches
    const onChange = (e) => { reducedMotion.value = e.matches }
    mq.addEventListener?.('change', onChange)
    mq.onchange = onChange
  })

  onUnmounted(() => {
    if (!mq) return
    mq.removeEventListener?.('change', () => {})
  })

  return { reducedMotion }
}
