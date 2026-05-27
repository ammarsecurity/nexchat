import { ref, onMounted, onUnmounted } from 'vue'

export function usePullToRefresh(onRefresh, { threshold = 72 } = {}) {
  const pullDistance = ref(0)
  const refreshing = ref(false)
  let startY = 0
  let tracking = false
  let el = null

  function canPull() {
    return el && el.scrollTop <= 0 && !refreshing.value
  }

  function onTouchStart(e) {
    if (!canPull()) return
    startY = e.touches[0].clientY
    tracking = true
  }

  function onTouchMove(e) {
    if (!tracking) return
    const dy = e.touches[0].clientY - startY
    if (dy <= 0) {
      pullDistance.value = 0
      return
    }
    pullDistance.value = Math.min(dy * 0.45, threshold * 1.4)
    if (pullDistance.value > 8) e.preventDefault()
  }

  async function onTouchEnd() {
    if (!tracking) return
    tracking = false
    if (pullDistance.value >= threshold && !refreshing.value) {
      refreshing.value = true
      try {
        await onRefresh()
      } finally {
        refreshing.value = false
      }
    }
    pullDistance.value = 0
  }

  function bind(node) {
    el = node
    el?.addEventListener('touchstart', onTouchStart, { passive: true })
    el?.addEventListener('touchmove', onTouchMove, { passive: false })
    el?.addEventListener('touchend', onTouchEnd, { passive: true })
  }

  function unbind() {
    el?.removeEventListener('touchstart', onTouchStart)
    el?.removeEventListener('touchmove', onTouchMove)
    el?.removeEventListener('touchend', onTouchEnd)
    el = null
  }

  onUnmounted(unbind)

  return { pullDistance, refreshing, bind, unbind }
}
