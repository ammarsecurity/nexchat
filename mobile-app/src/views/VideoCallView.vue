<script setup>
import { ref, onMounted, onUnmounted, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronRight, Mic, MicOff, Video, VideoOff, PhoneOff } from 'lucide-vue-next'
import { useChatStore } from '../stores/chat'
import { joinLiveKitRoom, leaveLiveKitRoom } from '../services/livekit'
import { requestMediaPermissions } from '../utils/mediaPermissions'
import LoaderOverlay from '../components/LoaderOverlay.vue'

const route = useRoute()
const router = useRouter()
const chat = useChatStore()

const sessionId = route.params.sessionId
const localVideo = ref(null)
const remoteVideo = ref(null)
const roomRef = ref(null)
const muted = ref(false)
const cameraOff = ref(false)
const callDuration = ref(0)
const connected = ref(false)
const error = ref('')
const initializing = ref(true)

let timerInterval

onMounted(async () => {
  try {
    await requestMediaPermissions()
    const remoteStream = new MediaStream()

    roomRef.value = await joinLiveKitRoom(
      sessionId,
      (track) => {
        remoteStream.addTrack(track.mediaStreamTrack)
        if (remoteVideo.value) remoteVideo.value.srcObject = remoteStream
        connected.value = true
      },
      () => {},
      () => {
        connected.value = false
      },
      () => {
        router.back()
      },
      (localTrack) => {
        nextTick().then(() => {
          if (localVideo.value && localTrack) {
            localTrack.attach(localVideo.value)
            localVideo.value.play?.().catch(() => {})
          }
        })
      },
      (e) => {
        error.value = e?.message || 'لا يمكن الوصول للكاميرا أو الميكروفون'
      }
    )

    await nextTick()
    const pubsMap = roomRef.value?.localParticipant?.trackPublications
    const pubs = pubsMap ? Array.from(pubsMap.values()) : []
    for (const pub of pubs) {
      if (pub?.track?.kind === 'video' && localVideo.value) {
        pub.track.attach(localVideo.value)
        localVideo.value.play?.().catch(() => {})
        break
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
      error.value = e.message || 'لا يمكن الوصول للكاميرا أو الميكروفون'
    }
  } finally {
    initializing.value = false
  }
})

onUnmounted(() => {
  clearInterval(timerInterval)
  leaveLiveKitRoom()
})

function toggleMute() {
  muted.value = !muted.value
  roomRef.value?.localParticipant?.setMicrophoneEnabled(!muted.value)
}

function toggleCamera() {
  cameraOff.value = !cameraOff.value
  roomRef.value?.localParticipant?.setCameraEnabled(!cameraOff.value)
}

function endCall() {
  router.back()
}

function formatTime(sec) {
  const m = Math.floor(sec / 60).toString().padStart(2, '0')
  const s = (sec % 60).toString().padStart(2, '0')
  return `${m}:${s}`
}

const partner = chat.partner
const partnerLetter = partner?.name?.[0]?.toUpperCase() || '?'
</script>

<template>
  <div class="video-call page">
    <LoaderOverlay :show="initializing" text="جاري تجهيز المكالمة..." />
    <!-- Remote Video (Full Screen) -->
    <video
      ref="remoteVideo"
      class="remote-video"
      autoplay
      playsinline
    ></video>

    <!-- No video placeholder -->
    <div v-if="!connected" class="waiting-overlay">
      <div class="avatar avatar-xl gradient-bg">{{ partnerLetter }}</div>
      <div class="waiting-text">
        <div class="gradient-text font-bold" style="font-size:20px">{{ partner?.name }}</div>
        <div class="text-secondary text-sm" v-if="!error">جارٍ الاتصال...</div>
        <div class="error-text text-sm" v-else>{{ error }}</div>
      </div>
      <div class="connecting-dots" v-if="!error">
        <span></span><span></span><span></span>
      </div>
    </div>

    <!-- Top Bar -->
    <div class="top-bar">
      <button class="back-btn" @click="endCall"><ChevronRight :size="22" /></button>
      <div class="call-info">
        <div class="call-name">{{ partner?.name }}</div>
        <div class="call-status text-sm">
          <span v-if="connected" class="live-badge">LIVE {{ formatTime(callDuration) }}</span>
          <span v-else class="text-muted">{{ error || 'جارٍ الاتصال...' }}</span>
        </div>
      </div>
    </div>

    <!-- Local Video (PiP) -->
    <div class="pip-container">
      <video
        ref="localVideo"
        class="local-video"
        autoplay
        playsinline
        muted
      ></video>
      <div v-if="cameraOff" class="camera-off-pip"><VideoOff :size="32" /></div>
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
        <span class="ctrl-label">{{ muted ? 'إلغاء الكتم' : 'كتم' }}</span>
      </button>

      <button class="ctrl-btn end-btn" @click="endCall">
        <PhoneOff :size="24" />
        <span class="ctrl-label">إنهاء</span>
      </button>

      <button
        class="ctrl-btn"
        :class="{ active: cameraOff }"
        @click="toggleCamera"
      >
        <VideoOff v-if="cameraOff" :size="24" />
        <Video v-else :size="24" />
        <span class="ctrl-label">{{ cameraOff ? 'تشغيل' : 'إيقاف' }}</span>
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
.waiting-text { text-align: center; }
.error-text { color: #FF6584; }

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
  padding: calc(30px + var(--safe-top)) var(--spacing) var(--spacing);
  background: linear-gradient(to bottom, rgba(0,0,0,0.6), transparent);
  display: flex;
  align-items: center;
  gap: 12px;
  z-index: 20;
}

.back-btn {
  align-items: center;
  background: rgba(255,255,255,0.2);
  border: none;
  border-radius: var(--radius-sm);
  color: white;
  cursor: pointer;
  display: flex;
  height: var(--touch-min);
  justify-content: center;
  min-width: var(--touch-min);
  flex-shrink: 0;
}

.call-info { flex: 1; }
.call-name { color: white; font-size: 18px; font-weight: 600; }

.live-badge {
  background: rgba(255,0,0,0.3);
  border: 1px solid rgba(255,0,0,0.4);
  border-radius: 20px;
  color: white;
  font-size: 12px;
  padding: 2px 8px;
  font-weight: 600;
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
