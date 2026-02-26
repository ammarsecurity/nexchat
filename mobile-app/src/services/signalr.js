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
export const webrtcHub = createHub('/hubs/webrtc')

export async function startHub(hub) {
  if (hub.state === signalR.HubConnectionState.Disconnected) {
    await hub.start()
  }
}

export async function stopHub(hub) {
  if (hub.state !== signalR.HubConnectionState.Disconnected) {
    await hub.stop()
  }
}
