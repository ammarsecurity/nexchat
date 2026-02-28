import * as signalR from '@microsoft/signalr'

const BASE_URL = import.meta.env.VITE_API_URL?.replace('/api', '') || 'http://localhost:5000'

function createHub(path) {
  return new signalR.HubConnectionBuilder()
    .withUrl(`${BASE_URL}${path}`, {
      accessTokenFactory: () => localStorage.getItem('nexchat_token') || ''
    })
    .withAutomaticReconnect()
    .configureLogging(signalR.LogLevel.Warning)
    .build()
}

export const matchingHub = createHub('/hubs/matching')
export const chatHub = createHub('/hubs/chat')

export async function startHub(hub) {
  if (hub.state === signalR.HubConnectionState.Disconnected) {
    await hub.start()
  }
}

/**
 * التأكد من اتصال الـ hub قبل تنفيذ أي عملية.
 * إذا كان الاتصال منقطعاً أو قيد إعادة الاتصال، ينتظر حتى يتصل تلقائياً.
 */
export async function ensureConnected(hub, timeoutMs = 15000) {
  if (hub.state === signalR.HubConnectionState.Connected) return
  if (hub.state === signalR.HubConnectionState.Disconnected) {
    await hub.start()
    return
  }
  const start = Date.now()
  while (hub.state !== signalR.HubConnectionState.Connected) {
    if (Date.now() - start > timeoutMs) throw new Error('انتهت مهلة الاتصال')
    await new Promise((r) => setTimeout(r, 200))
  }
}

export async function stopHub(hub) {
  if (hub.state !== signalR.HubConnectionState.Disconnected) {
    await hub.stop()
  }
}
