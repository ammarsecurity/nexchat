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
export const conversationHub = createHub('/hubs/conversation')

export async function startHub(hub) {
  if (hub.state === signalR.HubConnectionState.Disconnected) {
    await hub.start()
  }
}

/**
 * التأكد من اتصال الـ hub قبل تنفيذ أي عملية.
 * - Connected: يعود فوراً.
 * - Disconnected: يبدأ الاتصال.
 * - Reconnecting/Connecting: ينتظر حتى يكتمل الاتصال تلقائياً (بدون استدعاء start لتجنب التداخل).
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

/** تشخيص الاتصال: يطبع في الكونسول معلومات عن الـ URL والـ REST/Hub ping */
export async function diagnoseConnection() {
  const base = import.meta.env.VITE_API_URL?.replace('/api', '') || 'http://localhost:5000'
  const restUrl = `${base}/api/dev/ping`
  console.log('[NexChat] API base:', base)
  console.log('[NexChat] SignalR URL:', `${base}/hubs/conversation`)
  try {
    const r = await fetch(restUrl)
    const j = await r.json()
    console.log('[NexChat] REST ping:', r.ok ? 'OK' : 'FAIL', j)
  } catch (e) {
    console.error('[NexChat] REST ping failed:', e.message)
  }
  try {
    await ensureConnected(conversationHub)
    const pong = await conversationHub.invoke('Ping')
    console.log('[NexChat] Hub ping:', pong)
  } catch (e) {
    console.error('[NexChat] Hub ping failed:', e.message)
  }
}
