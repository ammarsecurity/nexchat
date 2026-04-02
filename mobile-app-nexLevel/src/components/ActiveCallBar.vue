<script setup>
import { ref, watch, nextTick, computed, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { PhoneOff, Mic } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { useActiveCallStore } from '../stores/activeCall'
import { getLiveKitRoom, getRemoteTracksMediaStream, leaveLiveKitRoom } from '../services/livekit'
import CachedAvatar from './CachedAvatar.vue'

defineProps({
  /** داخل تخطيط المحادثة (ليس fixed على كامل الشاشة) */
  embedded: { type: Boolean, default: false }
})

const { t } = useI18n()
const router = useRouter()
const activeCall = useActiveCallStore()

const remoteMediaEl = ref(null)
const elapsedSec = ref(0)
let tickTimer = null

const partnerLetter = computed(() => activeCall.partnerName?.[0]?.toUpperCase() || '?')
const partnerAvatarIsImage = computed(() => {
  const a = activeCall.partnerAvatar
  return a && (a.startsWith('http') || a.startsWith('/'))
})

function formatTime(sec) {
  const m = Math.floor(sec / 60).toString().padStart(2, '0')
  const s = (sec % 60).toString().padStart(2, '0')
  return `${m}:${s}`
}

function attachRemotePlayback() {
  const room = getLiveKitRoom()
  const el = remoteMediaEl.value
  if (!room || !el) return
  const ms = getRemoteTracksMediaStream(room)
  if (ms.getTracks().length === 0) return
  el.srcObject = ms
  el.play?.().catch(() => {})
}

function clearRemotePlayback() {
  const el = remoteMediaEl.value
  if (el) {
    el.srcObject = null
  }
}

watch(
  () => activeCall.showFloatingBar,
  (show) => {
    if (show) {
      nextTick(() => attachRemotePlayback())
      if (!tickTimer && activeCall.startedAt) {
        elapsedSec.value = Math.floor((Date.now() - activeCall.startedAt) / 1000)
        tickTimer = setInterval(() => {
          if (activeCall.startedAt) {
            elapsedSec.value = Math.floor((Date.now() - activeCall.startedAt) / 1000)
          }
        }, 1000)
      }
    } else {
      clearRemotePlayback()
      if (tickTimer) {
        clearInterval(tickTimer)
        tickTimer = null
      }
    }
  },
  { immediate: true }
)

onUnmounted(() => {
  if (tickTimer) clearInterval(tickTimer)
  clearRemotePlayback()
})

function openFullCall() {
  clearRemotePlayback()
  activeCall.expand()
  router.push({
    path: `/video/${activeCall.sessionId}`,
    state: { voiceOnly: activeCall.voiceOnly }
  })
}

function endCallFromBar() {
  leaveLiveKitRoom()
  clearRemotePlayback()
  activeCall.clear()
}
</script>

<template>
  <div
    v-if="activeCall.showFloatingBar"
    class="active-call-bar"
    :class="{ 'active-call-bar--embedded': embedded }"
  >
    <!-- تشغيل الصوت/الفيديو البعيد أثناء التصغير (بدون إطار مرئي) -->
    <video
      ref="remoteMediaEl"
      class="active-call-remote-media"
      autoplay
      playsinline
    />

    <button type="button" class="active-call-main" @click="openFullCall">
      <div
        class="active-call-avatar"
        :style="partnerAvatarIsImage ? {} : { background: 'var(--primary)' }"
      >
        <CachedAvatar
          v-if="partnerAvatarIsImage"
          :url="activeCall.partnerAvatar"
          img-class="active-call-avatar-img"
        />
        <span v-else>{{ partnerLetter }}</span>
      </div>
      <div class="active-call-text">
        <div class="active-call-name">{{ activeCall.partnerName || '…' }}</div>
        <div class="active-call-meta">
          <Mic :size="14" class="active-call-mic" />
          <span>{{ t('videoCall.callInBackground') }}</span>
          <span class="active-call-dot">·</span>
          <span>{{ formatTime(elapsedSec) }}</span>
        </div>
      </div>
    </button>

    <button
      type="button"
      class="active-call-hangup"
      :aria-label="t('videoCall.endCallAria')"
      @click.stop="endCallFromBar"
    >
      <PhoneOff :size="22" />
    </button>
  </div>
</template>

<style scoped>
.active-call-remote-media {
  position: absolute;
  width: 1px;
  height: 1px;
  opacity: 0;
  pointer-events: none;
  left: 0;
  top: 0;
}

.active-call-bar {
  position: fixed;
  left: var(--spacing, 16px);
  right: var(--spacing, 16px);
  top: calc(18px + var(--safe-top, 0px));
  bottom: auto;
  z-index: 10050;
  box-sizing: border-box;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  background: rgba(20, 20, 24, 0.92);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 16px;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.4);
  font-family: 'Cairo', system-ui, -apple-system, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

@media (min-width: 480px) {
  .active-call-bar:not(.active-call-bar--embedded) {
    left: 50%;
    right: auto;
    transform: translateX(-50%);
    width: min(var(--app-max-width), calc(100vw - 2 * var(--spacing, 16px)));
    max-width: min(var(--app-max-width), calc(100vw - 2 * var(--spacing, 16px)));
  }
}

.active-call-bar--embedded {
  position: relative;
  left: auto;
  right: auto;
  top: auto;
  bottom: auto;
  width: 100%;
  max-width: 100%;
  margin: 0;
  z-index: 6;
  box-shadow: 0 2px 16px rgba(0, 0, 0, 0.25);
}

.active-call-main {
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0;
  border: none;
  background: transparent;
  cursor: pointer;
  text-align: right;
  -webkit-tap-highlight-color: transparent;
}

.active-call-avatar {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  font-family: 'Cairo', system-ui, -apple-system, sans-serif;
  font-size: 18px;
  font-weight: 700;
  color: #fff;
}

.active-call-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}

.active-call-text {
  min-width: 0;
  flex: 1;
}

.active-call-name {
  font-family: 'Cairo', system-ui, -apple-system, sans-serif;
  font-size: 15px;
  font-weight: 700;
  color: #fff;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.active-call-meta {
  display: flex;
  align-items: center;
  gap: 6px;
  font-family: 'Cairo', system-ui, -apple-system, sans-serif;
  font-size: 12px;
  line-height: 1.5;
  color: rgba(255, 255, 255, 0.65);
  margin-top: 2px;
}

.active-call-mic {
  flex-shrink: 0;
  opacity: 0.9;
}

.active-call-dot {
  opacity: 0.5;
}

.active-call-hangup {
  flex-shrink: 0;
  width: 48px;
  height: 48px;
  border-radius: 50%;
  border: none;
  background: rgba(239, 68, 68, 0.9);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: transform 0.15s, background 0.15s;
}
.active-call-hangup:active {
  transform: scale(0.94);
  background: rgba(220, 38, 38, 1);
}
</style>
