import { useNotifyStore } from '../stores/notify'

export const notify = {
  success: (msg) => useNotifyStore().success(msg),
  error: (msg) => useNotifyStore().error(msg),
  info: (msg) => useNotifyStore().info(msg)
}
