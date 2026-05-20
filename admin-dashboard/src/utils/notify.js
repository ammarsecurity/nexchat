import { useNotifyStore } from '../stores/notify'

/** Toast موحّد بدل alert — للاستخدام داخل وخارج setup */
export const notify = {
  success: (msg) => useNotifyStore().success(msg),
  error: (msg) => useNotifyStore().error(msg),
  info: (msg) => useNotifyStore().info(msg),
  warning: (msg) => useNotifyStore().warning(msg)
}
