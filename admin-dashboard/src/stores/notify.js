import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useNotifyStore = defineStore('notify', () => {
  const visible = ref(false)
  const message = ref('')
  const type = ref('info')
  let hideTimer = null

  function show(msg, toastType = 'info') {
    if (!msg) return
    message.value = String(msg)
    type.value = toastType
    visible.value = true
    if (hideTimer) clearTimeout(hideTimer)
    hideTimer = setTimeout(() => {
      visible.value = false
    }, 3800)
  }

  function success(msg) {
    show(msg, 'success')
  }

  function error(msg) {
    show(msg, 'error')
  }

  function info(msg) {
    show(msg, 'info')
  }

  function warning(msg) {
    show(msg, 'warning')
  }

  function close() {
    visible.value = false
    if (hideTimer) clearTimeout(hideTimer)
  }

  return { visible, message, type, show, success, error, info, warning, close }
})
