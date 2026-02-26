<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { useChatStore } from '../stores/chat'
import { initWebRTC, destroyWebRTC, getLocalStream } from '../services/webrtc'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const chat = useChatStore()

const sessionId = route.params.sessionId
const localVideo = ref(null)
const remoteVideo = ref(null)
const localStream = ref(null)
const muted = ref(false)
const cameraOff = ref(false)
const callDuration = ref(0)
const connected = ref(false)
const error = ref('')

let timerInterval

onMounted(async () => {
  try {
    localStream.value = await getLocalStream(true, true)
    if (localVideo.value)
      localVideo.value.srcObject = localStream.value

    const isInitiator = history.state?.initiator ?? true
    await initWebRTC(
      sessionId,
      isInitiator,
      localStream.value,
      (stream) => {
        if (remoteVideo.value) {
          remoteVideo.value.srcObject = stream
          connected.value = true
        }
      },
      (err) => {
        error.value = 'خطأ في الاتصال: ' + err.message
      }
    )

    timerInterval = setInterval(() => {
      if (connected.value) callDuration.value++
    }, 1000)
  } catch (e) {
    error.value = 'لا يمكن الوصول للكاميرا أو الميكروفون'
  }
})

onUnmounted(() => {
  clearInterval(timerInterval)
  destroyWebRTC()
  localStream.value?.getTracks().forEach(t => t.stop())
})

function toggleMute() {
  muted.value = !muted.value
  localStream.value?.getAudioTracks().forEach(t => { t.enabled = !muted.value })
}

function toggleCamera() {
  cameraOff.value = !cameraOff.value
  localStream.value?.getVideoTracks().forEach(t => { t.enabled = !cameraOff.value })
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
      <button class="back-btn" @click="endCall">←</button>
      <div class="call-info">
        <div class="call-name">{{ partner?.name }}</div>
        <div class="call-status text-sm">
          <span v-if="connected" class="live-badge">🔴 LIVE {{ formatTime(callDuration) }}</span>
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
      <div v-if="cameraOff" class="camera-off-pip">📷</div>
    </div>

    <!-- Controls -->
    <div class="controls">
      <button
        class="ctrl-btn"
        :class="{ active: muted }"
        @click="toggleMute"
      >
        <span>{{ muted ? '🔇' : '🎤' }}</span>
        <span class="ctrl-label">{{ muted ? 'إلغاء الكتم' : 'كتم' }}</span>
      </button>

      <button class="ctrl-btn end-btn" @click="endCall">
        <span>📞</span>
        <span class="ctrl-label">إنهاء</span>
      </button>

      <button
        class="ctrl-btn"
        :class="{ active: cameraOff }"
        @click="toggleCamera"
      >
        <span>{{ cameraOff ? '📷' : '📹' }}</span>
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

.gradient-bg { background: var(--gradient); }
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
  padding: 50px 20px 20px;
  background: linear-gradient(to bottom, rgba(0,0,0,0.6), transparent);
  display: flex;
  align-items: center;
  gap: 12px;
  z-index: 20;
}

.back-btn {
  background: rgba(255,255,255,0.15);
  border: none;
  border-radius: 50%;
  color: white;
  cursor: pointer;
  font-size: 20px;
  height: 36px;
  width: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
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
  display: flex;
  align-items: center;
  justify-content: center;
  background: #111;
  font-size: 30px;
}

.controls {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  padding: 24px 20px 48px;
  background: linear-gradient(to top, rgba(0,0,0,0.7), transparent);
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 24px;
  z-index: 20;
}

.ctrl-btn {
  align-items: center;
  background: rgba(255,255,255,0.15);
  backdrop-filter: blur(10px);
  border: 1px solid rgba(255,255,255,0.2);
  border-radius: 50%;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  gap: 6px;
  height: 64px;
  justify-content: center;
  width: 64px;
  font-size: 24px;
  transition: 0.2s;
}
.ctrl-btn.active { background: rgba(255,255,255,0.25); }
.ctrl-btn:hover { transform: scale(1.05); }

.ctrl-label {
  color: white;
  font-size: 9px;
  position: absolute;
  bottom: -20px;
  white-space: nowrap;
}
.ctrl-btn { position: relative; }

.end-btn {
  background: rgba(255, 60, 60, 0.7) !important;
  border-color: rgba(255, 60, 60, 0.5) !important;
  height: 72px;
  width: 72px;
  font-size: 28px;
  transform: rotate(135deg);
}
.end-btn:hover { background: rgba(255, 60, 60, 0.9) !important; }
</style>
