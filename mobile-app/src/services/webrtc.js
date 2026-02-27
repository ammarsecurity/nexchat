import SimplePeer from 'simple-peer'
import { webrtcHub, startHub } from './signalr'

let peer = null

const ICE_SERVERS = {
  iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' }
  ]
}

export async function initWebRTC(sessionId, isInitiator, localStream, onRemoteStream, onError) {
  await startHub(webrtcHub)
  await webrtcHub.invoke('JoinVideoSession', sessionId)
  // Give the other peer time to join the session group before signaling
  if (isInitiator) await new Promise(r => setTimeout(r, 800))

  peer = new SimplePeer({
    initiator: isInitiator,
    stream: localStream,
    config: ICE_SERVERS,
    trickle: true
  })

  peer.on('signal', async (data) => {
    if (data.type === 'offer') {
      await webrtcHub.invoke('SendOffer', sessionId, data)
    } else if (data.type === 'answer') {
      await webrtcHub.invoke('SendAnswer', sessionId, data)
    } else {
      await webrtcHub.invoke('SendIceCandidate', sessionId, data)
    }
  })

  peer.on('stream', onRemoteStream)
  peer.on('error', onError)

  webrtcHub.on('ReceiveOffer', (sid, offer) => {
    if (sid === sessionId) peer?.signal(offer)
  })
  webrtcHub.on('ReceiveAnswer', (sid, answer) => {
    if (sid === sessionId) peer?.signal(answer)
  })
  webrtcHub.on('ReceiveIceCandidate', (sid, candidate) => {
    if (sid === sessionId) peer?.signal(candidate)
  })

  return peer
}

export function destroyWebRTC() {
  if (peer) {
    peer.destroy()
    peer = null
  }
  webrtcHub.off('ReceiveOffer')
  webrtcHub.off('ReceiveAnswer')
  webrtcHub.off('ReceiveIceCandidate')
}

export async function getLocalStream(video = true, audio = true) {
  return navigator.mediaDevices.getUserMedia({ video, audio })
}
