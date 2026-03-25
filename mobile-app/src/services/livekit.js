import { Room, RoomEvent, Track, ConnectionState } from 'livekit-client'
import api from './api'

let room = null
let lastJoinedSessionId = null

/** يُحدَّث من joinLiveKitRoom و setLiveKitHandlers */
let handlers = {
  onRemoteTrack: null,
  onConnected: null,
  onDisconnected: null,
  onParticipantLeft: null,
  onLocalTrack: null,
  onMediaError: null
}

export function getLiveKitRoom() {
  return room
}

/**
 * تحديث معالجات الأحداث دون إعادة الاتصال (مثلاً عند مغادرة VideoCallView مع بقاء المكالمة).
 */
export function setLiveKitHandlers(partial) {
  handlers = { ...handlers, ...partial }
}

/**
 * جمع مسار الصوت/الفيديو البعيد الحالي لإعادة ربطه بعنصر &lt;video&gt; بعد إعادة فتح الشاشة.
 */
export function getRemoteTracksMediaStream(roomInstance) {
  const ms = new MediaStream()
  if (!roomInstance?.remoteParticipants) return ms
  for (const p of roomInstance.remoteParticipants.values()) {
    p.trackPublications.forEach((pub) => {
      if (pub.track?.mediaStreamTrack) {
        ms.addTrack(pub.track.mediaStreamTrack)
      }
    })
  }
  return ms
}

/**
 * @param {string} sessionId
 * @param {object} h - onRemoteTrack, onConnected, onDisconnected, onParticipantLeft, onLocalTrack, onMediaError
 * @param {{ voiceOnly?: boolean }} [opts]
 * @returns {Promise<{ room: Room, reused: boolean }>}
 */
export async function joinLiveKitRoom(sessionId, h, opts = {}) {
  const voiceOnly = opts.voiceOnly === true
  handlers = { ...handlers, ...h }

  if (
    room &&
    room.state === ConnectionState.Connected &&
    lastJoinedSessionId === sessionId
  ) {
    return { room, reused: true }
  }

  if (room) {
    room.disconnect()
    room = null
  }

  lastJoinedSessionId = sessionId
  const { data } = await api.post('livekit/token', { roomName: sessionId })

  room = new Room()

  room.on('trackSubscribed', (track, publication, participant) => {
    if (track.mediaStreamTrack) handlers.onRemoteTrack?.(track)
  })

  room.on(RoomEvent.LocalTrackPublished, (publication, participant) => {
    const track = publication?.track
    if (track?.kind === 'video') handlers.onLocalTrack?.(track)
  })

  room.on(RoomEvent.MediaDevicesError, (error) => {
    handlers.onMediaError?.(error)
  })

  room.on('participantDisconnected', () => {
    handlers.onParticipantLeft?.()
  })

  room.on('disconnected', () => {
    handlers.onDisconnected?.()
  })

  await room.connect(data.url, data.token)

  if (voiceOnly) {
    await room.localParticipant.setMicrophoneEnabled(true)
  } else {
    await room.localParticipant.enableCameraAndMicrophone()
    const videoPub = room.localParticipant.getTrackPublication(Track.Source.Camera)
    if (videoPub?.track && videoPub.track.kind === 'video') {
      handlers.onLocalTrack?.(videoPub.track)
    }
  }

  handlers.onConnected?.()

  return { room, reused: false }
}

export function leaveLiveKitRoom() {
  if (room) {
    room.disconnect()
    room = null
  }
  lastJoinedSessionId = null
}
