<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Video, Flag, X, Check, ChevronLeft, Smile, Image, Send, Loader2, Clock, AlertCircle, RotateCcw, CheckCircle2 } from 'lucide-vue-next'
import { useAuthStore } from '../stores/auth'
import { useChatStore } from '../stores/chat'
import { chatHub, startHub, ensureConnected } from '../services/signalr'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { ensureAbsoluteUrl } from '../utils/imageUrl'

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
const showReportSuccess = ref(false)
const incomingCall = ref(false)
const callDeclined = ref(false)
const showVideoConfirm = ref(false)
const callingOut = ref(false)
const showEmojiPicker = ref(false)
const activeEmojiTab = ref(0)
const imageInput = ref(null)
const uploadingImage = ref(false)
const loading = ref(false)
const imageModalUrl = ref(null)
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
    const tempId = `temp-${Date.now()}-${Math.random().toString(36).slice(2)}`
    chat.addMessage({
      tempId,
      senderId: auth.user?.id,
      content: url,
      type: 'image',
      sentAt: new Date(),
      status: 'pending'
    })
    scrollToBottom()
    try {
      await ensureConnected(chatHub)
      await chatHub.invoke('SendMessage', sessionId, url, 'image')
    } catch {
      chat.updateMessage(tempId, { status: 'failed' })
    }
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
const isSupportChat = computed(() => partner.value?.name === 'دعم')

function normalizeServerMsg(msg) {
  return {
    id: msg.id ?? msg.Id,
    senderId: msg.senderId ?? msg.SenderId,
    content: msg.content ?? msg.Content,
    type: msg.type ?? msg.Type ?? 'text',
    sentAt: msg.sentAt ?? msg.SentAt
  }
}

function formatTime(sec) {
  const m = Math.floor(sec / 60).toString().padStart(2, '0')
  const s = (sec % 60).toString().padStart(2, '0')
  return `${m}:${s}`
}

async function onVisibilityChange() {
  if (document.visibilityState === 'visible' && !sessionEnded.value) {
    try {
      await ensureConnected(chatHub)
      await chatHub.invoke('JoinSession', sessionId)
    } catch {}
  }
}

onMounted(async () => {
  loading.value = true
  await startHub(chatHub)

  chatHub.on('ReceiveMessage', (msg) => {
    const senderId = msg.senderId ?? msg.SenderId
    const myId = auth.user?.id
    if (myId && String(senderId) === String(myId)) {
      chat.updatePendingMessage(normalizeServerMsg(msg))
    } else {
      chat.addMessage({ ...normalizeServerMsg(msg), status: 'sent' })
    }
    scrollToBottom()
  })

  chatHub.on('UserTyping', () => { chat.partnerTyping = true })
  chatHub.on('UserStoppedTyping', () => { chat.partnerTyping = false })

  chatHub.on('SessionEnded', () => {
    sessionEnded.value = true
    clearInterval(timerInterval)
    chat.addMessage({ id: Date.now(), type: 'system', content: '🔴 انتهت المحادثة', sentAt: new Date() })
  })

  chatHub.on('SessionJoined', (data) => {
    const p = data.partner ?? data.Partner
    const msgs = data.messages ?? data.Messages ?? []
    if (!chat.partner) chat.partner = p
    if (!chat.session && (data.id ?? data.Id)) chat.$patch({ session: data.id ?? data.Id })
    // إضافة الرسائل فقط عند الانضمام الأول (لا يوجد رسائل بعد) لتجنب التكرار عند إعادة الاتصال
    if (msgs?.length && chat.messages.length === 0) {
      msgs.forEach(m => chat.addMessage({ ...normalizeServerMsg(m), status: 'sent' }))
      scrollToBottom()
    }
  })

  chatHub.on('ReportSent', () => {
    showReport.value = false
    showReportSuccess.value = true
    setTimeout(() => { showReportSuccess.value = false }, 3500)
  })

  chatHub.on('IncomingVideoCall', () => {
    incomingCall.value = true
  })

  chatHub.on('VideoCallAccepted', () => {
    callingOut.value = false
    router.push({ path: `/video/${sessionId}`, state: { initiator: true } })
  })

  chatHub.on('VideoCallDeclined', () => {
    callingOut.value = false
    callDeclined.value = true
    setTimeout(() => { callDeclined.value = false }, 3000)
  })

  try {
    await chatHub.invoke('JoinSession', sessionId)
  } finally {
    loading.value = false
  }

  chatHub.onreconnected(async () => {
    if (!sessionEnded.value) {
      try {
        await chatHub.invoke('JoinSession', sessionId)
      } catch {}
    }
  })

  document.addEventListener('visibilitychange', onVisibilityChange)

  timerInterval = setInterval(() => {
    if (!sessionEnded.value) timerSeconds.value++
  }, 1000)
})

onUnmounted(() => {
  clearInterval(timerInterval)
  document.removeEventListener('visibilitychange', onVisibilityChange)
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
  try {
    await ensureConnected(chatHub)
    if (!typingTimeout) await chatHub.invoke('StartTyping', sessionId)
  } catch {}
  clearTimeout(typingTimeout)
  typingTimeout = setTimeout(async () => {
    try {
      await ensureConnected(chatHub)
      await chatHub.invoke('StopTyping', sessionId)
    } catch {}
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
  const tempId = `temp-${Date.now()}-${Math.random().toString(36).slice(2)}`
  chat.addMessage({
    tempId,
    senderId: auth.user?.id,
    content: text,
    type: 'text',
    sentAt: new Date(),
    status: 'pending'
  })
  scrollToBottom()
  try {
    await ensureConnected(chatHub)
    await chatHub.invoke('SendMessage', sessionId, text, 'text')
  } catch {
    chat.updateMessage(tempId, { status: 'failed' })
  }
}

async function retryMessage(msg) {
  if (msg.status !== 'failed') return
  const tempId = `temp-${Date.now()}-${Math.random().toString(36).slice(2)}`
  chat.updateMessage(msg.tempId, { tempId, status: 'pending' })
  try {
    await ensureConnected(chatHub)
    await chatHub.invoke('SendMessage', sessionId, msg.content, msg.type || 'text')
  } catch {
    chat.updateMessage(tempId, { status: 'failed' })
  }
}

async function leaveSession() {
  loading.value = true
  clearInterval(timerInterval)
  try {
    await ensureConnected(chatHub)
    await chatHub.invoke('LeaveSession', sessionId)
    chat.clearSession()
    router.replace(isSupportChat.value ? '/settings' : '/home')
  } finally {
    loading.value = false
  }
}

async function nextPerson() {
  loading.value = true
  clearInterval(timerInterval)
  try {
    await ensureConnected(chatHub)
    await chatHub.invoke('LeaveSession', sessionId)
    chat.clearSession()
    router.replace('/matching')
    const { matchingHub: mHub, startHub: sHub } = await import('../services/signalr')
    await sHub(mHub)
    await ensureConnected(mHub)
    await mHub.invoke('StartSearching', 'all')
  } finally {
    loading.value = false
  }
}

async function submitReport() {
  if (!reportReason.value.trim()) return
  loading.value = true
  try {
    await ensureConnected(chatHub)
    await chatHub.invoke('ReportUser', sessionId, reportReason.value)
    reportReason.value = ''
    showReport.value = false
  } finally {
    loading.value = false
  }
}

function openVideoConfirm() {
  showVideoConfirm.value = true
}

async function confirmStartVideo() {
  showVideoConfirm.value = false
  callingOut.value = true
  await ensureConnected(chatHub)
  await chatHub.invoke('RequestVideoCall', sessionId)
}

function cancelVideoConfirm() {
  showVideoConfirm.value = false
}

async function acceptCall() {
  incomingCall.value = false
  await ensureConnected(chatHub)
  await chatHub.invoke('AcceptVideoCall', sessionId)
  router.push({ path: `/video/${sessionId}`, state: { initiator: false } })
}

async function declineCall() {
  incomingCall.value = false
  await ensureConnected(chatHub)
  await chatHub.invoke('DeclineVideoCall', sessionId)
}

function openImage(url) {
  imageModalUrl.value = url
}

function closeImageModal() {
  imageModalUrl.value = null
}
</script>

<template>
  <div class="chat-view page">
    <LoaderOverlay :show="loading" text="جاري التحميل..." />
    <!-- Header -->
    <header class="chat-header glass-card">
      <div class="partner-info">
        <div class="avatar avatar-sm" :style="partnerAvatarIsImage ? {} : { background: partnerColor }">
          <img v-if="partnerAvatarIsImage" :src="ensureAbsoluteUrl(partner.avatar)" class="partner-avatar-img" referrerpolicy="no-referrer" />
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
            <span v-else-if="isSupportChat">دردشة الدعم</span>
            <span v-else>{{ formatTime(timerSeconds) }}</span>
          </div>
        </div>
      </div>

      <div class="header-actions">
        <template v-if="!isSupportChat">
          <button class="icon-btn" @click="openVideoConfirm" title="فيديو كول"><Video :size="20" /></button>
          <button class="icon-btn" @click="showReport = !showReport" title="بلاغ"><Flag :size="20" /></button>
          <button class="icon-btn next-header-btn" @click="nextPerson" title="التالي"><ChevronLeft :size="20" /></button>
        </template>
        <button class="icon-btn" :class="{ danger: !isSupportChat }" @click="leaveSession" :title="isSupportChat ? 'رجوع' : 'إنهاء'">
          <ChevronRight v-if="isSupportChat" :size="20" />
          <X v-else :size="20" />
        </button>
      </div>
    </header>

    <!-- Incoming Call Overlay -->
    <Transition name="fade">
      <div v-if="incomingCall" class="call-overlay">
        <div class="call-popup glass-card">
          <div class="call-popup-avatar" :style="partnerAvatarIsImage ? { padding: 0, overflow: 'hidden' } : { background: partnerColor }">
            <img v-if="partnerAvatarIsImage" :src="ensureAbsoluteUrl(partner.avatar)" style="width:100%;height:100%;object-fit:cover;border-radius:50%" referrerpolicy="no-referrer" />
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

    <!-- Video Call Confirmation -->
    <Transition name="fade">
      <div v-if="showVideoConfirm" class="call-overlay">
        <div class="call-popup glass-card">
          <div class="call-popup-avatar" :style="partnerAvatarIsImage ? { padding: 0, overflow: 'hidden' } : { background: partnerColor }">
            <img v-if="partnerAvatarIsImage" :src="ensureAbsoluteUrl(partner.avatar)" style="width:100%;height:100%;object-fit:cover;border-radius:50%" referrerpolicy="no-referrer" />
            <span v-else-if="partnerAvatarIsEmoji" style="font-size:32px">{{ partner.avatar }}</span>
            <span v-else>{{ partnerLetter }}</span>
          </div>
          <div class="call-popup-name">{{ partner?.name }}</div>
          <div class="call-popup-label">طلب مكالمة فيديو مع {{ partner?.name }}؟</div>
          <div class="call-popup-actions">
            <button class="call-btn decline" @click="cancelVideoConfirm"><X :size="18" /> إلغاء</button>
            <button class="call-btn accept" @click="confirmStartVideo"><Video :size="18" /> طلب</button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Calling Out Loader -->
    <Transition name="fade">
      <div v-if="callingOut" class="call-overlay">
        <div class="call-popup glass-card calling-popup">
          <div class="calling-loader">
            <Loader2 :size="48" class="spin" />
          </div>
          <div class="call-popup-name">{{ partner?.name }}</div>
          <div class="call-popup-label">جاري الاتصال...</div>
          <div class="calling-dots">
            <span></span><span></span><span></span>
          </div>
          <button class="call-btn decline calling-cancel" @click="callingOut = false">
            <X :size="18" /> إلغاء الطلب
          </button>
        </div>
      </div>
    </Transition>

    <!-- Call Declined Toast -->
    <Transition name="fade">
      <div v-if="callDeclined" class="declined-toast">رفض {{ partner?.name }} المكالمة</div>
    </Transition>

    <!-- Report Success Modal -->
    <Transition name="modal">
      <div v-if="showReportSuccess" class="success-overlay" @click.self="showReportSuccess = false">
        <div class="success-modal glass-card">
          <div class="success-icon-wrap">
            <CheckCircle2 :size="56" class="success-icon" />
          </div>
          <h3 class="success-title">تم إرسال البلاغ بنجاح</h3>
          <p class="success-text">تم استلام البلاغ وسيتم مراجعته من قبل الفريق</p>
          <button class="success-btn" @click="showReportSuccess = false">حسناً</button>
        </div>
      </div>
    </Transition>

    <!-- Image Modal -->
    <Transition name="fade">
      <div v-if="imageModalUrl" class="image-modal-overlay" @click.self="closeImageModal">
        <button class="image-modal-close" @click="closeImageModal" aria-label="إغلاق"><X :size="24" /></button>
        <img :src="ensureAbsoluteUrl(imageModalUrl)" class="image-modal-img" alt="" @click.stop referrerpolicy="no-referrer" />
      </div>
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
        :key="msg.tempId || msg.id"
        :class="['message-wrap', msg.type === 'system' ? 'system' : msg.senderId === currentUserId ? 'mine' : 'theirs']"
      >
        <div v-if="msg.type === 'system'" class="system-msg">{{ msg.content }}</div>
        <div v-else-if="msg.type === 'image'" class="bubble image-bubble">
          <img :src="ensureAbsoluteUrl(msg.content)" class="chat-image" @click="openImage(msg.content)" referrerpolicy="no-referrer" />
        </div>
        <div v-else class="bubble">{{ msg.content }}</div>
        <div v-if="msg.type !== 'system'" class="msg-meta">
          <span class="msg-time text-muted">
            {{ new Date(msg.sentAt).toLocaleTimeString('ar', { hour: '2-digit', minute: '2-digit' }) }}
          </span>
          <span v-if="msg.senderId === currentUserId" class="msg-status">
            <Clock v-if="msg.status === 'pending'" :size="14" class="status-pending" />
            <Check v-else-if="msg.status === 'sent' || !msg.status" :size="14" class="status-sent" />
            <span v-else-if="msg.status === 'failed'" class="status-failed-wrap">
              <AlertCircle :size="14" class="status-failed" />
              <button class="retry-btn" @click="retryMessage(msg)"><RotateCcw :size="12" /> إعادة</button>
            </span>
          </span>
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
          class="msg-input"
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
  overflow: hidden;
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
  background: var(--msg-theirs-bg);
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

.msg-meta {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 4px;
}
.msg-time { color: var(--text-muted); font-size: 11px; }
.msg-status { display: inline-flex; align-items: center; }
.status-pending { color: var(--text-muted); opacity: 0.8; }
.status-sent { color: var(--primary); }
.status-failed-wrap {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
.status-failed { color: var(--danger); }
.retry-btn {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  background: rgba(255,101,132,0.2);
  border: 1px solid rgba(255,101,132,0.4);
  border-radius: 6px;
  color: var(--danger);
  cursor: pointer;
  font-size: 10px;
  font-family: 'Cairo', sans-serif;
  padding: 2px 6px;
  -webkit-tap-highlight-color: transparent;
}
.retry-btn:active { opacity: 0.9; }

.system-msg {
  background: var(--system-msg-bg);
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

.next-header-btn { color: var(--primary); }

.message-input-row {
  display: flex;
  gap: 10px;
  align-items: center;
  min-height: 48px;
}

.msg-input {
  flex: 1;
  min-width: 0;
  min-height: 48px;
  padding: 0 18px;
  border-radius: 24px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  color: var(--text-primary);
  font-size: 16px;
  font-family: 'Cairo', sans-serif;
  outline: none;
  -webkit-appearance: none;
  appearance: none;
}
.msg-input::placeholder { color: var(--text-muted); }
.msg-input:focus { border-color: var(--primary); }

.send-btn {
  background: var(--primary);
  border: none;
  border-radius: 50%;
  color: white;
  cursor: pointer;
  height: 48px;
  width: 48px;
  min-width: 48px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.15s, opacity 0.2s;
}
.send-btn:not(:disabled):active { transform: scale(0.95); opacity: 0.95; }
.send-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.next-btn {
  align-items: center;
  background: none;
  border: none;
  color: var(--primary);
  cursor: pointer;
  display: flex;
  font-family: 'Cairo', sans-serif;
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

.calling-popup { gap: 16px; }
.calling-cancel {
  width: 100%;
  margin-top: 8px;
  box-shadow: 0 2px 12px rgba(255,101,132,0.25);
}
.calling-loader {
  color: var(--primary);
  display: flex;
  align-items: center;
  justify-content: center;
}
.calling-dots {
  display: flex;
  gap: 8px;
  justify-content: center;
}
.calling-dots span {
  background: rgba(255,255,255,0.4);
  border-radius: 50%;
  width: 8px;
  height: 8px;
  animation: dot-bounce 1.2s ease-in-out infinite;
}
.calling-dots span:nth-child(2) { animation-delay: 0.2s; }
.calling-dots span:nth-child(3) { animation-delay: 0.4s; }
@keyframes dot-bounce {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-6px); }
}

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

/* Report Success Modal */
.success-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0,0,0,0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 150;
  backdrop-filter: blur(6px);
}
.success-modal {
  width: 85%;
  max-width: 320px;
  padding: 28px 24px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 16px;
  text-align: center;
}
.success-icon-wrap {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 80px;
  height: 80px;
  border-radius: 50%;
  background: rgba(34, 197, 94, 0.15);
}
.success-icon {
  color: var(--success);
  flex-shrink: 0;
}
.success-title {
  font-size: 18px;
  font-weight: 700;
  color: var(--text-primary);
  margin: 0;
  font-family: 'Cairo', sans-serif;
}
.success-text {
  font-size: 14px;
  color: var(--text-secondary);
  margin: 0;
  line-height: 1.5;
}
.success-btn {
  width: 100%;
  min-height: 48px;
  padding: 0 24px;
  background: var(--primary);
  border: none;
  border-radius: var(--radius-sm);
  color: white;
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.success-btn:active { opacity: 0.9; }

.modal-enter-active, .modal-leave-active { transition: opacity 0.25s; }
.modal-enter-from, .modal-leave-to { opacity: 0; }

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
  border-radius: 12px;
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  height: 48px;
  justify-content: center;
  min-width: 48px;
  padding: 0;
  transition: background 0.2s, color 0.2s;
  flex-shrink: 0;
  -webkit-tap-highlight-color: transparent;
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

/* Image Modal */
.image-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 1000;
  background: rgba(0, 0, 0, 0.92);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  -webkit-tap-highlight-color: transparent;
}
.image-modal-close {
  position: absolute;
  top: 12px;
  right: 12px;
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.15);
  color: #fff;
  border: none;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 2;
  transition: background 0.2s;
}
.image-modal-close:active { background: rgba(255, 255, 255, 0.25); }
.image-modal-img {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
  border-radius: 8px;
}

.slide-up-enter-active, .slide-up-leave-active { transition: all 0.2s ease; }
.slide-up-enter-from, .slide-up-leave-to { opacity: 0; transform: translateY(10px); }
</style>
