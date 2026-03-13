<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronRight, Image, Send, MoreVertical, Trash2, UserX, X, Clock, Check, CheckCheck, AlertCircle, RotateCcw, Share2, Copy, Mic, Play, Pause } from 'lucide-vue-next'
import { useAuthStore } from '../stores/auth'
import { useConversationStore } from '../stores/conversation'
import { useConversationsListStore } from '../stores/conversationsList'
import { conversationHub, startHub, ensureConnected } from '../services/signalr'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { formatTime12 } from '../utils/formatTime'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../stores/locale'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const convStore = useConversationStore()
const listStore = useConversationsListStore()
const localeStore = useLocaleStore()
const { t } = useI18n()

const conversationId = route.params.conversationId
const messageText = ref('')
const messagesEl = ref(null)
const loading = ref(false)
const imageInput = ref(null)
let mediaRecorder = null
let currentStream = null
let audioChunks = []
const pendingAudioBlobs = new Map()
const msgInputRef = ref(null)
const uploadingImage = ref(false)
const isRecording = ref(false)
const uploadingVoice = ref(false)
const recordingSeconds = ref(0)
let recordingTimer = null
const imageModalUrl = ref(null)
const showMessageMenu = ref(null)
const showDeleteConvConfirm = ref(false)
const showShareModal = ref(false)
const shareCodeCopied = ref(false)
const showInputActionsMenu = ref(false)
const playingAudioId = ref(null)
const audioProgress = ref({})
const audioDurations = ref({})

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

function getMsgKey(msg) {
  return msg.tempId || msg.id || msg.Id
}

function linkifyText(text) {
  if (!text || typeof text !== 'string') return ''
  const escaped = text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
  const urlRegex = /(https?:\/\/[^\s<>]+)|(www\.[^\s<>]+)/gi
  return escaped.replace(urlRegex, (match) => {
    const href = match.startsWith('http') ? match : `https://${match}`
    return `<a href="${href.replace(/"/g, '&quot;')}" target="_blank" rel="noopener noreferrer" class="msg-link">${match}</a>`
  })
}

function handleMessageLinkClick(e) {
  const a = e.target.closest('a.msg-link')
  if (a) {
    e.preventDefault()
    e.stopPropagation()
    window.open(a.href, '_blank')
  }
}

function formatAudioDuration(sec) {
  if (sec == null || sec === Infinity || !Number.isFinite(sec) || sec < 0) return '0:00'
  const m = Math.floor(sec / 60)
  const s = Math.floor(sec % 60)
  return `${m}:${s.toString().padStart(2, '0')}`
}

function getAudioProgress(msg) {
  const key = getMsgKey(msg)
  const cur = audioProgress.value[key]
  const dur = audioDurations.value[key]
  return { current: cur, duration: dur }
}

function toggleAudioPlay(msg, el) {
  const key = getMsgKey(msg)
  if (!el) return
  if (playingAudioId.value === key) {
    el.pause()
  } else {
    document.querySelectorAll('.audio-bubble audio').forEach(a => { if (a !== el) a.pause() })
    el.play()
  }
}

function onAudioPlay(msg, e) {
  playingAudioId.value = getMsgKey(msg)
}

function onAudioPause(msg, e) {
  if (playingAudioId.value === getMsgKey(msg)) playingAudioId.value = null
}

function onAudioTimeUpdate(msg, e) {
  const el = e.target
  const key = getMsgKey(msg)
  if (Number.isFinite(el.duration) && el.duration > 0) {
    audioDurations.value[key] = el.duration
  }
  audioProgress.value[key] = Number.isFinite(el.currentTime) ? el.currentTime : 0
}

function onAudioLoadedMetadata(msg, e) {
  const key = getMsgKey(msg)
  const d = e.target.duration
  if (Number.isFinite(d) && d > 0) audioDurations.value[key] = d
}

const currentUserId = computed(() => auth.user?.id)
const partner = computed(() => convStore.partner)
const messages = computed(() => convStore.messages)
const partnerLetter = computed(() => partner.value?.name?.[0]?.toUpperCase() || '?')
const partnerAvatarIsImage = computed(() =>
  partner.value?.avatar && (partner.value.avatar.startsWith('http') || partner.value.avatar.startsWith('/'))
)

function normalizeMsg(msg) {
  return {
    id: msg.id ?? msg.Id,
    senderId: msg.senderId ?? msg.SenderId,
    content: msg.content ?? msg.Content,
    type: msg.type ?? msg.Type ?? 'text',
    sentAt: msg.sentAt ?? msg.SentAt,
    deletedForEveryone: msg.deletedForEveryone ?? msg.DeletedForEveryone,
    isRead: msg.isRead ?? msg.IsRead
  }
}

let mounted = true
let visibilityHandler = null
let markAsReadTimer = null
let markAsReadInterval = null
function markAsReadDebounced() {
  if (markAsReadTimer) clearTimeout(markAsReadTimer)
  markAsReadTimer = setTimeout(() => {
    markAsReadTimer = null
    if (!mounted) return
    ensureConnected(conversationHub).then(() =>
      conversationHub.invoke('MarkAsRead', conversationId)
    ).catch(() => {})
  }, 300)
}

onMounted(async () => {
  loading.value = true
  await startHub(conversationHub)

  conversationHub.on('ReceiveMessage', (msg) => {
    const m = normalizeMsg(msg)
    if (String(m.senderId) === String(currentUserId.value)) {
      const type = m.type || 'text'
      if (type === 'audio') {
        const pending = convStore.messages.find(x =>
          x.status === 'pending' &&
          String(x.senderId) === String(currentUserId.value) &&
          (x.type || 'text') === 'audio'
        )
        if (pending?.content?.startsWith?.('blob:')) {
          URL.revokeObjectURL(pending.content)
          pendingAudioBlobs.delete(pending.tempId)
        }
      }
      convStore.updatePendingMessage(m)
    } else {
      convStore.addMessage({ ...m, status: 'sent' })
      markAsReadDebounced()
    }
    nextTick(scrollToBottom)
  })

  conversationHub.on('UserTyping', () => { convStore.partnerTyping = true })
  conversationHub.on('UserStoppedTyping', () => { convStore.partnerTyping = false })

  conversationHub.on('MessageDeletedForMe', (messageId) => {
    convStore.removeMessage(messageId)
  })

  conversationHub.on('MessageDeletedForEveryone', (messageId) => {
    convStore.setMessageDeletedForEveryone(messageId)
  })

  conversationHub.on('ConversationDeletedForMe', () => {
    listStore.removeConversation(conversationId)
    convStore.clearConversation()
    router.replace('/conversations')
  })

  conversationHub.on('ConversationJoined', (data) => {
    const p = data.partner ?? data.Partner
    const msgs = data.messages ?? data.Messages ?? []
    convStore.setConversation(conversationId, p)
    listStore.updateConversation(conversationId, { unreadCount: 0 })
    if (msgs?.length) {
      msgs.forEach(m => convStore.addMessage({ ...normalizeMsg(m), status: 'sent' }))
      nextTick(scrollToBottom)
    }
  })

  conversationHub.on('PartnerReadUpTo', (payload) => {
    const readerId = payload?.readerId ?? payload?.ReaderId
    if (String(readerId) === String(currentUserId.value)) return
    const lastRead = payload?.lastReadAt ?? payload?.LastReadAt
    if (lastRead) convStore.setPartnerLastReadAt(lastRead)
  })

  conversationHub.on('MessagesRead', (payload) => {
    const ids = payload?.messageIds ?? payload?.MessageIds ?? []
    if (ids?.length) convStore.setMessagesRead(ids)
  })

  conversationHub.on('Error', (err) => {
    if (err?.includes('not found')) router.replace('/conversations')
  })

  conversationHub.on('ConversationListUpdated', (payload) => {
    const convId = payload?.conversationId ?? payload?.ConversationId
    const preview = payload?.lastMessagePreview ?? payload?.LastMessagePreview
    const at = payload?.lastMessageAt ?? payload?.LastMessageAt
    if (String(convId) === String(conversationId)) {
      listStore.updateConversation(convId, {
        lastMessagePreview: preview,
        lastMessageAt: at,
        LastMessagePreview: preview,
        LastMessageAt: at
      }, false)
    }
  })

  try {
    await conversationHub.invoke('JoinConversation', conversationId)
  } finally {
    loading.value = false
  }

  conversationHub.onreconnected(async () => {
    if (!mounted) return
    try {
      await ensureConnected(conversationHub)
      await conversationHub.invoke('JoinConversation', conversationId)
    } catch {}
  })

  visibilityHandler = () => {
    if (document.visibilityState === 'visible' && mounted) {
      ensureConnected(conversationHub).then(() =>
        conversationHub.invoke('MarkAsRead', conversationId)
      ).catch(() => {})
    }
  }
  document.addEventListener('visibilitychange', visibilityHandler)

  markAsReadInterval = setInterval(() => {
    if (!mounted || document.visibilityState !== 'visible') return
    ensureConnected(conversationHub).then(() =>
      conversationHub.invoke('MarkAsRead', conversationId)
    ).catch(() => {})
  }, 4000)
})

onUnmounted(() => {
  mounted = false
  if (markAsReadTimer) clearTimeout(markAsReadTimer)
  if (markAsReadInterval) clearInterval(markAsReadInterval)
  if (visibilityHandler) document.removeEventListener('visibilitychange', visibilityHandler)
  if (isRecording.value) cancelRecording()
  for (const entry of pendingAudioBlobs.values()) {
    if (entry?.blobUrl) URL.revokeObjectURL(entry.blobUrl)
  }
  pendingAudioBlobs.clear()
  convStore.clearConversation()
  conversationHub.off('ReceiveMessage')
  conversationHub.off('UserTyping')
  conversationHub.off('UserStoppedTyping')
  conversationHub.off('MessageDeletedForMe')
  conversationHub.off('MessageDeletedForEveryone')
  conversationHub.off('ConversationDeletedForMe')
  conversationHub.off('ConversationJoined')
  conversationHub.off('PartnerReadUpTo')
  conversationHub.off('MessagesRead')
  conversationHub.off('Error')
  conversationHub.off('ConversationListUpdated')
  ensureConnected(conversationHub).then(() =>
    conversationHub.invoke('LeaveConversation', conversationId)
  ).catch(() => {})
})

watch(messages, () => nextTick(scrollToBottom))

function scrollToBottom() {
  if (messagesEl.value) messagesEl.value.scrollTop = messagesEl.value.scrollHeight
}

let typingTimeout
const MSG_INPUT_MIN_HEIGHT = 48
const MSG_INPUT_MAX_HEIGHT = 120
function resizeMsgInput() {
  const el = msgInputRef.value
  if (!el) return
  el.style.height = '0'
  const h = Math.max(MSG_INPUT_MIN_HEIGHT, Math.min(el.scrollHeight, MSG_INPUT_MAX_HEIGHT))
  el.style.height = h + 'px'
}
async function handleInput() {
  resizeMsgInput()
  try {
    await ensureConnected(conversationHub)
    if (!typingTimeout) await conversationHub.invoke('StartTyping', conversationId)
  } catch {}
  clearTimeout(typingTimeout)
  typingTimeout = setTimeout(async () => {
    try {
      await ensureConnected(conversationHub)
      await conversationHub.invoke('StopTyping', conversationId)
    } catch {}
    typingTimeout = null
  }, 1500)
}

async function sendMessage() {
  const text = messageText.value.trim()
  if (!text) return
  messageText.value = ''
  nextTick(resizeMsgInput)
  if (typingTimeout) {
    clearTimeout(typingTimeout)
    typingTimeout = null
    await conversationHub.invoke('StopTyping', conversationId)
  }
  const tempId = `temp-${Date.now()}`
  convStore.addMessage({
    tempId,
    senderId: currentUserId.value,
    content: text,
    type: 'text',
    sentAt: new Date(),
    status: 'pending'
  })
  scrollToBottom()
  try {
    await ensureConnected(conversationHub)
    await conversationHub.invoke('SendMessage', conversationId, text, 'text')
  } catch {
    convStore.updateMessage(tempId, { status: 'failed' })
  }
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
    const tempId = `temp-${Date.now()}`
    convStore.addMessage({
      tempId,
      senderId: currentUserId.value,
      content: url,
      type: 'image',
      sentAt: new Date(),
      status: 'pending'
    })
    scrollToBottom()
    try {
      await ensureConnected(conversationHub)
      await conversationHub.invoke('SendMessage', conversationId, url, 'image')
    } catch {
      convStore.updateMessage(tempId, { status: 'failed' })
    }
  } finally {
    uploadingImage.value = false
  }
}

async function startVoiceRecording() {
  if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
    alert(t('conversationChat.voiceNotSupported'))
    return
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    currentStream = stream
    const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
      ? 'audio/webm;codecs=opus'
      : MediaRecorder.isTypeSupported('audio/webm')
        ? 'audio/webm'
        : 'audio/mp4'
    audioChunks = []
    mediaRecorder = new MediaRecorder(stream)
    mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) audioChunks.push(e.data)
    }
    mediaRecorder.onstop = () => {
      currentStream?.getTracks().forEach((t) => t.stop())
      currentStream = null
    }
    mediaRecorder.start(1000)
    isRecording.value = true
    recordingSeconds.value = 0
    recordingTimer = setInterval(() => {
      recordingSeconds.value++
    }, 1000)
  } catch (err) {
    alert(t('conversationChat.voicePermissionDenied'))
  }
}

function cancelRecording() {
  if (mediaRecorder && mediaRecorder.state !== 'inactive') {
    mediaRecorder.onstop = () => {}
    mediaRecorder.stop()
  }
  currentStream?.getTracks().forEach((t) => t.stop())
  currentStream = null
  isRecording.value = false
  mediaRecorder = null
  audioChunks = []
  if (recordingTimer) {
    clearInterval(recordingTimer)
    recordingTimer = null
  }
  recordingSeconds.value = 0
}

function formatRecordingTime(sec) {
  const m = Math.floor(sec / 60)
  const s = sec % 60
  return `${m}:${s.toString().padStart(2, '0')}`
}

function stopAndSendVoice() {
  if (!mediaRecorder || mediaRecorder.state === 'inactive') return
  const recorder = mediaRecorder
  mediaRecorder = null
  isRecording.value = false
  if (recordingTimer) {
    clearInterval(recordingTimer)
    recordingTimer = null
  }
  recordingSeconds.value = 0

  recorder.onstop = async () => {
    currentStream?.getTracks().forEach((t) => t.stop())
    currentStream = null
    const blob = new Blob(audioChunks, { type: recorder.mimeType || 'audio/webm' })
    audioChunks = []

    if (blob.size < 100) {
      alert(t('conversationChat.voiceRecordingTooShort'))
      return
    }

    const tempId = `temp-${Date.now()}`
    const blobUrl = URL.createObjectURL(blob)
    pendingAudioBlobs.set(tempId, { blob, blobUrl })

    convStore.addMessage({
      tempId,
      senderId: currentUserId.value,
      content: blobUrl,
      type: 'audio',
      sentAt: new Date(),
      status: 'pending'
    })
    scrollToBottom()
    uploadingVoice.value = true

    try {
      const formData = new FormData()
      const ext = blob.type.includes('webm') ? '.webm' : blob.type.includes('mp4') ? '.m4a' : '.ogg'
      formData.append('file', blob, `voice${ext}`)
      const token = localStorage.getItem('nexchat_token')
      const res = await fetch(`${API_BASE}/media/upload-audio`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: formData
      })
      if (!res.ok) throw new Error()
      const { url } = await res.json()
      try {
        await ensureConnected(conversationHub)
        await conversationHub.invoke('SendMessage', conversationId, url, 'audio')
      } catch {
        convStore.updateMessage(tempId, { status: 'failed' })
      }
    } catch {
      convStore.updateMessage(tempId, { status: 'failed' })
      alert(t('conversationChat.voiceUploadFailed'))
    } finally {
      uploadingVoice.value = false
    }
  }
  recorder.stop()
}

function toggleVoiceRecording() {
  if (isRecording.value) {
    stopAndSendVoice()
  } else {
    startVoiceRecording()
  }
}

async function deleteForMe(msg) {
  showMessageMenu.value = null
  try {
    await conversationHub.invoke('DeleteMessageForMe', conversationId, msg.id || msg.Id)
  } catch {}
}

async function deleteForEveryone(msg) {
  showMessageMenu.value = null
  try {
    await conversationHub.invoke('DeleteMessageForEveryone', conversationId, msg.id || msg.Id)
  } catch {}
}

async function retryMessage(msg) {
  if (msg.status !== 'failed') return
  const oldTempId = msg.tempId
  const newTempId = `temp-${Date.now()}-${Math.random().toString(36).slice(2)}`
  const isAudio = (msg.type || 'text') === 'audio'
  const entry = isAudio ? pendingAudioBlobs.get(oldTempId) : null
  if (isAudio && entry) {
    pendingAudioBlobs.delete(oldTempId)
    pendingAudioBlobs.set(newTempId, entry)
  }
  convStore.updateMessage(oldTempId, { tempId: newTempId, status: 'pending' })
  try {
    if (isAudio && entry?.blob) {
      const blob = entry.blob
      const formData = new FormData()
      const ext = blob.type.includes('webm') ? '.webm' : blob.type.includes('mp4') ? '.m4a' : '.ogg'
      formData.append('file', blob, `voice${ext}`)
      const token = localStorage.getItem('nexchat_token')
      const res = await fetch(`${API_BASE}/media/upload-audio`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: formData
      })
      if (!res.ok) throw new Error()
      const { url } = await res.json()
      await ensureConnected(conversationHub)
      await conversationHub.invoke('SendMessage', conversationId, url, 'audio')
      pendingAudioBlobs.delete(newTempId)
    } else {
      await ensureConnected(conversationHub)
      await conversationHub.invoke('SendMessage', conversationId, msg.content, msg.type || 'text')
    }
  } catch {
    convStore.updateMessage(newTempId, { status: 'failed' })
  }
}

function isMessageRead(msg) {
  if (msg.senderId !== currentUserId.value) return false
  if (msg.status === 'pending' || msg.status === 'failed') return false
  if (msg.isRead === true) return true
  const lastRead = convStore.partnerLastReadAt
  if (!lastRead) return false
  const sentAt = msg.sentAt ? new Date(msg.sentAt).getTime() : 0
  const readAt = new Date(lastRead).getTime()
  return sentAt > 0 && sentAt <= readAt
}

async function deleteConversation() {
  showDeleteConvConfirm.value = false
  try {
    await conversationHub.invoke('DeleteConversationForMe', conversationId)
    convStore.clearConversation()
    router.replace('/conversations')
  } catch {}
}

function openImage(url) {
  imageModalUrl.value = url
}

function closeImageModal() {
  imageModalUrl.value = null
}

function openShareModal() {
  showShareModal.value = true
  shareCodeCopied.value = false
}

function closeShareModal() {
  showShareModal.value = false
}

async function copyShareCode() {
  const code = auth.user?.uniqueCode
  if (!code) return
  try {
    await navigator.clipboard.writeText(code)
    shareCodeCopied.value = true
    setTimeout(() => { shareCodeCopied.value = false }, 2000)
  } catch {}
}

async function shareCodeInChat() {
  const code = auth.user?.uniqueCode
  if (!code) return
  const text = t('conversationChat.shareCodeMessage', { code })
  closeShareModal()
  const tempId = `temp-${Date.now()}`
  convStore.addMessage({
    tempId,
    senderId: currentUserId.value,
    content: text,
    type: 'text',
    sentAt: new Date(),
    status: 'pending'
  })
  scrollToBottom()
  try {
    await ensureConnected(conversationHub)
    await conversationHub.invoke('SendMessage', conversationId, text, 'text')
  } catch {
    convStore.updateMessage(tempId, { status: 'failed' })
  }
}

async function leaveChat() {
  convStore.clearConversation()
  router.replace('/conversations')
}
</script>

<template>
  <div class="conv-chat page">
    <LoaderOverlay :show="loading" :text="t('common.loading')" />

    <header class="chat-header glass-card">
      <button class="back-btn" @click="leaveChat" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <div class="partner-info">
        <div class="avatar-wrap">
          <div class="avatar avatar-sm" :style="partnerAvatarIsImage ? {} : { background: 'var(--primary)' }">
            <img v-if="partnerAvatarIsImage" :src="ensureAbsoluteUrl(partner?.avatar)" class="avatar-img" referrerpolicy="no-referrer" />
            <span v-else>{{ partnerLetter }}</span>
          </div>
        </div>
        <div class="partner-meta">
          <div class="partner-name">{{ partner?.name || '...' }}</div>
          <div class="typing-status">
            <span v-if="convStore.partnerTyping" class="typing-text">يكتب...</span>
          </div>
        </div>
      </div>
      <div class="header-actions">
        <button class="icon-btn" @click="showDeleteConvConfirm = true" :title="t('conversationChat.deleteConversation')">
          <Trash2 :size="20" />
        </button>
      </div>
    </header>

    <div class="messages-area" ref="messagesEl">
      <div v-if="showMessageMenu" class="msg-actions-backdrop" @click="showMessageMenu = null" />
      <div v-if="!messages.length" class="empty-chat text-muted text-sm">{{ t('conversationChat.empty') }}</div>

      <div
        v-for="msg in messages"
        :key="msg.tempId || msg.id"
        :class="['message-wrap', msg.senderId === currentUserId ? 'mine' : 'theirs']"
      >
        <div v-if="msg.type === 'image'" class="bubble image-bubble">
          <img v-if="!msg.deletedForEveryone" :src="ensureAbsoluteUrl(msg.content)" class="chat-image" @click="openImage(msg.content)" referrerpolicy="no-referrer" />
          <span v-else class="deleted-msg">{{ t('conversationChat.messageDeleted') }}</span>
        </div>
        <div v-else-if="msg.type === 'audio'" class="bubble audio-bubble">
          <template v-if="!msg.deletedForEveryone">
            <div class="audio-bubble-inner">
              <button
                type="button"
                class="audio-play-btn"
                :class="{ playing: playingAudioId === getMsgKey(msg) }"
                @click="toggleAudioPlay(msg, $event.currentTarget.closest('.audio-bubble-inner')?.querySelector('audio'))"
              >
                <Play v-if="playingAudioId !== getMsgKey(msg)" :size="18" stroke-width="2.5" />
                <Pause v-else :size="18" stroke-width="2.5" />
              </button>
              <div class="audio-content">
                <audio
                  :src="ensureAbsoluteUrl(msg.content)"
                  preload="metadata"
                  @play="onAudioPlay(msg, $event)"
                  @pause="onAudioPause(msg, $event)"
                  @timeupdate="onAudioTimeUpdate(msg, $event)"
                  @loadedmetadata="onAudioLoadedMetadata(msg, $event)"
                />
                <div class="audio-progress-track">
                  <div
                    class="audio-progress-fill"
                    :style="{ width: getAudioProgress(msg).duration > 0 ? `${Math.min(100, 100 * (getAudioProgress(msg).current || 0) / getAudioProgress(msg).duration)}%` : '0%' }"
                  />
                </div>
                <div class="audio-meta">
                  <span class="audio-duration">{{ formatAudioDuration(getAudioProgress(msg).current) }} / {{ formatAudioDuration(getAudioProgress(msg).duration) }}</span>
                </div>
              </div>
            </div>
          </template>
          <span v-else class="deleted-msg">{{ t('conversationChat.messageDeleted') }}</span>
        </div>
        <div v-else class="bubble">
          <span v-if="msg.deletedForEveryone" class="deleted-msg">{{ t('conversationChat.messageDeleted') }}</span>
          <span v-else class="msg-text" v-html="linkifyText(msg.content)" @click="handleMessageLinkClick"></span>
        </div>
        <div class="msg-meta">
          <span class="msg-time">{{ formatTime12(msg.sentAt, localeStore.locale) }}</span>
          <span v-if="msg.senderId === currentUserId && !msg.deletedForEveryone" class="msg-status">
            <Clock v-if="msg.status === 'pending'" :size="14" class="status-pending" />
            <CheckCheck v-else-if="isMessageRead(msg)" :size="14" class="status-read" />
            <Check v-else-if="msg.status === 'sent' || !msg.status" :size="14" class="status-sent" />
            <span v-else-if="msg.status === 'failed'" class="status-failed-wrap">
              <AlertCircle :size="14" class="status-failed" />
              <button class="retry-btn" @click.stop="retryMessage(msg)"><RotateCcw :size="12" /> {{ t('conversationChat.retry') }}</button>
            </span>
          </span>
          <button
            v-if="!msg.deletedForEveryone"
            class="msg-menu-btn"
            @click="showMessageMenu = showMessageMenu === (msg.id || msg.Id) ? null : (msg.id || msg.Id)"
          >
            <MoreVertical :size="14" />
          </button>
        </div>

        <Transition name="fade">
          <div v-if="showMessageMenu === (msg.id || msg.Id)" class="msg-actions-popup glass-card">
            <button class="msg-action-btn msg-action-me" @click="deleteForMe(msg)">
              <Trash2 :size="14" stroke-width="2" class="msg-action-icon" />
              <span class="msg-action-label">{{ t('conversationChat.deleteForMe') }}</span>
            </button>
            <button v-if="msg.senderId === currentUserId" class="msg-action-btn msg-action-everyone" @click="deleteForEveryone(msg)">
              <UserX :size="14" stroke-width="2" class="msg-action-icon" />
              <span class="msg-action-label">{{ t('conversationChat.deleteForEveryone') }}</span>
            </button>
          </div>
        </Transition>
      </div>

      <div v-if="convStore.partnerTyping" class="message-wrap theirs">
        <div class="bubble typing-bubble">
          <span class="typing-dots"><span></span><span></span><span></span></span>
        </div>
      </div>
    </div>

    <div class="input-area">
      <button v-if="!isRecording && !uploadingVoice" class="share-code-bar" @click="openShareModal">
        <Share2 :size="18" stroke-width="2" />
        <span>{{ t('conversationChat.shareYourCode') }}</span>
      </button>

      <!-- شريط التسجيل الصوتي -->
      <Transition name="slide-up">
        <div v-if="isRecording" class="recording-bar">
          <div class="recording-indicator">
            <span class="recording-dot" />
            <div class="recording-wave">
              <span v-for="i in 5" :key="i" class="rec-wave-bar" :style="{ animationDelay: `${(i - 1) * 0.12}s` }" />
            </div>
          </div>
          <div class="recording-timer">{{ formatRecordingTime(recordingSeconds) }}</div>
          <div class="recording-actions">
            <button type="button" class="recording-cancel-btn" @click="cancelRecording">
              <X :size="18" stroke-width="2.5" />
              <span>{{ t('common.cancel') }}</span>
            </button>
            <button type="button" class="recording-send-btn" @click="stopAndSendVoice">
              <Send :size="18" stroke-width="2.5" />
              <span>{{ t('conversationChat.sendVoice') }}</span>
            </button>
          </div>
        </div>
      </Transition>

      <div v-if="uploadingVoice" class="uploading-voice-bar">
        <div class="uploading-spinner" />
        <span>{{ t('conversationChat.uploadingVoice') }}</span>
      </div>

      <div v-if="!isRecording" class="message-input-row">
        <div class="input-actions-wrap">
          <button
            class="input-action-btn"
            @click="showInputActionsMenu = !showInputActionsMenu"
            :disabled="uploadingVoice || uploadingImage"
            :title="t('conversationChat.attachOrVoice')"
          >
            <MoreVertical :size="20" />
          </button>
          <div v-if="showInputActionsMenu" class="input-actions-backdrop" @click="showInputActionsMenu = false" />
          <Transition name="fade">
            <div v-if="showInputActionsMenu" class="input-actions-menu glass-card" @click.stop>
              <button class="input-action-menu-item" @click="showInputActionsMenu = false; imageInput?.click()">
                <Image :size="18" />
                <span>{{ t('conversationChat.attachImage') }}</span>
              </button>
              <button class="input-action-menu-item" @click="showInputActionsMenu = false; toggleVoiceRecording()">
                <Mic :size="18" />
                <span>{{ t('conversationChat.voiceMessage') }}</span>
              </button>
            </div>
          </Transition>
        </div>
        <input ref="imageInput" type="file" accept="image/*" style="display:none" @change="handleImageUpload" />
        <textarea
          ref="msgInputRef"
          v-model="messageText"
          class="msg-input"
          :placeholder="t('conversationChat.messagePlaceholder')"
          rows="1"
          @input="handleInput"
          @keydown.enter.exact.prevent="sendMessage"
          maxlength="5000"
        />
        <button class="send-btn" @click="sendMessage" :disabled="!messageText.trim()">
          <Send :size="20" />
        </button>
      </div>
    </div>

    <Teleport to="body">
      <div v-if="showDeleteConvConfirm" class="modal-overlay" @click.self="showDeleteConvConfirm = false">
        <div class="confirm-modal glass-card">
          <p>{{ t('conversationChat.deleteConversation') }}؟</p>
          <div class="modal-actions">
            <button class="btn-outline" @click="showDeleteConvConfirm = false">{{ t('common.cancel') }}</button>
            <button class="btn-danger" @click="deleteConversation">{{ t('common.delete') }}</button>
          </div>
        </div>
      </div>
    </Teleport>

    <Teleport to="body">
      <Transition name="modal">
        <div v-if="showShareModal" class="share-overlay" @click.self="closeShareModal">
          <div class="share-modal glass-card">
            <div class="share-modal-header">
              <Share2 :size="20" stroke-width="2" class="share-modal-icon" />
              <h3 class="share-modal-title">{{ t('conversationChat.shareCodeTitle') }}</h3>
            </div>
            <div class="share-code-display">{{ auth.user?.uniqueCode }}</div>
            <div class="share-modal-actions">
              <button class="share-btn primary-btn" @click="shareCodeInChat">
                <Send :size="18" stroke-width="2" />
                <span>{{ t('conversationChat.sendInChat') }}</span>
              </button>
              <button class="share-btn copy-btn" @click="copyShareCode">
                <Copy v-if="!shareCodeCopied" :size="18" stroke-width="2" />
                <Check v-else :size="18" stroke-width="2" />
                <span>{{ shareCodeCopied ? t('conversationChat.copied') : t('conversationChat.copy') }}</span>
              </button>
            </div>
            <button class="share-close-btn" @click="closeShareModal">{{ t('common.cancel') }}</button>
          </div>
        </div>
      </Transition>
    </Teleport>

    <Teleport to="body">
      <div v-if="imageModalUrl" class="image-modal-overlay" @click.self="closeImageModal">
        <button class="image-modal-close" @click="closeImageModal"><X :size="24" /></button>
        <img :src="ensureAbsoluteUrl(imageModalUrl)" class="image-modal-img" alt="" referrerpolicy="no-referrer" />
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.conv-chat {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
  font-family: 'Cairo', sans-serif;
}

.chat-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: calc(8px + var(--safe-top)) var(--spacing) 12px;
  flex-shrink: 0;
  border-radius: 0 0 var(--radius) var(--radius);
  border-top: none;
}

.back-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  min-width: 40px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.back-btn:active { background: var(--bg-card-hover); }

.partner-info {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
  flex: 1;
  margin-inline-start: 12px;
  margin-inline-end: 12px;
}

.avatar-wrap { flex-shrink: 0; }

.avatar-img { width: 100%; height: 100%; object-fit: cover; border-radius: 50%; }

.partner-meta { min-width: 0; flex: 1; }

.partner-name {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.typing-status {
  margin-top: 2px;
  font-size: 12px;
  color: var(--text-muted);
  min-height: 16px;
}

.typing-text { font-family: 'Cairo', sans-serif; }

.header-actions { display: flex; gap: 8px; }

.chat-header .icon-btn {
  align-items: center;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-primary);
  cursor: pointer;
  display: flex;
  height: var(--touch-min);
  justify-content: center;
  min-width: var(--touch-min);
  padding: 0;
  -webkit-tap-highlight-color: transparent;
}
.chat-header .icon-btn:active { background: var(--bg-card-hover); }
.chat-header .icon-btn.danger { background: rgba(255,101,132,0.15); color: var(--danger); border-color: rgba(255,101,132,0.25); }

.messages-area {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 16px 16px 8px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  -webkit-overflow-scrolling: touch;
}

.empty-chat {
  text-align: center;
  margin: auto;
  font-family: 'Cairo', sans-serif;
}

.message-wrap {
  display: flex;
  flex-direction: column;
  max-width: 80%;
  position: relative;
}
.message-wrap.mine { align-self: flex-end; align-items: flex-end; }
.message-wrap.theirs { align-self: flex-start; align-items: flex-start; }

.bubble {
  background: var(--msg-theirs-bg);
  color: var(--msg-theirs-color);
  border-radius: 16px;
  padding: 10px 14px;
  font-size: 15px;
  word-break: break-word;
  line-height: 1.5;
  font-family: 'Cairo', sans-serif;
}
.mine .bubble {
  background: var(--msg-mine-bg);
  color: var(--msg-mine-color);
  border-bottom-right-radius: 4px;
}
.theirs .bubble { border-bottom-left-radius: 4px; }

.deleted-msg { font-style: italic; opacity: 0.8; }
.msg-text :deep(.msg-link) {
  color: #64B5F6;
  text-decoration: underline;
  cursor: pointer;
  word-break: break-all;
}
.mine .msg-text :deep(.msg-link) {
  color: #90CAF9;
}
.msg-text :deep(.msg-link:active) { opacity: 0.8; }

.msg-meta {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 4px;
}
.msg-time { font-size: 11px; color: var(--text-muted); font-family: 'Cairo', sans-serif; }
.msg-status { display: inline-flex; align-items: center; }
.status-pending { color: var(--text-muted); opacity: 0.8; }
.status-sent { color: var(--primary); }
.status-read { color: var(--primary); }
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

.msg-menu-btn {
  background: none;
  border: none;
  color: var(--text-muted);
  padding: 2px;
  cursor: pointer;
}

.msg-actions-backdrop {
  position: fixed;
  inset: 0;
  z-index: 40;
}

.msg-actions-popup {
  position: absolute;
  bottom: calc(100% + 4px);
  right: 0;
  display: flex;
  flex-direction: column;
  min-width: 150px;
  padding: 4px 0;
  border-radius: 8px;
  border: 1px solid var(--border);
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.22);
  z-index: 50;
  direction: rtl;
}

.msg-action-btn {
  display: grid;
  grid-template-columns: auto 1fr;
  align-items: center;
  gap: 10px;
  width: 100%;
  font-size: 13px;
  font-weight: 500;
  padding: 8px 12px;
  border: none;
  background: transparent;
  cursor: pointer;
  font-family: 'Cairo', sans-serif;
  transition: background 0.15s;
  -webkit-tap-highlight-color: transparent;
  text-align: right;
}
.msg-action-btn + .msg-action-btn {
  border-top: 1px solid var(--border);
}
.msg-action-label {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.msg-action-icon {
  flex-shrink: 0;
  width: 14px;
  height: 14px;
  opacity: 0.9;
}

.msg-action-me {
  background: transparent;
  color: var(--text-secondary);
}
.msg-action-me:hover,
.msg-action-me:active {
  background: var(--bg-card-hover);
  color: var(--text-primary);
}

.msg-action-everyone {
  background: transparent;
  color: var(--danger);
}
.msg-action-everyone:hover,
.msg-action-everyone:active {
  background: rgba(255, 101, 132, 0.15);
  color: var(--danger);
}

.input-area {
  padding: 8px var(--spacing) calc(var(--spacing) + var(--safe-bottom));
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-height: 0;
}

.share-code-bar {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
  padding: 10px 16px;
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.12) 0%, rgba(108, 99, 255, 0.06) 100%);
  border: 1px solid rgba(108, 99, 255, 0.25);
  border-radius: 12px;
  color: var(--primary);
  font-size: 14px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: all 0.2s;
}
.share-code-bar:active { background: rgba(108, 99, 255, 0.2); }

.message-input-row {
  display: flex;
  gap: 10px;
  align-items: center;
  min-height: 56px;
}
/* شريط التسجيل الصوتي */
.recording-bar {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 12px 14px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  min-height: 56px;
  flex-shrink: 0;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.08);
}
@media (max-width: 400px) {
  .recording-bar {
    gap: 10px;
    padding: 10px 12px;
    min-height: 52px;
  }
  .recording-cancel-btn span,
  .recording-send-btn span { display: none; }
  .recording-cancel-btn,
  .recording-send-btn { padding: 8px 12px; }
  .recording-timer { font-size: 15px; min-width: 40px; }
}
.recording-indicator {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-shrink: 0;
}
.recording-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: #e53935;
  animation: recording-pulse-dot 1.2s ease-in-out infinite;
}
@keyframes recording-pulse-dot {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.6; transform: scale(1.15); }
}
.recording-wave {
  display: flex;
  align-items: center;
  gap: 3px;
  height: 28px;
}
.rec-wave-bar {
  width: 4px;
  border-radius: 2px;
  background: var(--primary);
  opacity: 0.7;
  animation: rec-wave-bounce 0.5s ease-in-out infinite alternate;
}
.rec-wave-bar:nth-child(1) { height: 10px; }
.rec-wave-bar:nth-child(2) { height: 18px; }
.rec-wave-bar:nth-child(3) { height: 24px; }
.rec-wave-bar:nth-child(4) { height: 16px; }
.rec-wave-bar:nth-child(5) { height: 12px; }
@keyframes rec-wave-bounce {
  from { transform: scaleY(0.5); opacity: 0.5; }
  to { transform: scaleY(1); opacity: 0.9; }
}
.recording-timer {
  font-variant-numeric: tabular-nums;
  font-size: 17px;
  font-weight: 600;
  color: var(--text-primary);
  min-width: 44px;
  letter-spacing: 0.02em;
}
.recording-actions {
  display: flex;
  gap: 10px;
  margin-right: 0;
  margin-left: auto;
}
.recording-cancel-btn {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 16px;
  background: transparent;
  border: 1px solid var(--border);
  border-radius: 12px;
  color: var(--text-secondary);
  font-size: 14px;
  font-weight: 500;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.2s, color 0.2s, border-color 0.2s;
}
.recording-cancel-btn:hover {
  background: rgba(255, 255, 255, 0.04);
  color: var(--text-primary);
}
.recording-cancel-btn:active {
  background: rgba(255, 255, 255, 0.08);
}
.recording-send-btn {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 20px;
  background: var(--primary);
  border: none;
  border-radius: 12px;
  color: #fff;
  font-size: 14px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.15s, opacity 0.2s, box-shadow 0.2s;
  box-shadow: 0 2px 8px rgba(108, 99, 255, 0.3);
}
.recording-send-btn:hover {
  box-shadow: 0 4px 12px rgba(108, 99, 255, 0.4);
}
.recording-send-btn:active {
  transform: scale(0.97);
  opacity: 0.95;
}

.uploading-voice-bar {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 12px 16px;
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.12) 0%, rgba(108, 99, 255, 0.06) 100%);
  border: 1px solid rgba(108, 99, 255, 0.25);
  border-radius: 12px;
  color: var(--primary);
  font-size: 14px;
  font-weight: 600;
}
.uploading-spinner {
  width: 20px;
  height: 20px;
  border: 2px solid rgba(108, 99, 255, 0.3);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin {
  to { transform: rotate(360deg); }
}

.slide-up-enter-active,
.slide-up-leave-active {
  transition: all 0.25s ease;
}
.slide-up-enter-from,
.slide-up-leave-to {
  opacity: 0;
  transform: translateY(12px);
}

.fade-enter-active, .fade-leave-active { transition: opacity 0.2s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }

.msg-input {
  flex: 1;
  min-width: 0;
  min-height: 52px;
  max-height: 120px;
  padding: 14px 16px;
  border-radius: 24px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  color: var(--text-primary);
  font-size: 16px;
  font-family: 'Cairo', sans-serif;
  outline: none;
  resize: none;
  overflow-y: auto;
  line-height: 1.5;
  box-sizing: border-box;
}
.msg-input::placeholder { color: var(--text-muted); }
.msg-input:focus { border-color: var(--primary); }

.send-btn {
  background: linear-gradient(145deg, #7C75FF 0%, var(--primary) 50%, #5B54E8 100%);
  border: none;
  border-radius: 50%;
  color: white;
  width: 48px;
  height: 48px;
  min-width: 48px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  box-shadow: 0 4px 12px rgba(108, 99, 255, 0.35);
  -webkit-tap-highlight-color: transparent;
}
.send-btn:not(:disabled):active { transform: scale(0.95); opacity: 0.95; }
.send-btn:disabled { opacity: 0.4; cursor: not-allowed; }

.input-actions-wrap {
  position: relative;
  flex-shrink: 0;
}
.input-action-btn {
  width: 48px;
  height: 48px;
  min-width: 48px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 12px;
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  -webkit-tap-highlight-color: transparent;
}
.input-action-btn:active { background: var(--bg-card-hover); }

.input-actions-backdrop {
  position: fixed;
  inset: 0;
  z-index: 100;
}
.input-actions-menu {
  position: absolute;
  bottom: calc(100% + 8px);
  left: 0;
  right: auto;
  min-width: 180px;
  padding: 6px;
  z-index: 101;
  border-radius: 12px;
  border: 1px solid var(--border);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.25);
  direction: rtl;
}
[dir="rtl"] .input-actions-menu {
  left: auto;
  right: 0;
}
.input-action-menu-item {
  display: flex;
  align-items: center;
  flex-direction: row;
  gap: 12px;
  width: 100%;
  padding: 12px 14px;
  border: none;
  background: transparent;
  color: var(--text-primary);
  font-size: 14px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  border-radius: 8px;
  text-align: right;
  -webkit-tap-highlight-color: transparent;
}
.input-action-menu-item svg {
  flex-shrink: 0;
  width: 18px;
  height: 18px;
}
.input-action-menu-item:hover,
.input-action-menu-item:active {
  background: var(--bg-card-hover);
}

.image-bubble { padding: 4px !important; overflow: hidden; }

.audio-bubble {
  padding: 0;
  min-width: 200px;
  max-width: 260px;
  overflow: hidden;
  border-radius: 16px;
}
.mine .audio-bubble { border-bottom-right-radius: 4px; }
.theirs .audio-bubble { border-bottom-left-radius: 4px; }
.audio-bubble-inner {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 12px 16px;
}
.audio-play-btn {
  flex-shrink: 0;
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.15);
  border: none;
  color: inherit;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.2s, transform 0.15s, box-shadow 0.2s;
  -webkit-tap-highlight-color: transparent;
}
.mine .audio-play-btn {
  background: rgba(255, 255, 255, 0.2);
}
.theirs .audio-play-btn {
  background: rgba(0, 0, 0, 0.12);
}
.audio-play-btn:hover {
  background: rgba(0, 0, 0, 0.22);
}
.mine .audio-play-btn:hover {
  background: rgba(255, 255, 255, 0.3);
}
.audio-play-btn:active { transform: scale(0.96); }
.audio-play-btn.playing {
  background: var(--primary);
  color: #fff;
  box-shadow: 0 2px 8px rgba(108, 99, 255, 0.35);
}
.audio-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.audio-content audio {
  position: absolute;
  width: 0;
  height: 0;
  opacity: 0;
  pointer-events: none;
}
.audio-progress-track {
  height: 4px;
  background: rgba(0, 0, 0, 0.12);
  border-radius: 2px;
  overflow: hidden;
}
.mine .audio-progress-track {
  background: rgba(255, 255, 255, 0.2);
}
.audio-progress-fill {
  height: 100%;
  background: var(--primary);
  border-radius: 2px;
  transition: width 0.1s linear;
}
.audio-meta {
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  color: inherit;
  opacity: 0.75;
}
.input-action-btn.recording {
  background: rgba(255, 80, 80, 0.25);
  color: #ff5050;
  animation: recording-pulse 1s ease-in-out infinite;
}
@keyframes recording-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.7; }
}

.chat-image {
  max-width: 220px;
  max-height: 280px;
  border-radius: 12px;
  cursor: pointer;
  object-fit: cover;
  display: block;
}

.typing-bubble { padding: 12px 16px; }

.typing-dots {
  display: flex;
  gap: 4px;
  align-items: center;
}
.typing-dots span {
  width: 6px;
  height: 6px;
  background: var(--text-muted);
  border-radius: 50%;
  animation: bounce 1.2s ease-in-out infinite;
}
.typing-dots span:nth-child(2) { animation-delay: 0.2s; }
.typing-dots span:nth-child(3) { animation-delay: 0.4s; }
@keyframes bounce { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-4px); } }

/* Share Code Modal - compact for mobile */
.share-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1500;
  padding: 16px;
  backdrop-filter: blur(6px);
}
.share-modal {
  width: 100%;
  max-width: 300px;
  padding: 16px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  text-align: center;
}
.share-modal-header {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--primary);
}
.share-modal-icon { flex-shrink: 0; }
.share-modal-title {
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
  margin: 0;
  font-family: 'Cairo', sans-serif;
}
.share-code-display {
  font-size: 20px;
  font-weight: 700;
  letter-spacing: 2px;
  color: var(--primary);
  padding: 10px 18px;
  background: rgba(108, 99, 255, 0.1);
  border-radius: 10px;
  border: 1px solid rgba(108, 99, 255, 0.25);
  font-family: 'Cairo', sans-serif;
}
.share-modal-actions {
  display: flex;
  flex-direction: row;
  gap: 8px;
  width: 100%;
}
.share-btn {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  min-height: 40px;
  padding: 0 12px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: all 0.2s;
  white-space: nowrap;
}
.share-btn.copy-btn {
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  color: var(--text-primary);
}
.share-btn.copy-btn:active { background: var(--bg-card-hover); }
.share-btn.primary-btn {
  background: linear-gradient(145deg, #7C75FF 0%, var(--primary) 50%, #5B54E8 100%);
  border: none;
  color: white;
  box-shadow: 0 4px 12px rgba(108, 99, 255, 0.35);
}
.share-btn.primary-btn:active { opacity: 0.9; transform: scale(0.98); }
.share-close-btn {
  background: none;
  border: none;
  color: var(--text-muted);
  font-size: 13px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  padding: 4px 12px;
  -webkit-tap-highlight-color: transparent;
}
.share-close-btn:active { opacity: 0.8; }

.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: var(--spacing);
  backdrop-filter: blur(4px);
}

.confirm-modal {
  padding: 24px;
  max-width: 320px;
  width: 100%;
}
.confirm-modal p {
  margin: 0 0 20px;
  font-family: 'Cairo', sans-serif;
  font-size: 15px;
}

.modal-actions { display: flex; gap: 12px; }

.btn-outline {
  flex: 1;
  padding: 12px;
  background: transparent;
  border: 1px solid var(--border);
  border-radius: 12px;
  color: var(--text-primary);
  cursor: pointer;
  font-family: 'Cairo', sans-serif;
}

.btn-danger {
  flex: 1;
  padding: 12px;
  background: var(--danger);
  border: none;
  border-radius: 12px;
  color: white;
  cursor: pointer;
  font-family: 'Cairo', sans-serif;
  font-weight: 600;
}

.image-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 1000;
  background: rgba(0,0,0,0.92);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
}
.image-modal-close {
  position: absolute;
  top: 12px;
  right: 12px;
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: rgba(255,255,255,0.15);
  color: #fff;
  border: none;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
}
.image-modal-img {
  max-width: 100%;
  max-height: 100%;
  object-fit: contain;
  border-radius: 8px;
}

.modal-enter-active, .modal-leave-active { transition: opacity 0.25s; }
.modal-enter-from, .modal-leave-to { opacity: 0; }
</style>
