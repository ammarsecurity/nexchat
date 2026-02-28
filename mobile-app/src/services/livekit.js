import { Room, RoomEvent, Track } from 'livekit-client'
import api from './api'

let room = null

/**
 * الانضمام لغرفة LiveKit
 * @param {string} sessionId - معرف الجلسة (اسم الغرفة)
 * @param {Function} onRemoteTrack - callback عند استلام track بعيد
 * @param {Function} onConnected - callback عند الاتصال
 * @param {Function} onDisconnected - callback عند الانقطاع
 * @param {Function} onParticipantLeft - callback عند مغادرة الطرف الآخر (لإغلاق المكالمة والعودة للدردشة)
 * @param {Function} onLocalTrack - callback عند نشر track محلي (كاميرا/ميكروفون)
 * @param {Function} onMediaError - callback عند فشل الوصول للكاميرا أو الميكروفون
 */
export async function joinLiveKitRoom(sessionId, onRemoteTrack, onConnected, onDisconnected, onParticipantLeft, onLocalTrack, onMediaError) {
  const { data } = await api.post('livekit/token', { roomName: sessionId })

  room = new Room()

  room.on('trackSubscribed', (track, publication, participant) => {
    if (track.mediaStreamTrack) onRemoteTrack?.(track)
  })

  room.on(RoomEvent.LocalTrackPublished, (publication, participant) => {
    const track = publication?.track
    if (track?.kind === 'video') onLocalTrack?.(track)
  })

  room.on(RoomEvent.MediaDevicesError, (error) => {
    onMediaError?.(error)
  })

  room.on('participantDisconnected', () => {
    onParticipantLeft?.()
  })

  room.on('disconnected', () => {
    onDisconnected?.()
  })

  await room.connect(data.url, data.token)

  await room.localParticipant.enableCameraAndMicrophone()

  // ربط الكاميرا المحلية فوراً إن كانت جاهزة (للتوافق مع Android)
  const videoPub = room.localParticipant.getTrackPublication(Track.Source.Camera)
  if (videoPub?.track && videoPub.track.kind === 'video') {
    onLocalTrack?.(videoPub.track)
  }

  onConnected?.()

  return room
}

export function leaveLiveKitRoom() {
  if (room) {
    room.disconnect()
    room = null
  }
}
