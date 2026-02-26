<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Video, Flag, X, Check, ChevronLeft, Smile, Image, Send, Loader2 } from 'lucide-vue-next'
import { useAuthStore } from '../stores/auth'
import { useChatStore } from '../stores/chat'
import { chatHub, startHub } from '../services/signalr'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const chat = useChatStore()

const sessionId = route.params.sessionId
const messageText = ref('')
const messagesEl = ref(null)
const sessionEnded = ref(false)
const timerSeconds = ref(0)
const showReport = ref(false)
const reportReason = ref('')
const incomingCall = ref(false)
const callDeclined = ref(false)
const showEmojiPicker = ref(false)
const activeEmojiTab = ref(0)
const imageInput = ref(null)
const uploadingImage = ref(false)
let timerInterval

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

const emojiCategories = [
  { icon: '😀', emojis: ['😀','😃','😄','😁','😆','😅','😂','🤣','😊','😇','🥰','😍','🤩','😘','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒','🙄','😬','😌','😔','😪','😴','😷','🤒','🤕','🤢','🤮','🤧','🥵','🥶','😵','🤯','🥳','😎','🤓','🧐','😕','🙁','😮','😯','😲','😳','🥺','😦','😧','😨','😢','😭','😱','😖','😞','😓','😩','😫','😤','😡','😠','🤬','😈','💀','👻','💩','🤡','👹','👺','👽','👾','🤖'] },
  { icon: '👋', emojis: ['👋','🤚','🖐','✋','👌','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️','👍','👎','✊','👊','👏','🙌','🙏','💪','🤝','🫶','💅','🤳'] },
  { icon: '❤️', emojis: ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖','💘','💝','💯','✨','🌟','⭐','🔥','🎉','🎊','🎈','🎁','🏆','🥇','🎯','🎮','🎲','🎭','🎪','🎨','🎵','🎶','🎤','🎸','🎹','🎺','🥁'] },
  { icon: '🐶', emojis: ['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🐔','🐧','🐦','🐤','🦆','🦅','🦉','🦇','🐝','🦋','🐌','🐞','🐢','🐍','🦎','🐙','🦑','🐟','🐬','🐳','🦈','🐊','🐘','🦒','🦓','🦍','🦧','🦬','🐕','🐈','🐓','🦃','🦚','🦜','🦩','🌵','🌲','🌳','🌴','🌱','🌿','☘️','🍀','🍁','🌾','🍄','🌸','🌺','🌻','🌹','🌷','💐','🌊','🌙','⭐','☀️','🌈','⛄','🌍'] },
  { icon: '🍕', emojis: ['🍕','🍔','🍟','🌭','🌮','🌯','🥙','🍳','🥗','🍲','🍜','🍝','🍣','🍱','🍛','🍚','🍿','🍩','🍪','🎂','🍰','🧁','🍫','🍬','🍭','☕','🍵','🧋','🥤','🧃','🍺','🍷','🥂','🍸','🍹','🥃','🍾','🍎','🍊','🍋','🍇','🍓','🫐','🍒','🍑','🥭','🍍','🥥','🍌','🍉','🍈','🍏'] },
]

function insertEmoji(emoji) {
  messageText.value += emoji
  showEmojiPicker.value = false
}

async function handleImageUpload(e) {
  const file = e.target.files[0]
  if (!file) return
  imageInput.value.value = ''
  const formData = new FormData()
  formData.append('file', file)
  const token = localStorage.getItem('nexchat_token')
  uploadingImage.value = true
  try {
    const res = await fetch(`${API_BASE}/media/upload`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: formData
    })
    if (!res.ok) throw new Error()
    const { url } = await res.json()
    await chatHub.invoke('SendMessage', sessionId, url, 'image')
  } finally {
    uploadingImage.value = false
  }
}

const currentUserId = computed(() => auth.user?.id)
const partner = computed(() => chat.partner)
const messages = computed(() => chat.messages)
const partnerLetter = computed(() => partner.value?.name?.[0]?.toUpperCase() || '?')
const partnerColor = computed(() => {
  if (!partner.value) return '#6C63FF'
  const colors = ['#6C63FF', '#FF6584', '#00D4FF', '#FF8C42']
  return colors[partner.value.name.charCodeAt(0) % colors.length]
})
const partnerAvatarIsImage = computed(() =>
  partner.value?.avatar && (partner.value.avatar.startsWith('http') || partner.value.avatar.startsWith('/'))
)
const partnerAvatarIsEmoji = computed(() =>
  partner.value?.avatar && !partnerAvatarIsImage.value
)

function formatTime(sec) {
  const m = Math.floor(sec / 60).toString().padStart(2, '0')
  const s = (sec % 60).toString().padStart(2, '0')
  return `${m}:${s}`
}

onMounted(async () => {
  await startHub(chatHub)

  chatHub.on('ReceiveMessage', (msg) => {
    chat.addMessage(msg)
    scrollToBottom()
  })

  chatHub.on('UserTyping', () => { chat.partnerTyping = true })
  chatHub.on('UserStoppedTyping', () => { chat.partnerTyping = false })

  chatHub.on('SessionEnded', () => {
    sessionEnded.value = true
    clearInterval(timerInterval)
    chat.addMessage({ id: Date.now(), type: 'system', content: '🔴 انتهت المحادثة', sentAt: new Date() })
  })

  chatHub.on('SessionJoined', ({ partner: p, messages: msgs }) => {
    if (!chat.partner) chat.partner = p
    if (msgs?.length) {
      msgs.forEach(m => chat.addMessage(m))
      scrollToBottom()
    }
  })

  chatHub.on('ReportSent', () => {
    showReport.value = false
    alert('تم إرسال البلاغ بنجاح')
  })

  chatHub.on('IncomingVideoCall', () => {
    incomingCall.value = true
  })

  chatHub.on('VideoCallAccepted', () => {
    router.push({ path: `/video/${sessionId}`, state: { initiator: true } })
  })

  chatHub.on('VideoCallDeclined', () => {
    callDeclined.value = true
    setTimeout(() => { callDeclined.value = false }, 3000)
  })

  await chatHub.invoke('JoinSession', sessionId)

  timerInterval = setInterval(() => {
    if (!sessionEnded.value) timerSeconds.value++
  }, 1000)
})

onUnmounted(() => {
  clearInterval(timerInterval)
  chatHub.off('ReceiveMessage')
  chatHub.off('UserTyping')
  chatHub.off('UserStoppedTyping')
  chatHub.off('SessionEnded')
  chatHub.off('SessionJoined')
  chatHub.off('ReportSent')
  chatHub.off('IncomingVideoCall')
  chatHub.off('VideoCallAccepted')
  chatHub.off('VideoCallDeclined')
})

watch(messages, () => nextTick(scrollToBottom))

function scrollToBottom() {
  if (messagesEl.value)
    messagesEl.value.scrollTop = messagesEl.value.scrollHeight
}

let typingTimeout
async function handleInput() {
  if (!typingTimeout) await chatHub.invoke('StartTyping', sessionId)
  clearTimeout(typingTimeout)
  typingTimeout = setTimeout(async () => {
    await chatHub.invoke('StopTyping', sessionId)
    typingTimeout = null
  }, 1500)
}

async function sendMessage() {
  const text = messageText.value.trim()
  if (!text || sessionEnded.value) return
  messageText.value = ''
  if (typingTimeout) {
    clearTimeout(typingTimeout)
    typingTimeout = null
    await chatHub.invoke('StopTyping', sessionId)
  }
  await chatHub.invoke('SendMessage', sessionId, text, 'text')
}

async function leaveSession() {
  clearInterval(timerInterval)
  await chatHub.invoke('LeaveSession', sessionId)
  chat.clearSession()
  router.replace('/home')
}

async function nextPerson() {
  clearInterval(timerInterval)
  await chatHub.invoke('LeaveSession', sessionId)
  chat.clearSession()
  router.replace('/matching')
  // Restart search
  const { matchingHub: mHub, startHub: sHub } = await import('../services/signalr')
  await sHub(mHub)
  await mHub.invoke('StartSearching', 'all')
}

async function submitReport() {
  if (!reportReason.value.trim()) return
  await chatHub.invoke('ReportUser', sessionId, reportReason.value)
  reportReason.value = ''
}

async function startVideo() {
  await chatHub.invoke('RequestVideoCall', sessionId)
}

async function acceptCall() {
  incomingCall.value = false
  await chatHub.invoke('AcceptVideoCall', sessionId)
  router.push({ path: `/video/${sessionId}`, state: { initiator: false } })
}

async function declineCall() {
  incomingCall.value = false
  await chatHub.invoke('DeclineVideoCall', sessionId)
}

function openImage(url) {
  window.open(url, '_blank')
}
</script>

<template>
  <div class="chat-view page">
    <!-- Header -->
    <header class="chat-header glass-card">
      <div class="partner-info">
        <div class="avatar avatar-sm" :style="partnerAvatarIsImage ? {} : { background: partnerColor }">
          <img v-if="partnerAvatarIsImage" :src="partner.avatar" class="partner-avatar-img" />
          <span v-else-if="partnerAvatarIsEmoji">{{ partner.avatar }}</span>
          <span v-else>{{ partnerLetter }}</span>
        </div>
        <div>
          <div class="partner-name">{{ partner?.name || 'جارٍ التحميل...' }}</div>
          <div class="typing-status text-sm text-muted">
            <span v-if="chat.partnerTyping" class="typing-text">
              <span class="typing-dots"><span></span><span></span><span></span></span>
              يكتب...
            </span>
            <span v-else>{{ formatTime(timerSeconds) }}</span>
          </div>
        </div>
      </div>

      <div class="header-actions">
        <button class="icon-btn" @click="startVideo" title="فيديو كول"><Video :size="20" /></button>
        <button class="icon-btn" @click="showReport = !showReport" title="بلاغ"><Flag :size="20" /></button>
        <button class="icon-btn danger" @click="leaveSession" title="إنهاء"><X :size="20" /></button>
      </div>
    </header>

    <!-- Incoming Call Overlay -->
    <Transition name="fade">
      <div v-if="incomingCall" class="call-overlay">
        <div class="call-popup glass-card">
          <div class="call-popup-avatar" :style="partnerAvatarIsImage ? { padding: 0, overflow: 'hidden' } : { background: partnerColor }">
            <img v-if="partnerAvatarIsImage" :src="partner.avatar" style="width:100%;height:100%;object-fit:cover;border-radius:50%" />
            <span v-else-if="partnerAvatarIsEmoji" style="font-size:32px">{{ partner.avatar }}</span>
            <span v-else>{{ partnerLetter }}</span>
          </div>
          <div class="call-popup-name">{{ partner?.name }}</div>
          <div class="call-popup-label">يطلب مكالمة فيديو</div>
          <div class="call-popup-actions">
            <button class="call-btn decline" @click="declineCall"><X :size="18" /> رفض</button>
            <button class="call-btn accept" @click="acceptCall"><Check :size="18" /> قبول</button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Call Declined Toast -->
    <Transition name="fade">
      <div v-if="callDeclined" class="declined-toast">رفض {{ partner?.name }} المكالمة</div>
    </Transition>

    <!-- Report Sheet -->
    <Transition name="slide-up">
      <div v-if="showReport" class="report-sheet glass-card">
        <div class="text-sm text-secondary" style="margin-bottom:8px">سبب البلاغ:</div>
        <input v-model="reportReason" class="input-field" placeholder="اكتب السبب..." />
        <div class="flex gap-2" style="margin-top:8px">
          <button class="btn-gradient" style="padding:10px" @click="submitReport">إرسال</button>
          <button class="btn-ghost" style="padding:10px;flex:1" @click="showReport=false">إلغاء</button>
        </div>
      </div>
    </Transition>

    <!-- Messages -->
    <div class="messages-area" ref="messagesEl">
      <div v-if="!messages.length" class="empty-chat text-muted text-sm">
        ابدأ المحادثة بأول رسالة! 👋
      </div>

      <div
        v-for="msg in messages"
        :key="msg.id"
        :class="['message-wrap', msg.type === 'system' ? 'system' : msg.senderId === currentUserId ? 'mine' : 'theirs']"
      >
        <div v-if="msg.type === 'system'" class="system-msg">{{ msg.content }}</div>
        <div v-else-if="msg.type === 'image'" class="bubble image-bubble">
          <img :src="msg.content" class="chat-image" @click="openImage(msg.content)" />
        </div>
        <div v-else class="bubble">{{ msg.content }}</div>
        <div v-if="msg.type !== 'system'" class="msg-time text-muted">
          {{ new Date(msg.sentAt).toLocaleTimeString('ar', { hour: '2-digit', minute: '2-digit' }) }}
        </div>
      </div>

      <div v-if="chat.partnerTyping" class="message-wrap theirs">
        <div class="bubble typing-bubble">
          <span class="typing-dots"><span></span><span></span><span></span></span>
        </div>
      </div>
    </div>

    <!-- Session Ended Banner -->
    <div v-if="sessionEnded" class="ended-banner">
      <span>انتهت المحادثة</span>
      <button class="next-btn gradient-text" @click="nextPerson"><ChevronLeft :size="18" /> التالي</button>
    </div>

    <!-- Input -->
    <div v-else class="input-area">
      <div class="next-btn-wrap">
        <button class="btn-ghost next-small" @click="nextPerson"><ChevronLeft :size="16" /> التالي</button>
      </div>

      <!-- Emoji Picker -->
      <Transition name="slide-up">
        <div v-if="showEmojiPicker" class="emoji-picker glass-card">
          <div class="emoji-tabs">
            <button
              v-for="(cat, i) in emojiCategories"
              :key="i"
              class="emoji-tab"
              :class="{ active: activeEmojiTab === i }"
              @click="activeEmojiTab = i"
            >{{ cat.icon }}</button>
          </div>
          <div class="emoji-grid">
            <button
              v-for="emoji in emojiCategories[activeEmojiTab].emojis"
              :key="emoji"
              class="emoji-btn"
              @click="insertEmoji(emoji)"
            >{{ emoji }}</button>
          </div>
        </div>
      </Transition>

      <div class="message-input-row">
        <button class="input-action-btn" @click="showEmojiPicker = !showEmojiPicker" :class="{ active: showEmojiPicker }"><Smile :size="20" /></button>
        <button class="input-action-btn" @click="imageInput.click()" :disabled="uploadingImage">
          <Loader2 v-if="uploadingImage" :size="20" class="spin" />
          <Image v-else :size="20" />
        </button>
        <input
          ref="imageInput"
          type="file"
          accept="image/*"
          style="display:none"
          @change="handleImageUpload"
        />
        <input
          v-model="messageText"
          class="input-field msg-input"
          placeholder="اكتب رسالة..."
          @input="handleInput"
          @keyup.enter="sendMessage"
          @focus="showEmojiPicker = false"
          :disabled="sessionEnded"
          maxlength="2000"
        />
        <button
          class="send-btn"
          @click="sendMessage"
          :disabled="!messageText.trim() || sessionEnded"
        >
          <Send :size="20" />
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.chat-view {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
}

.chat-header {
  align-items: center;
  border-radius: 0 0 var(--radius) var(--radius);
  display: flex;
  justify-content: space-between;
  padding: calc(8px + var(--safe-top)) var(--spacing) var(--spacing);
  flex-shrink: 0;
  z-index: 20;
  border-top: none;
}

.partner-info { display: flex; align-items: center; gap: 10px; }
.partner-avatar-img { width: 100%; height: 100%; object-fit: cover; border-radius: 50%; }
.partner-name { font-size: 15px; font-weight: 600; }
.typing-status { margin-top: 2px; min-height: 16px; }

.header-actions { display: flex; gap: 8px; }
.icon-btn {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  height: var(--touch-min);
  justify-content: center;
  min-width: var(--touch-min);
  padding: 0;
  transition: background 0.2s;
}
.icon-btn:active { background: var(--bg-card-hover); }
.icon-btn.danger { background: rgba(255,101,132,0.15); color: var(--danger); }

.report-sheet {
  margin: 8px 16px;
  padding: 14px;
  flex-shrink: 0;
  z-index: 15;
}

.messages-area {
  flex: 1;
  overflow-y: auto;
  padding: 16px 16px 8px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.empty-chat {
  text-align: center;
  margin: auto;
}

.message-wrap {
  display: flex;
  flex-direction: column;
  max-width: 80%;
}
.message-wrap.mine { align-self: flex-end; align-items: flex-end; }
.message-wrap.theirs { align-self: flex-start; align-items: flex-start; }
.message-wrap.system { align-self: center; max-width: 100%; }

.bubble {
  background: rgba(255,255,255,0.08);
  border-radius: 16px;
  padding: 10px 14px;
  font-size: 15px;
  word-break: break-word;
  line-height: 1.5;
}
.mine .bubble {
  background: var(--primary);
  border-bottom-right-radius: 4px;
}
.theirs .bubble {
  border-bottom-left-radius: 4px;
}

.msg-time { color: var(--text-muted); font-size: 11px; margin-top: 4px; }

.system-msg {
  background: rgba(255,255,255,0.05);
  border-radius: 20px;
  color: var(--text-muted);
  font-size: 12px;
  padding: 6px 14px;
  text-align: center;
}

.typing-bubble { padding: 12px 16px; }
.typing-dots {
  display: flex;
  gap: 4px;
  align-items: center;
}
.typing-dots span {
  background: var(--text-muted);
  border-radius: 50%;
  width: 6px; height: 6px;
  animation: bounce 1.2s ease-in-out infinite;
}
.typing-dots span:nth-child(2) { animation-delay: 0.2s; }
.typing-dots span:nth-child(3) { animation-delay: 0.4s; }
@keyframes bounce { 0%,100%{transform:translateY(0)} 50%{transform:translateY(-4px)} }

.typing-text { display: flex; align-items: center; gap: 6px; }

.ended-banner {
  background: rgba(255,101,132,0.1);
  border-top: 1px solid rgba(255,101,132,0.2);
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 20px;
  flex-shrink: 0;
  color: var(--text-secondary);
  font-size: 14px;
}

.input-area {
  padding: 8px var(--spacing) calc(var(--spacing) + var(--safe-bottom));
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.next-btn-wrap { display: flex; justify-content: flex-end; }
.next-small {
  align-items: center;
  display: flex;
  font-size: 13px;
  gap: 4px;
  padding: 6px 14px;
}

.message-input-row {
  display: flex;
  gap: 8px;
  align-items: flex-end;
}

.msg-input {
  flex: 1;
  border-radius: var(--radius-full);
  padding: 12px 18px;
}

.send-btn {
  background: var(--primary);
  border: none;
  border-radius: 50%;
  color: white;
  cursor: pointer;
  height: var(--touch-min);
  width: var(--touch-min);
  min-width: var(--touch-min);
  flex-shrink: 0;
  transition: opacity 0.2s;
  display: flex;
  align-items: center;
  justify-content: center;
}
.send-btn:disabled { opacity: 0.5; cursor: not-allowed; }
.send-btn:not(:disabled):active { opacity: 0.9; }

.next-btn {
  align-items: center;
  background: none;
  border: none;
  color: var(--primary);
  cursor: pointer;
  display: flex;
  font-size: 14px;
  font-weight: 600;
  gap: 4px;
}

.call-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0,0,0,0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
  backdrop-filter: blur(4px);
}

.call-popup {
  width: 80%;
  max-width: 300px;
  padding: 28px 20px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
}

.call-popup-avatar {
  width: 72px;
  height: 72px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 28px;
  font-weight: 700;
  color: white;
  animation: ring-pulse 1.5s ease-in-out infinite;
  box-shadow: 0 0 0 0 rgba(108,99,255,0.4);
}
@keyframes ring-pulse {
  0% { box-shadow: 0 0 0 0 rgba(108,99,255,0.5); }
  70% { box-shadow: 0 0 0 16px rgba(108,99,255,0); }
  100% { box-shadow: 0 0 0 0 rgba(108,99,255,0); }
}

.call-popup-name { font-size: 18px; font-weight: 700; color: white; }
.call-popup-label { font-size: 13px; color: var(--text-muted); }

.call-popup-actions {
  display: flex;
  gap: 12px;
  margin-top: 8px;
  width: 100%;
}

.call-btn {
  align-items: center;
  border: none;
  border-radius: var(--radius-sm);
  cursor: pointer;
  display: flex;
  flex: 1;
  font-family: 'Cairo';
  font-size: 14px;
  font-weight: 600;
  gap: 6px;
  justify-content: center;
  min-height: var(--touch-min);
  padding: 0 12px;
  transition: opacity 0.2s;
}
.call-btn.accept { background: var(--success); color: white; }
.call-btn.accept:active { opacity: 0.9; }
.call-btn.decline { background: rgba(255,101,132,0.2); color: var(--danger); border: 1px solid rgba(255,101,132,0.3); }
.call-btn.decline:active { opacity: 0.9; }

.declined-toast {
  position: absolute;
  top: 70px;
  left: 50%;
  transform: translateX(-50%);
  background: rgba(255,101,132,0.15);
  border: 1px solid rgba(255,101,132,0.3);
  border-radius: var(--radius-full);
  color: #FF6584;
  font-size: 13px;
  padding: 8px 18px;
  z-index: 50;
  white-space: nowrap;
}

.fade-enter-active, .fade-leave-active { transition: opacity 0.25s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }

/* Emoji Picker */
.emoji-picker {
  padding: 0;
  overflow: hidden;
  margin-bottom: 8px;
  flex-shrink: 0;
}

.emoji-tabs {
  display: flex;
  gap: 0;
  border-bottom: 1px solid var(--border);
  overflow-x: auto;
  scrollbar-width: none;
}
.emoji-tabs::-webkit-scrollbar { display: none; }

.emoji-tab {
  background: none;
  border: none;
  border-bottom: 2px solid transparent;
  cursor: pointer;
  font-size: 20px;
  padding: 8px 14px;
  flex-shrink: 0;
  transition: 0.15s;
}
.emoji-tab.active { border-bottom-color: #6C63FF; }

.emoji-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 2px;
  max-height: 180px;
  overflow-y: auto;
  padding: 8px;
  scrollbar-width: thin;
  scrollbar-color: rgba(255,255,255,0.1) transparent;
}

.emoji-btn {
  background: none;
  border: none;
  border-radius: 8px;
  cursor: pointer;
  font-size: 22px;
  height: 38px;
  width: 38px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: 0.1s;
  flex-shrink: 0;
}
.emoji-btn:hover { background: rgba(255,255,255,0.1); transform: scale(1.2); }
.emoji-btn:active { transform: scale(0.95); }

/* Input action buttons */
.input-action-btn {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  height: var(--touch-min);
  justify-content: center;
  min-width: var(--touch-min);
  padding: 0;
  transition: background 0.2s;
  flex-shrink: 0;
}
.input-action-btn:active { background: var(--bg-card-hover); }
.input-action-btn.active { background: rgba(108,99,255,0.2); color: var(--primary); }
.input-action-btn:disabled { opacity: 0.5; cursor: not-allowed; }
.spin { animation: spin 0.8s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

/* Image in chat */
.image-bubble { padding: 4px !important; overflow: hidden; }
.chat-image {
  border-radius: 12px;
  cursor: pointer;
  display: block;
  max-width: 220px;
  max-height: 280px;
  object-fit: cover;
  transition: 0.2s;
}
.chat-image:hover { opacity: 0.9; transform: scale(1.02); }

.slide-up-enter-active, .slide-up-leave-active { transition: all 0.2s ease; }
.slide-up-enter-from, .slide-up-leave-to { opacity: 0; transform: translateY(10px); }
</style>
