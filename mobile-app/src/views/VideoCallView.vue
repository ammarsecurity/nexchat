<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronRight, Mic, MicOff, Video, VideoOff, PhoneOff, AlertCircle, MessageSquare } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useChatStore } from '../stores/chat'
import { useConversationStore } from '../stores/conversation'
import { useActiveCallStore } from '../stores/activeCall'
import {
  joinLiveKitRoom,
  leaveLiveKitRoom,
  getRemoteTracksMediaStream,
  setLiveKitHandlers
} from '../services/livekit'
import { requestMediaPermissions } from '../utils/mediaPermissions'
import { createFilteredVideoStream } from '../utils/videoFilterStream'
import { Track } from 'livekit-client'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import CachedAvatar from '../components/CachedAvatar.vue'

const route = useRoute()
const router = useRouter()
const chat = useChatStore()
const convStore = useConversationStore()
const { t } = useI18n()

const sessionId = route.params.sessionId
const voiceOnly = ref(typeof history !== 'undefined' && history.state?.voiceOnly === true)
const localVideo = ref(null)
const remoteVideo = ref(null)
const roomRef = ref(null)
const muted = ref(false)
const cameraOff = ref(false)
const callDuration = ref(0)
const connected = ref(false)
const error = ref('')
const initializing = ref(true)
const activeFilter = ref('none')
const filterPipelineRef = ref(null)
const hasReplacedTrack = ref(false)

const cameraFilters = [
  { id: 'none', labelKey: 'videoCall.filters.none', css: 'none' },
  { id: 'grayscale', labelKey: 'videoCall.filters.grayscale', css: 'grayscale(100%)' },
  { id: 'sepia', labelKey: 'videoCall.filters.sepia', css: 'sepia(80%)' },
  { id: 'vintage', labelKey: 'videoCall.filters.vintage', css: 'sepia(40%) contrast(1.1) saturate(0.9)' },
  { id: 'warm', labelKey: 'videoCall.filters.warm', css: 'sepia(30%) hue-rotate(-10deg)' },
  { id: 'cool', labelKey: 'videoCall.filters.cool', css: 'hue-rotate(180deg) saturate(0.8)' },
  { id: 'cinematic', labelKey: 'videoCall.filters.cinematic', css: 'contrast(1.2) saturate(0.7)' }
]

function getFilterCss() {
  const f = cameraFilters.find((x) => x.id === activeFilter.value)
  return f?.css || 'none'
}

function replaceWithFilteredTrack(originalTrack) {
  if (!roomRef.value || !originalTrack?.mediaStreamTrack || hasReplacedTrack.value) return
  const lp = roomRef.value.localParticipant
  const videoPub = lp.getTrackPublication(Track.Source.Camera)
  if (!videoPub) return

  hasReplacedTrack.value = true
  const clonedTrack = originalTrack.mediaStreamTrack.clone()
  filterPipelineRef.value = createFilteredVideoStream(clonedTrack, getFilterCss)
  const filteredStream = filterPipelineRef.value.stream
  const filteredVideoTrack = filteredStream.getVideoTracks()[0]
  if (!filteredVideoTrack) {
    hasReplacedTrack.value = false
    return
  }

  lp.unpublishTrack(videoPub.track, false).then(() => {
    lp.publishTrack(filteredVideoTrack, {
      name: 'camera',
      source: Track.Source.Camera
    })

    nextTick().then(() => {
      if (localVideo.value && filteredVideoTrack) {
        const stream = new MediaStream([filteredVideoTrack])
        localVideo.value.srcObject = stream
        localVideo.value.style.filter = 'none'
        localVideo.value.play?.().catch(() => {})
      }
    })
  }).catch(() => {
    hasReplacedTrack.value = false
  })
}

let timerInterval

const activeCall = useActiveCallStore()

function isConversationRoom() {
  return String(convStore.conversationId) === String(sessionId)
}

/** محادثة خاصة: convStore، أو activeCall قبل مسح conv، أو state من ConversationChatView */
function isConversationCallContext() {
  return (
    isConversationRoom() ||
    activeCall.isConversation ||
    (typeof history !== 'undefined' && history.state?.fromConversation === true)
  )
}

const partner = computed(() => {
  if (String(convStore.conversationId) === String(sessionId)) return convStore.partner
  if (
    String(activeCall.sessionId) === String(sessionId) &&
    (activeCall.partnerName || activeCall.partnerAvatar)
  ) {
    return {
      name: activeCall.partnerName || '…',
      avatar: activeCall.partnerAvatar || null
    }
  }
  return chat.partner
})
const partnerLetter = computed(() => partner.value?.name?.[0]?.toUpperCase() || '?')
const partnerAvatarIsImage = computed(() => {
  const a = partner.value?.avatar
  return a && (a.startsWith('http') || a.startsWith('/'))
})
const partnerColor = computed(() => {
  if (!partner.value?.name) return 'var(--primary)'
  const colors = ['#6C63FF', '#FF6584', '#00D4FF', '#FF8C42']
  return colors[partner.value.name.charCodeAt(0) % colors.length]
})

function goBackAfterCall() {
  const id = sessionId
  const useConversation = isConversationCallContext()
  activeCall.clear()
  if (useConversation) router.replace(`/conversation/${id}`)
  else router.replace(`/chat/${id}`)
}

function openChatDuringCall() {
  const toConversation = isConversationCallContext()
  activeCall.syncMeta({
    sessionId,
    voiceOnly: voiceOnly.value,
    isConversation: toConversation,
    partnerName: partner.value?.name || activeCall.partnerName,
    partnerAvatar: partner.value?.avatar || activeCall.partnerAvatar
  })
  activeCall.minimize()
  if (toConversation) router.push(`/conversation/${sessionId}`)
  else router.push(`/chat/${sessionId}`)
}

onMounted(async () => {
  activeCall.syncMeta({
    sessionId,
    voiceOnly: voiceOnly.value,
    isConversation: isConversationCallContext(),
    partnerName: partner.value?.name || activeCall.partnerName,
    partnerAvatar: partner.value?.avatar || activeCall.partnerAvatar
  })

  try {
    await requestMediaPermissions()
    const remoteStream = new MediaStream()

    const { room: joinedRoom, reused } = await joinLiveKitRoom(
      sessionId,
      {
        onRemoteTrack: (track) => {
          remoteStream.addTrack(track.mediaStreamTrack)
          if (remoteVideo.value) remoteVideo.value.srcObject = remoteStream
          connected.value = true
        },
        onConnected: () => {},
        onDisconnected: () => {
          connected.value = false
        },
        onParticipantLeft: () => {
          goBackAfterCall()
        },
        onLocalTrack: (localTrack) => {
          if (voiceOnly.value) return
          nextTick().then(() => {
            if (localTrack?.kind === 'video') {
              replaceWithFilteredTrack(localTrack)
            } else if (localVideo.value && localTrack) {
              localTrack.attach(localVideo.value)
              localVideo.value.play?.().catch(() => {})
            }
          })
        },
        onMediaError: (e) => {
          error.value = e?.message || 'لا يمكن الوصول للكاميرا أو الميكروفون'
        }
      },
      { voiceOnly: voiceOnly.value }
    )

    roomRef.value = joinedRoom

    await nextTick()

    if (reused) {
      connected.value = true
      const ms = getRemoteTracksMediaStream(joinedRoom)
      if (remoteVideo.value) remoteVideo.value.srcObject = ms
      callDuration.value = activeCall.startedAt
        ? Math.floor((Date.now() - activeCall.startedAt) / 1000)
        : 0
      if (!voiceOnly.value) {
        const videoPub = joinedRoom.localParticipant.getTrackPublication(Track.Source.Camera)
        if (videoPub?.track?.kind === 'video' && localVideo.value) {
          hasReplacedTrack.value = false
          replaceWithFilteredTrack(videoPub.track)
        }
      }
    } else if (!voiceOnly.value) {
      const videoPub = roomRef.value?.localParticipant?.getTrackPublication(Track.Source.Camera)
      if (videoPub?.track?.kind === 'video' && localVideo.value && !localVideo.value.srcObject) {
        replaceWithFilteredTrack(videoPub.track)
      }
    }

    timerInterval = setInterval(() => {
      if (connected.value) callDuration.value++
    }, 1000)
  } catch (e) {
    if (e.name === 'NotAllowedError') {
      error.value = 'يجب السماح بالوصول للكاميرا والميكروفون'
    } else if (e.name === 'NotFoundError') {
      error.value = 'لم يتم العثور على كاميرا أو ميكروفون'
    } else {
      error.value = e.userMessage || e.response?.data?.message || e.message || 'لا يمكن الوصول للكاميرا أو الميكروفون'
    }
  } finally {
    initializing.value = false
  }
})

onUnmounted(() => {
  clearInterval(timerInterval)
  filterPipelineRef.value?.stop()
  filterPipelineRef.value = null

  if (activeCall.minimized && activeCall.sessionId === sessionId) {
    setLiveKitHandlers({
      onParticipantLeft: () => {
        leaveLiveKitRoom()
        activeCall.clear()
      },
      onDisconnected: () => {
        leaveLiveKitRoom()
        activeCall.clear()
      },
      onRemoteTrack: () => {},
      onLocalTrack: () => {},
      onConnected: () => {},
      onMediaError: () => {}
    })
    return
  }

  leaveLiveKitRoom()
  if (activeCall.sessionId === sessionId) activeCall.clear()
})

function toggleMute() {
  muted.value = !muted.value
  roomRef.value?.localParticipant?.setMicrophoneEnabled(!muted.value)
}

function toggleCamera() {
  if (voiceOnly.value) return
  cameraOff.value = !cameraOff.value
  if (cameraOff.value && filterPipelineRef.value) {
    filterPipelineRef.value.stop()
    filterPipelineRef.value = null
    hasReplacedTrack.value = false
  }
  roomRef.value?.localParticipant?.setCameraEnabled(!cameraOff.value)
}

function endCall() {
  goBackAfterCall()
}

function formatTime(sec) {
  const m = Math.floor(sec / 60).toString().padStart(2, '0')
  const s = (sec % 60).toString().padStart(2, '0')
  return `${m}:${s}`
}
</script>

<template>
  <div class="video-call page" :class="{ 'voice-only-mode': voiceOnly }">
    <LoaderOverlay :show="initializing" :text="t('videoCall.preparing')" />
    <!-- Remote: في المكالمة الصوتية يبقى العنصر لتشغيل الصوت فقط (مخفي بصرياً) -->
    <video
      ref="remoteVideo"
      class="remote-video"
      :class="{ 'remote-video--voice-audio-only': voiceOnly }"
      autoplay
      playsinline
    ></video>

    <!-- وضع المكالمة الصوتية: صورة واسم الطرف الآخر بشكل مرتب -->
    <div v-if="voiceOnly" class="voice-call-stage">
      <div class="voice-call-card">
        <div
          class="voice-call-avatar"
          :style="partnerAvatarIsImage ? {} : { background: partnerColor }"
        >
          <CachedAvatar
            v-if="partnerAvatarIsImage"
            :url="partner?.avatar"
            img-class="voice-call-avatar-img"
          />
          <span v-else class="voice-call-letter">{{ partnerLetter }}</span>
        </div>
        <h2 class="voice-call-title">{{ partner?.name || '…' }}</h2>
        <p v-if="!connected && !error" class="voice-call-sub">{{ t('videoCall.connecting') }}</p>
        <div v-else-if="!connected && error" class="error-toast voice-call-error">
          <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
          <span>{{ error }}</span>
        </div>
        <div v-else class="voice-call-live-row">
          <span class="voice-live-pill">
            <span class="live-dot"></span>
            {{ t('videoCall.voiceCallLive') }}
          </span>
          <span class="voice-call-timer">{{ formatTime(callDuration) }}</span>
        </div>
        <div v-if="!connected && !error" class="connecting-dots voice-call-dots">
          <span></span><span></span><span></span>
        </div>
      </div>
    </div>

    <!-- فيديو: انتظار قبل الاتصال -->
    <div v-if="!connected && !voiceOnly" class="waiting-overlay">
      <div class="avatar avatar-xl gradient-bg">{{ partnerLetter }}</div>
      <div class="waiting-text">
        <div class="waiting-name gradient-text font-bold">{{ partner?.name }}</div>
        <div class="text-secondary text-sm" v-if="!error">{{ t('videoCall.connecting') }}</div>
        <div v-else class="error-toast">
          <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
          <span>{{ error }}</span>
        </div>
      </div>
      <div class="connecting-dots" v-if="!error">
        <span></span><span></span><span></span>
      </div>
    </div>

    <!-- Top Bar -->
    <div class="top-bar">
      <button class="top-bar-back" @click="endCall" :aria-label="t('videoCall.endCallAria')">
        <ChevronRight :size="22" />
      </button>
      <button
        type="button"
        class="top-bar-chat"
        :title="t('videoCall.openChat')"
        :aria-label="t('videoCall.openChat')"
        @click="openChatDuringCall"
      >
        <MessageSquare :size="20" />
      </button>
      <div class="top-bar-info">
        <div class="top-bar-name">{{ partner?.name }}</div>
        <div class="top-bar-status">
          <span v-if="connected" class="live-badge">
            <span class="live-dot"></span>
            LIVE {{ formatTime(callDuration) }}
          </span>
          <span v-else class="status-connecting">{{ error || t('videoCall.connecting') }}</span>
        </div>
      </div>
    </div>

    <!-- Local Video (PiP) - الفلتر مُطبّق على الستريم المرسل فيراه الطرف الآخر -->
    <div v-if="!voiceOnly" class="pip-container">
      <video
        ref="localVideo"
        class="local-video"
        autoplay
        playsinline
        muted
      ></video>
      <div v-if="cameraOff" class="camera-off-pip"><VideoOff :size="32" /></div>
    </div>

    <!-- Filter Bar -->
    <div v-if="!voiceOnly" class="filter-bar">
      <div class="filter-scroll">
        <button
          v-for="f in cameraFilters"
          :key="f.id"
          class="filter-chip"
          :class="{ active: activeFilter === f.id }"
          :title="t(f.labelKey)"
          @click="activeFilter = f.id"
        >
          <span
            class="filter-preview"
            :style="{ filter: f.id !== 'none' ? f.css : 'none' }"
          ></span>
          <span class="filter-chip-label">{{ t(f.labelKey) }}</span>
        </button>
      </div>
    </div>

    <!-- Controls -->
    <div class="controls">
      <button
        class="ctrl-btn"
        :class="{ active: muted }"
        @click="toggleMute"
      >
        <MicOff v-if="muted" :size="24" />
        <Mic v-else :size="24" />
        <span class="ctrl-label">{{ muted ? t('videoCall.unmute') : t('videoCall.mute') }}</span>
      </button>

      <button class="ctrl-btn end-btn" @click="endCall">
        <PhoneOff :size="24" />
        <span class="ctrl-label">{{ t('videoCall.endCall') }}</span>
      </button>

      <button
        v-if="!voiceOnly"
        class="ctrl-btn"
        :class="{ active: cameraOff }"
        @click="toggleCamera"
      >
        <VideoOff v-if="cameraOff" :size="24" />
        <Video v-else :size="24" />
        <span class="ctrl-label">{{ cameraOff ? t('videoCall.cameraOn') : t('videoCall.cameraOff') }}</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.video-call {
  background: #000;
  position: relative;
  overflow: hidden;
}

.remote-video {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

/* إبقاء تشغيل الصوت البعيد دون عرض مساحة سوداء كاملة الشاشة */
.remote-video--voice-audio-only {
  position: absolute;
  width: 1px;
  height: 1px;
  opacity: 0;
  pointer-events: none;
  inset: auto;
  left: 0;
  top: 0;
}

.voice-call-stage {
  position: absolute;
  inset: 0;
  z-index: 5;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: calc(100px + var(--safe-top)) var(--spacing) calc(200px + var(--safe-bottom));
  background: radial-gradient(ellipse 120% 80% at 50% 35%, rgba(108, 99, 255, 0.22) 0%, transparent 55%),
    linear-gradient(180deg, #0f0f12 0%, #050506 50%, #0a0a0c 100%);
  pointer-events: none;
}

.voice-call-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  width: 100%;
  max-width: 320px;
  text-align: center;
}

.voice-call-avatar {
  width: 132px;
  height: 132px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  flex-shrink: 0;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.45), 0 0 0 4px rgba(255, 255, 255, 0.08);
}

.voice-call-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}

.voice-call-letter {
  font-size: 52px;
  font-weight: 700;
  color: #fff;
  line-height: 1;
  font-family: 'Cairo', sans-serif;
}

.voice-call-title {
  margin: 0;
  font-size: 22px;
  font-weight: 700;
  color: #fff;
  line-height: 1.3;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  font-family: 'Cairo', sans-serif;
  text-shadow: 0 2px 12px rgba(0, 0, 0, 0.35);
}

.voice-call-sub {
  margin: 0;
  font-size: 15px;
  color: rgba(255, 255, 255, 0.65);
  font-weight: 500;
}

.voice-call-live-row {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
}

.voice-live-pill {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  background: rgba(34, 197, 94, 0.2);
  border: 1px solid rgba(34, 197, 94, 0.45);
  color: #86efac;
  font-size: 13px;
  font-weight: 600;
  padding: 6px 14px;
  border-radius: 999px;
}

.voice-call-timer {
  font-size: 28px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  color: #fff;
  letter-spacing: 0.04em;
}

.voice-call-dots {
  margin-top: 4px;
}

.voice-call-error {
  max-width: 100%;
}

.voice-only-mode {
  background: #050506;
}

.waiting-overlay {
  position: absolute;
  inset: 0;
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 20px;
  z-index: 10;
}

.gradient-bg { background: var(--primary) !important; }
.waiting-text { text-align: center; display: flex; flex-direction: column; align-items: center; gap: 12px; max-width: 100%; }
.waiting-name {
  font-size: 20px;
  max-width: min(280px, calc(100vw - 48px));
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.connecting-dots {
  display: flex;
  gap: 8px;
}
.connecting-dots span {
  background: rgba(255,255,255,0.3);
  border-radius: 50%;
  width: 10px; height: 10px;
  animation: dot-bounce 1.2s ease-in-out infinite;
}
.connecting-dots span:nth-child(2) { animation-delay: 0.2s; }
.connecting-dots span:nth-child(3) { animation-delay: 0.4s; }
@keyframes dot-bounce { 0%,100%{transform:translateY(0)} 50%{transform:translateY(-8px)} }

.top-bar {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  padding: calc(24px + var(--safe-top)) var(--spacing) 20px;
  background: linear-gradient(180deg, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0.2) 60%, transparent 100%);
  display: flex;
  align-items: center;
  gap: 14px;
  z-index: 20;
}

.top-bar-back {
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  min-width: 44px;
  min-height: 44px;
  padding: 0;
  background: rgba(255,255,255,0.15);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid rgba(255,255,255,0.25);
  border-radius: 12px;
  color: white;
  cursor: pointer;
  display: flex;
  flex-shrink: 0;
  transition: background 0.2s, transform 0.2s;
}
.top-bar-back:active { background: rgba(255,255,255,0.25); transform: scale(0.96); }

.top-bar-chat {
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  min-width: 44px;
  min-height: 44px;
  padding: 0;
  background: rgba(108, 99, 255, 0.35);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid rgba(255, 255, 255, 0.28);
  border-radius: 12px;
  color: white;
  cursor: pointer;
  display: flex;
  flex-shrink: 0;
  transition: background 0.2s, transform 0.2s;
}
.top-bar-chat:active { background: rgba(108, 99, 255, 0.5); transform: scale(0.96); }

.top-bar-info {
  flex: 1;
  min-width: 0;
  padding: 10px 16px;
  background: rgba(255,255,255,0.08);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 14px;
  display: flex;
  flex-direction: row;
  gap: 4px;
  justify-content: space-between;
  align-items: center;
}

.top-bar-name {
  color: white;
  font-size: 17px;
  font-weight: 700;
  letter-spacing: -0.2px;
  text-shadow: 0 1px 2px rgba(0,0,0,0.3);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  min-width: 0;
}

.top-bar-status {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
}

.live-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: linear-gradient(135deg, rgba(239,68,68,0.4) 0%, rgba(220,38,38,0.35) 100%);
  border: 1px solid rgba(255,255,255,0.3);
  border-radius: 20px;
  color: white;
  font-size: 12px;
  font-weight: 700;
  padding: 4px 10px;
  letter-spacing: 0.5px;
  box-shadow: 0 2px 8px rgba(239,68,68,0.25);
}

.live-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: #fff;
  animation: live-pulse 1.5s ease-in-out infinite;
}

@keyframes live-pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.6; transform: scale(1.2); }
}

.status-connecting {
  color: rgba(255,255,255,0.85);
  font-weight: 500;
}

.pip-container {
  position: absolute;
  top: 120px;
  right: 16px;
  width: 90px;
  height: 120px;
  border-radius: 12px;
  overflow: hidden;
  border: 2px solid rgba(255,255,255,0.2);
  z-index: 20;
  background: #111;
}
.local-video {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.camera-off-pip {
  position: absolute;
  inset: 0;
  align-items: center;
  color: var(--text-muted);
  display: flex;
  justify-content: center;
  background: #111;
}

/* Filter Bar */
.filter-bar {
  position: absolute;
  left: 0;
  right: 0;
  bottom: calc(140px + var(--safe-bottom));
  padding: 0 var(--spacing);
  z-index: 20;
}

.filter-scroll {
  display: flex;
  gap: 10px;
  overflow-x: auto;
  padding: 12px 4px;
  scroll-snap-type: x mandatory;
  -webkit-overflow-scrolling: touch;
  background: rgba(0,0,0,0.4);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 16px;
}

.filter-chip {
  flex-shrink: 0;
  scroll-snap-align: center;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 6px 4px;
  background: transparent;
  border: 2px solid transparent;
  border-radius: 12px;
  cursor: pointer;
  transition: border-color 0.2s, background 0.2s;
  min-width: 56px;
}
.filter-chip:active { opacity: 0.9; }
.filter-chip.active {
  border-color: rgba(255,255,255,0.6);
  background: rgba(255,255,255,0.1);
}

.filter-preview {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 25%, #f093fb 50%, #f5576c 75%, #4facfe 100%);
  display: block;
}

.filter-chip-label {
  font-size: 10px;
  font-weight: 600;
  color: rgba(255,255,255,0.9);
  white-space: nowrap;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
}

.controls {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  padding: 24px var(--spacing) calc(48px + var(--safe-bottom));
  background: linear-gradient(to top, rgba(0,0,0,0.7), transparent);
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 24px;
  z-index: 20;
}

.ctrl-btn {
  align-items: center;
  background: rgba(255,255,255,0.2);
  border: 1px solid rgba(255,255,255,0.25);
  border-radius: var(--radius);
  color: white;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  font-family: 'Cairo', sans-serif;
  gap: 4px;
  height: 64px;
  justify-content: center;
  min-width: 64px;
  padding: 8px;
  transition: opacity 0.2s;
}
.ctrl-btn:active { opacity: 0.9; }
.ctrl-btn.active { background: rgba(255,255,255,0.3); }

.ctrl-label {
  color: white;
  font-family: 'Cairo', sans-serif;
  font-size: 10px;
  white-space: nowrap;
}

.end-btn {
  background: rgba(255, 60, 60, 0.85) !important;
  border-color: rgba(255, 60, 60, 0.6) !important;
  height: 72px;
  min-width: 72px;
}
.end-btn:active { opacity: 0.9; }
</style>
