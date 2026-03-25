<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronRight, Image, Send, MoreVertical, Trash2, UserX, X, Clock, Check, CheckCheck, AlertCircle, RotateCcw, Mic, Play, Pause, Reply, Forward, Video, Phone, Loader2, SmilePlus } from 'lucide-vue-next'
import { useAuthStore } from '../stores/auth'
import { useConversationStore } from '../stores/conversation'
import { useConversationsListStore } from '../stores/conversationsList'
import { useNetworkStore } from '../stores/network'
import { conversationHub, startHub, ensureConnected } from '../services/signalr'
import api from '../services/api'
import { loadMessagesFromCache, saveMessagesForConversation, clearMessagesForConversation } from '../services/cache'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import CachedAvatar from '../components/CachedAvatar.vue'
import { formatTime12 } from '../utils/formatTime'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../stores/locale'
import { useActiveCallStore } from '../stores/activeCall'
import ActiveCallBar from '../components/ActiveCallBar.vue'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const convStore = useConversationStore()
const listStore = useConversationsListStore()
const network = useNetworkStore()
const localeStore = useLocaleStore()
const { t } = useI18n()

let saveMessagesToCacheTimer = null
function debouncedSaveMessages(convId) {
  if (saveMessagesToCacheTimer) clearTimeout(saveMessagesToCacheTimer)
  saveMessagesToCacheTimer = setTimeout(() => {
    saveMessagesToCacheTimer = null
    saveMessagesForConversation(convId, convStore.messages)
  }, 400)
}

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
const showMessageMenuMsg = ref(null)
const msgMenuPosition = ref({})
const replyingTo = ref(null)
const showDeleteConvConfirm = ref(false)
const showInputActionsMenu = ref(false)
const playingAudioId = ref(null)
const audioProgress = ref({})
const audioDurations = ref({})
const highlightedMessageId = ref(null)
const groupSenders = ref({})
const showReactionPickerMsg = ref(null)
const reactionPickerPosition = ref({})
const REACTION_EMOJIS = ['❤️', '👍', '😂', '😮', '😢', '🙏']

const showVideoConfirm = ref(false)
const showVoiceConfirm = ref(false)
const callingOut = ref(false)
const pendingOutgoingVoiceOnly = ref(false)
const callDeclined = ref(false)

function getMsgKey(msg) {
  return msg.tempId || msg.id || msg.Id
}

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

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

function replyPreviewText(content) {
  if (!content || typeof content !== 'string') return ''
  const lower = content.toLowerCase()
  if (/\.(webm|m4a|ogg|opus|mp3|wav)(\?|$)/i.test(lower) || (lower.includes('/uploads/') && (lower.includes('webm') || lower.includes('m4a') || lower.includes('ogg')))) return t('conversationChat.voiceMessage')
  if (/\.(jpg|jpeg|png|gif|webp)(\?|$)/i.test(lower) || (lower.includes('/uploads/') && (lower.includes('jpg') || lower.includes('png') || lower.includes('webp')))) return t('conversationChat.replyPreviewImage')
  return content
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

function getMyReaction(msg) {
  if (!msg?.reactions?.length || !currentUserId.value) return msg?.myReaction ?? null
  const id = String(currentUserId.value)
  for (const r of msg.reactions) {
    const userIds = r.userIds ?? r.UserIds ?? []
    if (userIds.some(uid => String(uid) === id)) return r.emoji ?? r.Emoji ?? null
  }
  return null
}

function messageReactionsList(msg) {
  const list = msg?.reactions ?? []
  return Array.isArray(list) ? list : []
}
const messages = computed(() => convStore.messages)
const partnerLetter = computed(() => partner.value?.name?.[0]?.toUpperCase() || '?')
const partnerColor = computed(() => {
  if (!partner.value?.name) return 'var(--primary)'
  const colors = ['#6C63FF', '#FF6584', '#00D4FF', '#FF8C42']
  return colors[partner.value.name.charCodeAt(0) % colors.length]
})
const partnerAvatarIsImage = computed(() =>
  partner.value?.avatar && (partner.value.avatar.startsWith('http') || partner.value.avatar.startsWith('/'))
)
const partnerIsOnline = computed(() => partner.value?.isOnline ?? partner.value?.IsOnline ?? false)

const activeCall = useActiveCallStore()
const showEmbeddedActiveCallBar = computed(
  () =>
    activeCall.showFloatingBar &&
    activeCall.isConversation &&
    String(activeCall.sessionId) === String(conversationId)
)

function normalizeMsg(msg) {
  return {
    id: msg.id ?? msg.Id,
    senderId: msg.senderId ?? msg.SenderId,
    content: msg.content ?? msg.Content,
    type: msg.type ?? msg.Type ?? 'text',
    sentAt: msg.sentAt ?? msg.SentAt,
    deletedForEveryone: msg.deletedForEveryone ?? msg.DeletedForEveryone,
    isRead: msg.isRead ?? msg.IsRead,
    replyToMessageId: msg.replyToMessageId ?? msg.ReplyToMessageId,
    replyToContent: msg.replyToContent ?? msg.ReplyToContent,
    replyToSenderName: msg.replyToSenderName ?? msg.ReplyToSenderName,
    senderName: msg.senderName ?? msg.SenderName,
    senderAvatar: msg.senderAvatar ?? msg.SenderAvatar,
    reactions: msg.reactions ?? msg.Reactions ?? [],
    myReaction: msg.myReaction ?? msg.MyReaction ?? null
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
  const partnerFromList = listStore.list.find(
    (c) => String(c.id ?? c.Id) === String(conversationId)
  )
  let partnerInfo = partnerFromList
    ? {
        id: partnerFromList.partnerId ?? partnerFromList.PartnerId,
        name: partnerFromList.partnerName ?? partnerFromList.PartnerName,
        avatar: partnerFromList.partnerAvatar ?? partnerFromList.PartnerAvatar
      }
    : null
  let isGroupConv = partnerFromList ? (partnerFromList.isGroup ?? partnerFromList.IsGroup ?? false) : false
  if (!partnerFromList && network.isOnline) {
    try {
      const { data } = await api.get(`/conversations/${conversationId}`, { skipGlobalLoader: true })
      if (data?.type === 'group') {
        isGroupConv = true
        partnerInfo = {
          id: conversationId,
          name: data.groupName ?? 'مجموعة',
          avatar: data.groupImageUrl ?? null
        }
      } else if (data?.type === 'private' && data?.partnerId) {
        partnerInfo = {
          id: data.partnerId,
          name: data.partnerName ?? '',
          avatar: data.partnerAvatar ?? null
        }
      }
    } catch (_) {}
  }
  convStore.setConversation(conversationId, partnerInfo, { isGroup: isGroupConv })
  if (isGroupConv && network.isOnline) await fetchGroupSenders()

  const cachedMessages = await loadMessagesFromCache(conversationId)
  if (cachedMessages?.length) {
    convStore.setMessages(cachedMessages)
    nextTick(scrollToBottom)
  }
  loading.value = false
  if (!network.isOnline) return

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
      const updated = convStore.updatePendingMessage(m)
      if (!updated) convStore.addMessage({ ...m, status: 'sent' })
    } else {
      convStore.addMessage({ ...m, status: 'sent' })
      markAsReadDebounced()
    }
    nextTick(scrollToBottom)
    debouncedSaveMessages(conversationId)
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
    clearMessagesForConversation(conversationId)
    router.replace('/conversations')
  })

  conversationHub.on('ConversationJoined', (data) => {
    const p = data.partner ?? data.Partner
    const isGroupFromHub = data.type === 1 || data.Type === 1 || data.type === 'Group' || data.Type === 'Group' || (data.groupName ?? data.GroupName) != null
    const msgs = data.messages ?? data.Messages ?? []
    const localPending = convStore.messages.filter((m) => m.tempId)
    let partnerInfo = p
    if (isGroupFromHub) {
      partnerInfo = {
        id: conversationId,
        name: data.groupName ?? data.GroupName ?? 'مجموعة',
        avatar: data.groupImageUrl ?? data.GroupImageUrl ?? null
      }
    }
    convStore.setConversation(conversationId, partnerInfo, { isGroup: isGroupFromHub })
    listStore.updateConversation(conversationId, {
      unreadCount: 0,
      partnerAvatar: partnerInfo?.avatar ?? partnerInfo?.Avatar,
      PartnerAvatar: partnerInfo?.avatar ?? partnerInfo?.Avatar
    })
    const serverNormalized = (msgs || []).map((m) => ({ ...normalizeMsg(m), status: 'sent' }))
    const serverIds = new Set(serverNormalized.map((m) => String(m.id ?? m.Id)))
    const toKeep = localPending.filter((m) => !serverIds.has(String(m.id ?? m.Id)))
    const merged = [...serverNormalized, ...toKeep].sort(
      (a, b) => new Date(a.sentAt || 0).getTime() - new Date(b.sentAt || 0).getTime()
    )
    convStore.setMessages(merged)
    nextTick(scrollToBottom)
    loading.value = false
    saveMessagesForConversation(conversationId, merged)
    if (isGroupFromHub) fetchGroupSenders()
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

  conversationHub.on('ReactionUpdated', (payload) => {
    const mid = payload?.messageId ?? payload?.MessageId
    const reactions = payload?.reactions ?? payload?.Reactions ?? []
    if (mid) {
      convStore.updateMessageReactions(mid, reactions)
      debouncedSaveMessages(conversationId)
    }
  })

  conversationHub.on('VideoCallDeclined', (cidStr) => {
    if (cidStr != null && cidStr !== '' && String(cidStr) !== String(conversationId)) return
    callingOut.value = false
    callDeclined.value = true
    setTimeout(() => { callDeclined.value = false }, 3000)
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
  if (saveMessagesToCacheTimer) clearTimeout(saveMessagesToCacheTimer)
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
  conversationHub.off('ReactionUpdated')
  conversationHub.off('VideoCallDeclined')
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
  const reply = replyingTo.value
  const replyId = reply?.id
  messageText.value = ''
  replyingTo.value = null
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
    status: 'pending',
    replyToMessageId: replyId,
    replyToContent: reply?.content,
    replyToSenderName: reply?.senderName
  })
  scrollToBottom()
  try {
    await ensureConnected(conversationHub)
    await conversationHub.invoke('SendMessage', conversationId, text, 'text', replyId || undefined)
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
  uploadingImage.value = true
  const tempId = `temp-${Date.now()}`
  try {
    await ensureConnected(conversationHub, 25000)
    const { data } = await api.post('/media/upload', formData, { timeout: 60000 })
    const url = data?.url
    if (!url || typeof url !== 'string') throw new Error('Invalid upload response')
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
      await ensureConnected(conversationHub, 25000)
      await conversationHub.invoke('SendMessage', conversationId, url, 'image', null)
    } catch (err) {
      convStore.updateMessage(tempId, { status: 'failed' })
      console.warn('SendMessage failed after image upload:', err?.message ?? err)
    }
  } catch (err) {
    alert(err?.response?.data?.message || err?.userMessage || t('conversationChat.imageUploadFailed'))
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
      await ensureConnected(conversationHub, 25000)
      const formData = new FormData()
      const ext = blob.type.includes('webm') ? '.webm' : blob.type.includes('mp4') ? '.m4a' : '.ogg'
      formData.append('file', blob, `voice${ext}`)
      const { data } = await api.post('/media/upload-audio', formData, { timeout: 60000 })
      const url = data?.url ?? data?.data?.url
      if (!url || typeof url !== 'string') throw new Error('Invalid upload response')
      convStore.updateMessage(tempId, { content: url })
      pendingAudioBlobs.delete(tempId)
      try { URL.revokeObjectURL(blobUrl) } catch {}
      let sent = false
      for (let attempt = 0; attempt < 2 && !sent; attempt++) {
        try {
          await ensureConnected(conversationHub, 25000)
          await conversationHub.invoke('SendMessage', conversationId, url, 'audio', null)
          sent = true
        } catch (err) {
          if (attempt === 1) {
            convStore.updateMessage(tempId, { status: 'failed' })
            const msg = err?.message ?? err?.errorMessage ?? (typeof err === 'string' ? err : JSON.stringify(err))
            console.warn('SendMessage failed after upload:', msg, err)
          }
        }
      }
    } catch (err) {
      convStore.updateMessage(tempId, { status: 'failed' })
      alert(err?.response?.data?.message || err?.userMessage || t('conversationChat.voiceUploadFailed'))
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

function replyToMessage(msg) {
  showMessageMenu.value = null
  showMessageMenuMsg.value = null
  const isMine = String(msg.senderId) === String(currentUserId.value)
  const preview = msg.type === 'text' ? (msg.content || '').slice(0, 50) : (msg.type === 'audio' ? '🎤' : '🖼')
  replyingTo.value = {
    id: msg.id || msg.Id,
    content: preview,
    senderName: isMine ? (localeStore.locale === 'ar' ? 'أنت' : 'You') : (partner.value?.name || '—')
  }
  msgInputRef.value?.focus()
}

function cancelReply() {
  replyingTo.value = null
}

function scrollToRepliedMessage(replyToMessageId) {
  if (!replyToMessageId) return
  const id = String(replyToMessageId)
  const el = messagesEl.value?.querySelector(`[data-msg-id="${id}"]`)
  if (el) {
    el.scrollIntoView({ behavior: 'smooth', block: 'center' })
    highlightedMessageId.value = id
    setTimeout(() => { highlightedMessageId.value = null }, 1500)
  }
}

function openShareToConvModal(msg) {
  showMessageMenu.value = null
  showMessageMenuMsg.value = null
  router.push({
    path: '/share-message',
    state: {
      shareMessage: { content: msg.content, type: msg.type || 'text' },
      sourceConversationId: conversationId
    }
  })
}

function goToPartnerProfile() {
  if (convStore.isGroup) {
    router.push(`/conversation/${conversationId}/group-info`)
    return
  }
  const pid = convStore.partner?.id
  if (!pid) return
  router.push({
    path: `/profile/${pid}`,
    state: { conversationId }
  })
}

function openVideoConfirm() {
  showVideoConfirm.value = true
}

function openVoiceConfirm() {
  showVoiceConfirm.value = true
}

function cancelVideoConfirm() {
  showVideoConfirm.value = false
}

function cancelVoiceConfirm() {
  showVoiceConfirm.value = false
}

async function confirmStartVideo() {
  showVideoConfirm.value = false
  callingOut.value = true
  pendingOutgoingVoiceOnly.value = false
  try {
    await ensureConnected(conversationHub)
    await conversationHub.invoke('RequestVideoCall', conversationId, false)
  } catch {
    callingOut.value = false
  }
}

async function confirmStartVoice() {
  showVoiceConfirm.value = false
  callingOut.value = true
  pendingOutgoingVoiceOnly.value = true
  try {
    await ensureConnected(conversationHub)
    await conversationHub.invoke('RequestVideoCall', conversationId, true)
  } catch {
    callingOut.value = false
  }
}

function openSenderProfile(senderId) {
  if (!senderId) return
  router.push({
    path: `/profile/${senderId}`,
    state: { conversationId }
  })
}

async function fetchGroupSenders() {
  if (!convStore.isGroup || !conversationId) return
  try {
    const { data } = await api.get(`/conversations/${conversationId}/members`, { skipGlobalLoader: true })
    const list = data ?? []
    const map = {}
    for (const m of list) {
      const id = m.userId ?? m.UserId
      if (id) map[String(id)] = { name: m.name ?? m.Name ?? '—', avatar: m.avatar ?? m.Avatar ?? null }
    }
    groupSenders.value = map
  } catch {
    groupSenders.value = {}
  }
}

function getSenderDisplay(msg) {
  const id = msg?.senderId ?? msg?.SenderId
  const fromMsg = { name: msg?.senderName ?? msg?.SenderName, avatar: msg?.senderAvatar ?? msg?.SenderAvatar }
  const fromMap = id ? groupSenders.value[String(id)] : null
  return {
    name: fromMsg?.name || fromMap?.name || '—',
    avatar: fromMsg?.avatar ?? fromMap?.avatar ?? null
  }
}

/** Keep fixed popups inside the viewport (avoids negative top when opening above short space). */
function clampPopupTop(anchorRect, estHeight, gap = 4, pad = 8) {
  const H = window.innerHeight
  let top = anchorRect.top - estHeight - gap
  if (top < pad) {
    top = anchorRect.bottom + gap
  }
  if (top + estHeight > H - pad) {
    top = Math.max(pad, H - pad - estHeight)
  }
  if (top < pad) top = pad
  return top
}

function toggleMessageMenu(msg, e) {
  const id = msg.id || msg.Id
  if (showMessageMenu.value === id) {
    showMessageMenu.value = null
    showMessageMenuMsg.value = null
    return
  }
  const btn = e?.currentTarget
  if (btn) {
    const rect = btn.getBoundingClientRect()
    const popupWidth = 150
    const padding = 8
    let left = rect.right - popupWidth
    if (left < padding) left = padding
    if (left + popupWidth > window.innerWidth - padding) left = window.innerWidth - popupWidth - padding
    const MSG_MENU_EST_HEIGHT = 220
    const top = clampPopupTop(rect, MSG_MENU_EST_HEIGHT, 4, 8)
    msgMenuPosition.value = {
      top: top + 'px',
      left: left + 'px'
    }
  }
  showMessageMenu.value = id
  showMessageMenuMsg.value = msg
}

async function deleteForMe(msg) {
  showMessageMenu.value = null
  showMessageMenuMsg.value = null
  try {
    await conversationHub.invoke('DeleteMessageForMe', conversationId, msg.id || msg.Id)
  } catch {}
}

async function deleteForEveryone(msg) {
  showMessageMenu.value = null
  showMessageMenuMsg.value = null
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
      await ensureConnected(conversationHub, 25000)
      const formData = new FormData()
      const ext = blob.type.includes('webm') ? '.webm' : blob.type.includes('mp4') ? '.m4a' : '.ogg'
      formData.append('file', blob, `voice${ext}`)
      const { data } = await api.post('/media/upload-audio', formData, { timeout: 60000 })
      const url = data?.url ?? data?.data?.url
      if (!url) throw new Error()
      await ensureConnected(conversationHub, 25000)
      await conversationHub.invoke('SendMessage', conversationId, url, 'audio', null)
      pendingAudioBlobs.delete(newTempId)
    } else {
      await ensureConnected(conversationHub)
      await conversationHub.invoke('SendMessage', conversationId, msg.content, msg.type || 'text', null)
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

async function leaveChat() {
  convStore.clearConversation()
  router.replace('/conversations')
}

function openReactionFromMenu(msg) {
  showMessageMenu.value = null
  showMessageMenuMsg.value = null
  nextTick(() => openReactionPicker(msg, null))
}

function onMessageContextMenu(msg, e) {
  if (msg.deletedForEveryone) return
  e.preventDefault()
  openReactionPicker(msg, e)
}

function openReactionPicker(msg, e) {
  if (!(msg?.id ?? msg?.Id) || msg.deletedForEveryone) return
  showReactionPickerMsg.value = msg
  let btn = e?.currentTarget
  if (!btn && typeof document !== 'undefined') {
    const id = String(getMsgKey(msg))
    const wrap = document.querySelector(`[data-msg-id="${CSS.escape(id)}"]`)
    btn = wrap?.querySelector('.bubble') || wrap
  }
  if (btn) {
    const rect = btn.getBoundingClientRect()
    const padding = 16
    const maxPickerWidth = Math.min(280, window.innerWidth - padding * 2)
    let left = rect.left + (rect.width / 2) - (maxPickerWidth / 2)
    if (left + maxPickerWidth > window.innerWidth - padding) left = window.innerWidth - maxPickerWidth - padding
    if (left < padding) left = padding
    const PICKER_EST_HEIGHT = 56
    const top = clampPopupTop(rect, PICKER_EST_HEIGHT, 8, padding)
    reactionPickerPosition.value = {
      top: top + 'px',
      left: left + 'px',
      maxWidth: maxPickerWidth + 'px'
    }
  } else {
    reactionPickerPosition.value = {}
  }
}
function closeReactionPicker() {
  showReactionPickerMsg.value = null
}
async function pickReaction(msg, emoji) {
  const id = msg.id ?? msg.Id
  if (!id) return
  closeReactionPicker()
  const previousReactions = JSON.parse(JSON.stringify(msg.reactions || []))
  convStore.applyOptimisticReaction(id, currentUserId.value, emoji)
  try {
    await ensureConnected(conversationHub)
    await conversationHub.invoke('AddReaction', conversationId, id, emoji)
  } catch {
    convStore.updateMessageReactions(id, previousReactions)
  }
}
function removeReaction(msg) {
  const id = msg.id ?? msg.Id
  if (!id) return
  closeReactionPicker()
  ensureConnected(conversationHub).then(() =>
    conversationHub.invoke('RemoveReaction', conversationId, id)
  ).catch(() => {})
}
</script>

<template>
  <div class="conv-chat page">
    <LoaderOverlay :show="loading" :text="t('common.loading')" />

    <Transition name="fade">
      <div v-if="showVideoConfirm" class="call-overlay">
        <div class="call-popup glass-card">
          <div class="call-popup-avatar" :style="partnerAvatarIsImage ? { padding: 0, overflow: 'hidden' } : { background: partnerColor }">
            <CachedAvatar v-if="partnerAvatarIsImage" :url="partner?.avatar" img-class="call-popup-avatar-img" />
            <span v-else>{{ partnerLetter }}</span>
          </div>
          <div class="call-popup-name">{{ partner?.name }}</div>
          <div class="call-popup-label">{{ t('conversationChat.videoCallConfirm', { name: partner?.name || '…' }) }}</div>
          <div class="call-popup-actions">
            <button type="button" class="call-btn decline" @click="cancelVideoConfirm"><X :size="18" /> {{ t('common.cancel') }}</button>
            <button type="button" class="call-btn accept" @click="confirmStartVideo"><Video :size="18" /> {{ t('conversationChat.requestCall') }}</button>
          </div>
        </div>
      </div>
    </Transition>

    <Transition name="fade">
      <div v-if="showVoiceConfirm" class="call-overlay">
        <div class="call-popup glass-card">
          <div class="call-popup-avatar" :style="partnerAvatarIsImage ? { padding: 0, overflow: 'hidden' } : { background: partnerColor }">
            <CachedAvatar v-if="partnerAvatarIsImage" :url="partner?.avatar" img-class="call-popup-avatar-img" />
            <span v-else>{{ partnerLetter }}</span>
          </div>
          <div class="call-popup-name">{{ partner?.name }}</div>
          <div class="call-popup-label">{{ t('conversationChat.voiceCallConfirm', { name: partner?.name || '…' }) }}</div>
          <div class="call-popup-actions">
            <button type="button" class="call-btn decline" @click="cancelVoiceConfirm"><X :size="18" /> {{ t('common.cancel') }}</button>
            <button type="button" class="call-btn accept" @click="confirmStartVoice"><Phone :size="18" /> {{ t('conversationChat.requestCall') }}</button>
          </div>
        </div>
      </div>
    </Transition>

    <Transition name="fade">
      <div v-if="callingOut" class="call-overlay">
        <div class="call-popup glass-card calling-popup">
          <div class="calling-loader">
            <Loader2 :size="48" class="spin" />
          </div>
          <div class="call-popup-name">{{ partner?.name }}</div>
          <div class="call-popup-label">{{ t('conversationChat.connectingCall') }}</div>
          <div class="calling-dots">
            <span></span><span></span><span></span>
          </div>
          <button type="button" class="call-btn decline calling-cancel" @click="callingOut = false">
            <X :size="18" /> {{ t('common.cancel') }}
          </button>
        </div>
      </div>
    </Transition>

    <Transition name="fade">
      <div v-if="callDeclined" class="declined-toast">{{ t('conversationChat.callDeclined', { name: partner?.name || '…' }) }}</div>
    </Transition>

    <header class="chat-header glass-card">
      <button class="back-btn" @click="leaveChat" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <button type="button" class="partner-info partner-info-btn" @click="goToPartnerProfile">
        <div class="avatar-wrap">
          <div class="avatar avatar-sm" :style="partnerAvatarIsImage ? {} : { background: 'var(--primary)' }">
            <CachedAvatar v-if="partnerAvatarIsImage" :url="partner?.avatar" img-class="avatar-img" />
            <span v-else>{{ partnerLetter }}</span>
          </div>
        </div>
        <div class="partner-meta">
          <div class="partner-name">{{ partner?.name || '...' }}</div>
          <div class="typing-status">
            <span v-if="convStore.partnerTyping" class="typing-text">{{ t('conversationChat.typing') }}</span>
            <span v-else-if="convStore.isGroup" class="group-label">{{ t('groups.members') }}</span>
            <span v-else class="partner-online-status" :class="{ online: partnerIsOnline }">
              <span class="partner-online-dot"></span>
              {{ partnerIsOnline ? t('profile.online') : t('profile.offline') }}
            </span>
          </div>
        </div>
      </button>
      <div class="header-actions">
        <template v-if="!convStore.isGroup">
          <button type="button" class="icon-btn" @click="openVideoConfirm" :title="t('conversationChat.incomingVideoCall')">
            <Video :size="20" />
          </button>
          <button type="button" class="icon-btn" @click="openVoiceConfirm" :title="t('conversationChat.incomingVoiceCall')">
            <Phone :size="20" />
          </button>
        </template>
        <button class="icon-btn" @click="showDeleteConvConfirm = true" :title="t('conversationChat.deleteConversation')">
          <Trash2 :size="20" />
        </button>
      </div>
    </header>

    <div v-if="showEmbeddedActiveCallBar" class="conv-active-call-slot">
      <ActiveCallBar embedded />
    </div>

    <div class="messages-area" ref="messagesEl">
      <div v-if="showMessageMenu" class="msg-actions-backdrop" @click="showMessageMenu = null; showMessageMenuMsg = null" />
      <div v-if="!messages.length" class="empty-chat text-muted text-sm">{{ t('conversationChat.empty') }}</div>

      <div
        v-for="msg in messages"
        :key="msg.tempId || msg.id"
        :data-msg-id="getMsgKey(msg)"
        :class="['message-wrap', msg.senderId === currentUserId ? 'mine' : 'theirs', { 'msg-highlighted': highlightedMessageId === String(getMsgKey(msg)) }]"
      >
        <button
          v-if="convStore.isGroup && msg.senderId !== currentUserId"
          type="button"
          class="msg-sender-row"
          @click.stop="openSenderProfile(msg.senderId)"
        >
          <div
            class="msg-sender-avatar"
            :style="{ background: (getSenderDisplay(msg).avatar && (getSenderDisplay(msg).avatar.startsWith('http') || getSenderDisplay(msg).avatar.startsWith('/'))) ? 'var(--bg-elevated)' : 'var(--primary)' }"
          >
            <CachedAvatar v-if="getSenderDisplay(msg).avatar && (getSenderDisplay(msg).avatar.startsWith('http') || getSenderDisplay(msg).avatar.startsWith('/'))" :url="getSenderDisplay(msg).avatar" img-class="msg-sender-avatar-img" />
            <span v-else>{{ (getSenderDisplay(msg).name || '?')?.[0]?.toUpperCase() }}</span>
          </div>
          <span class="msg-sender-name">{{ getSenderDisplay(msg).name }}</span>
        </button>
        <div
          v-if="msg.type === 'image'"
          class="bubble image-bubble"
          @contextmenu="onMessageContextMenu(msg, $event)"
        >
          <div v-if="msg.replyToContent || msg.replyToSenderName" class="msg-reply-block" role="button" tabindex="0" @click.stop="scrollToRepliedMessage(msg.replyToMessageId)" @keydown.enter.space.prevent="scrollToRepliedMessage(msg.replyToMessageId)">
            <Reply :size="12" class="msg-reply-icon" />
            <div class="msg-reply-info">
              <span class="msg-reply-name">{{ msg.replyToSenderName || '—' }}</span>
              <span class="msg-reply-preview">{{ replyPreviewText(msg.replyToContent) }}</span>
            </div>
          </div>
          <img v-if="!msg.deletedForEveryone" :src="ensureAbsoluteUrl(msg.content)" class="chat-image" @click="openImage(msg.content)" referrerpolicy="no-referrer" />
          <span v-else class="deleted-msg">{{ t('conversationChat.messageDeleted') }}</span>
        </div>
        <div
          v-else-if="msg.type === 'audio'"
          class="bubble audio-bubble"
          @contextmenu="onMessageContextMenu(msg, $event)"
        >
          <div v-if="msg.replyToContent || msg.replyToSenderName" class="msg-reply-block" role="button" tabindex="0" @click.stop="scrollToRepliedMessage(msg.replyToMessageId)" @keydown.enter.space.prevent="scrollToRepliedMessage(msg.replyToMessageId)">
            <Reply :size="12" class="msg-reply-icon" />
            <div class="msg-reply-info">
              <span class="msg-reply-name">{{ msg.replyToSenderName || '—' }}</span>
              <span class="msg-reply-preview">{{ replyPreviewText(msg.replyToContent) }}</span>
            </div>
          </div>
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
        <div
          v-else
          class="bubble"
          @contextmenu="onMessageContextMenu(msg, $event)"
        >
          <div v-if="msg.replyToContent || msg.replyToSenderName" class="msg-reply-block" role="button" tabindex="0" @click.stop="scrollToRepliedMessage(msg.replyToMessageId)" @keydown.enter.space.prevent="scrollToRepliedMessage(msg.replyToMessageId)">
            <Reply :size="12" class="msg-reply-icon" />
            <div class="msg-reply-info">
              <span class="msg-reply-name">{{ msg.replyToSenderName || '—' }}</span>
              <span class="msg-reply-preview">{{ replyPreviewText(msg.replyToContent) }}</span>
            </div>
          </div>
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
            @click="toggleMessageMenu(msg, $event)"
          >
            <MoreVertical :size="14" />
          </button>
        </div>
        <div v-if="!msg.deletedForEveryone && messageReactionsList(msg).length > 0" class="msg-reactions-row">
          <template v-for="r in messageReactionsList(msg)" :key="r.emoji">
            <button
              type="button"
              class="reaction-chip"
              :class="{ 'reaction-chip-mine': getMyReaction(msg) === (r.emoji ?? r.Emoji) }"
              @click="pickReaction(msg, r.emoji ?? r.Emoji)"
            >
              <span class="reaction-emoji">{{ r.emoji ?? r.Emoji }}</span>
              <span v-if="(r.count ?? r.Count) > 1" class="reaction-count">{{ r.count ?? r.Count }}</span>
            </button>
          </template>
        </div>

      </div>

      <div v-if="convStore.partnerTyping" class="message-wrap theirs">
        <div class="bubble typing-bubble">
          <span class="typing-dots"><span></span><span></span><span></span></span>
        </div>
      </div>
    </div>

    <Teleport to="body">
      <Transition name="fade">
        <div v-if="showReactionPickerMsg" class="reaction-picker-backdrop" @click="closeReactionPicker" />
      </Transition>
      <Transition name="fade">
        <div v-if="showReactionPickerMsg" class="reaction-picker-popup glass-card" :style="reactionPickerPosition" @click.stop>
          <button
            v-for="emoji in REACTION_EMOJIS"
            :key="emoji"
            type="button"
            class="reaction-picker-emoji"
            @click="pickReaction(showReactionPickerMsg, emoji)"
          >{{ emoji }}</button>
        </div>
      </Transition>
    </Teleport>

    <Teleport to="body">
      <Transition name="fade">
        <div v-if="showMessageMenu && showMessageMenuMsg" class="msg-actions-popup glass-card msg-actions-popup-fixed" :style="msgMenuPosition">
          <button class="msg-action-btn msg-action-react" @click="openReactionFromMenu(showMessageMenuMsg)">
            <SmilePlus :size="14" stroke-width="2" class="msg-action-icon" />
            <span class="msg-action-label">{{ t('conversationChat.reaction') }}</span>
          </button>
          <button class="msg-action-btn msg-action-reply" @click="replyToMessage(showMessageMenuMsg)">
            <Reply :size="14" stroke-width="2" class="msg-action-icon" />
            <span class="msg-action-label">{{ t('conversationChat.reply') }}</span>
          </button>
          <button class="msg-action-btn msg-action-share" @click="openShareToConvModal(showMessageMenuMsg)">
            <Forward :size="14" stroke-width="2" class="msg-action-icon" />
            <span class="msg-action-label">{{ t('conversationChat.share') }}</span>
          </button>
          <button class="msg-action-btn msg-action-me" @click="deleteForMe(showMessageMenuMsg)">
            <Trash2 :size="14" stroke-width="2" class="msg-action-icon" />
            <span class="msg-action-label">{{ t('conversationChat.deleteForMe') }}</span>
          </button>
          <button v-if="showMessageMenuMsg.senderId === currentUserId" class="msg-action-btn msg-action-everyone" @click="deleteForEveryone(showMessageMenuMsg)">
            <UserX :size="14" stroke-width="2" class="msg-action-icon" />
            <span class="msg-action-label">{{ t('conversationChat.deleteForEveryone') }}</span>
          </button>
        </div>
      </Transition>
    </Teleport>

    <div class="input-area">
      <Transition name="slide-down">
        <div v-if="replyingTo" class="reply-preview-bar">
          <div class="reply-preview-content">
            <Reply :size="16" class="reply-preview-icon" />
            <div class="reply-preview-text">
              <span class="reply-preview-name">{{ replyingTo.senderName }}</span>
              <span class="reply-preview-msg">{{ replyingTo.content }}</span>
            </div>
          </div>
          <button class="reply-preview-close" @click="cancelReply" :aria-label="t('common.cancel')">
            <X :size="18" />
          </button>
        </div>
      </Transition>

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
      <div v-if="imageModalUrl" class="image-modal-overlay" @click.self="closeImageModal">
        <button class="image-modal-close" @click="closeImageModal"><X :size="24" /></button>
        <img :src="ensureAbsoluteUrl(imageModalUrl)" class="image-modal-img" alt="" referrerpolicy="no-referrer" />
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.conv-chat {
  position: relative;
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  min-width: 0;
  width: 100%;
  max-width: 100%;
  overflow: hidden;
  font-family: 'Cairo', sans-serif;
  box-sizing: border-box;
}

.conv-active-call-slot {
  flex-shrink: 0;
  padding: 0 var(--spacing) 8px;
}

.chat-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 4px;
  padding: calc(8px + var(--safe-top)) var(--spacing) 12px;
  flex-shrink: 0;
  border-radius: 0 0 var(--radius) var(--radius);
  border-top: none;
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
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
}

.partner-info-btn {
  border: none;
  background: none;
  padding: 0;
  cursor: pointer;
  text-align: start;
  -webkit-tap-highlight-color: transparent;
  font: inherit;
  color: inherit;
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
}

.group-label {
  font-size: 12px;
  color: var(--text-muted);
  min-height: 16px;
  display: flex;
  align-items: center;
  gap: 6px;
}

.typing-text { font-family: 'Cairo', sans-serif; }

.partner-online-status {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-family: 'Cairo', sans-serif;
  color: var(--text-tertiary);
}

.partner-online-status.online { color: var(--text-secondary); }

.partner-online-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--text-tertiary);
  flex-shrink: 0;
}

.partner-online-status.online .partner-online-dot {
  background: #22c55e;
  box-shadow: 0 0 0 1px var(--bg-primary);
}

.header-actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
  align-items: center;
}

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
  max-width: min(80%, calc(100vw - 24px));
  position: relative;
  min-width: 0;
}
.message-wrap.mine { align-self: flex-end; align-items: flex-end; }
.message-wrap.theirs { align-self: flex-start; align-items: flex-start; }

.msg-sender-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
  padding-inline-start: 2px;
  border: none;
  background: none;
  cursor: pointer;
  font: inherit;
  color: inherit;
  -webkit-tap-highlight-color: transparent;
  text-align: start;
}

.msg-sender-row:active {
  opacity: 0.85;
}

.msg-sender-avatar {
  width: 22px;
  height: 22px;
  min-width: 22px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  color: white;
  font-size: 12px;
  font-weight: 600;
}

.msg-sender-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.msg-sender-name {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-secondary);
  font-family: 'Cairo', sans-serif;
}


.message-wrap.msg-highlighted .bubble {
  animation: msg-highlight-pulse 1.5s ease-out;
}
@keyframes msg-highlight-pulse {
  0% { box-shadow: 0 0 0 0 rgba(108, 99, 255, 0.5); }
  30% { box-shadow: 0 0 0 8px rgba(108, 99, 255, 0.25); }
  100% { box-shadow: 0 0 0 0 rgba(108, 99, 255, 0); }
}
.message-wrap.mine.msg-highlighted .bubble {
  animation: msg-highlight-pulse-mine 1.5s ease-out;
}
@keyframes msg-highlight-pulse-mine {
  0% { box-shadow: 0 0 0 0 rgba(255, 255, 255, 0.4); }
  30% { box-shadow: 0 0 0 8px rgba(255, 255, 255, 0.2); }
  100% { box-shadow: 0 0 0 0 rgba(255, 255, 255, 0); }
}

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
.msg-time { font-size: 12px; color: var(--text-muted); font-family: 'Cairo', sans-serif; }
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
  font-size: 12px;
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
.msg-actions-popup.msg-actions-popup-fixed {
  position: fixed;
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

.msg-action-reply { color: var(--primary); }
.msg-action-reply:hover, .msg-action-reply:active { background: rgba(108, 99, 255, 0.12); color: var(--primary); }
.msg-action-share { color: var(--primary); }
.msg-action-share:hover, .msg-action-share:active { background: rgba(108, 99, 255, 0.12); color: var(--primary); }

/* رد فعل — وضع داكن: نص أوضح على glass-card */
.msg-action-react {
  color: #c9c6ff;
}
.msg-action-react:hover,
.msg-action-react:active {
  background: rgba(139, 132, 255, 0.22);
  color: #ecebff;
}
html.light .msg-action-react {
  color: var(--primary);
}
html.light .msg-action-react:hover,
html.light .msg-action-react:active {
  background: rgba(108, 99, 255, 0.12);
  color: var(--primary);
}

.msg-reactions-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  margin-top: 4px;
  padding-inline-start: 2px;
}
.reaction-chip {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  padding: 2px 8px;
  border-radius: 12px;
  border: 1px solid var(--border);
  background: var(--bg-elevated);
  color: var(--text-primary);
  font-size: 13px;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.15s, border-color 0.15s;
}
.reaction-chip:active { background: var(--bg-card-hover); }
.reaction-chip-mine {
  border-color: var(--primary);
  background: rgba(108, 99, 255, 0.15);
}
.reaction-emoji { line-height: 1; }
.reaction-count {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-secondary);
  min-width: 12px;
}
.reaction-picker-backdrop {
  position: fixed;
  inset: 0;
  z-index: 45;
}
.reaction-picker-popup {
  position: fixed;
  z-index: 46;
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 8px;
  padding: 8px 12px;
  border-radius: 24px;
  border: 1px solid var(--border);
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.22);
  max-width: calc(100vw - 32px);
  box-sizing: border-box;
}
.reaction-picker-emoji {
  width: 36px;
  height: 36px;
  min-width: 32px;
  min-height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: none;
  background: transparent;
  font-size: 22px;
  cursor: pointer;
  border-radius: 50%;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.15s, transform 0.1s;
  flex-shrink: 0;
}
.reaction-picker-emoji:active {
  background: var(--bg-card-hover);
  transform: scale(1.1);
}
@media (max-width: 360px) {
  .reaction-picker-popup {
    gap: 6px;
    padding: 6px 10px;
  }
  .reaction-picker-emoji {
    width: 32px;
    height: 32px;
    font-size: 18px;
  }
}

.msg-reply-block {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 6px 10px;
  margin: 0 0 8px 0;
  border-inline-start: 3px solid var(--primary);
  background: rgba(108, 99, 255, 0.1);
  border-radius: 8px;
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
  font: inherit;
  color: inherit;
  text-align: inherit;
  border: none;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.2s;
  appearance: none;
}
.msg-reply-block:active { background: rgba(108, 99, 255, 0.18); }
.msg-reply-block:hover { background: rgba(108, 99, 255, 0.16); }
.mine .msg-reply-block {
  border-inline-start: 3px solid rgba(255, 255, 255, 0.7);
  background: rgba(255, 255, 255, 0.15);
}
.mine .msg-reply-block:hover { background: rgba(255, 255, 255, 0.2); }
.mine .msg-reply-block:active { background: rgba(255, 255, 255, 0.22); }
.msg-reply-icon { flex-shrink: 0; color: var(--primary); }
.mine .msg-reply-icon { color: rgba(255, 255, 255, 0.95); }
.msg-reply-info { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
.msg-reply-name { font-size: 12px; font-weight: 700; color: var(--primary); }
.mine .msg-reply-name { color: rgba(255, 255, 255, 0.95); }
.msg-reply-preview { font-size: 12px; color: var(--text-secondary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mine .msg-reply-preview { color: rgba(255, 255, 255, 0.9); }

.reply-preview-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 14px;
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.15) 0%, rgba(108, 99, 255, 0.06) 100%);
  border: 1px solid rgba(108, 99, 255, 0.25);
  border-radius: 12px;
  margin-bottom: 8px;
}
.reply-preview-content { display: flex; align-items: center; gap: 10px; min-width: 0; flex: 1; }
.reply-preview-icon { color: var(--primary); flex-shrink: 0; }
.reply-preview-text { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.reply-preview-name { font-size: 12px; font-weight: 700; color: var(--primary); }
.reply-preview-msg { font-size: 13px; color: var(--text-secondary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.reply-preview-close { background: none; border: none; color: var(--text-muted); padding: 4px; cursor: pointer; border-radius: 8px; }
.reply-preview-close:active { background: rgba(0,0,0,0.08); }

.slide-down-enter-active, .slide-down-leave-active { transition: all 0.2s ease; }
.slide-down-enter-from, .slide-down-leave-to { opacity: 0; transform: translateY(-8px); }

.input-area {
  padding: 8px var(--spacing) calc(var(--spacing) + var(--safe-bottom));
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-height: 0;
}

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
  min-width: 0;
  width: 100%;
  max-width: min(260px, calc(100vw - 48px));
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
  max-width: min(220px, calc(100vw - 48px));
  width: auto;
  height: auto;
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

.call-popup-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
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

.call-popup-name {
  font-size: 18px;
  font-weight: 700;
  color: white;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100%;
}
.call-popup-label {
  font-size: 13px;
  color: var(--text-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 100%;
  text-align: center;
}

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
  max-width: calc(100vw - 32px);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  background: rgba(255,101,132,0.15);
  border: 1px solid rgba(255,101,132,0.3);
  border-radius: var(--radius-full);
  color: #FF6584;
  font-size: 13px;
  padding: 8px 18px;
  z-index: 50;
}

.spin { animation: spin 0.8s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

/* شاشات ضيقة — رأس الدردشة أصغر قليلاً */
@media (max-width: 420px) {
  .chat-header {
    padding: calc(6px + var(--safe-top)) 6px 8px;
    gap: 2px;
  }
  .partner-info {
    gap: 8px;
  }
  .partner-info-btn {
    margin-inline-start: 4px !important;
    margin-inline-end: 4px !important;
  }
  .header-actions {
    gap: 3px;
  }
  .chat-header .icon-btn {
    width: 32px;
    height: 32px;
    min-width: 32px;
  }
  .chat-header .icon-btn :deep(svg) {
    width: 17px;
    height: 17px;
  }
  .back-btn {
    width: 32px;
    height: 32px;
    min-width: 32px;
  }
  .back-btn :deep(svg) {
    width: 18px;
    height: 18px;
  }
  .chat-header .avatar-sm {
    width: 34px;
    height: 34px;
    font-size: 14px;
  }
  .partner-name {
    font-size: 14px;
  }
  .typing-status {
    font-size: 11px;
    margin-top: 0;
  }
  .partner-online-dot {
    width: 5px;
    height: 5px;
  }
  .messages-area {
    padding-left: 10px;
    padding-right: 10px;
  }
  .input-area {
    padding: 6px 6px calc(10px + var(--safe-bottom));
    gap: 6px;
  }
  .message-input-row {
    gap: 5px;
    min-height: 48px;
    align-items: center;
  }
  .msg-input {
    min-height: 46px;
    padding: 10px 12px;
    font-size: 15px;
    border-radius: 20px;
  }
  .send-btn {
    width: 38px;
    height: 38px;
    min-width: 38px;
  }
  .send-btn :deep(svg) {
    width: 17px;
    height: 17px;
  }
  .input-action-btn {
    width: 38px;
    height: 38px;
    min-width: 38px;
    border-radius: 10px;
  }
  .input-action-btn :deep(svg) {
    width: 17px;
    height: 17px;
  }
}

@media (max-width: 360px) {
  .chat-header {
    padding: calc(4px + var(--safe-top)) 4px 6px;
    gap: 0;
  }
  .partner-info {
    gap: 6px;
  }
  .partner-info-btn {
    margin-inline-start: 2px !important;
    margin-inline-end: 2px !important;
  }
  .header-actions {
    gap: 2px;
  }
  .chat-header .icon-btn {
    width: 30px;
    height: 30px;
    min-width: 30px;
  }
  .chat-header .icon-btn :deep(svg) {
    width: 15px;
    height: 15px;
  }
  .back-btn {
    width: 30px;
    height: 30px;
    min-width: 30px;
  }
  .back-btn :deep(svg) {
    width: 17px;
    height: 17px;
  }
  .chat-header .avatar-sm {
    width: 32px;
    height: 32px;
    font-size: 13px;
  }
  .partner-name {
    font-size: 13px;
  }
  .typing-status {
    font-size: 10px;
  }
  .messages-area {
    padding-left: 8px;
    padding-right: 8px;
  }
  .input-area {
    padding: 4px 4px calc(8px + var(--safe-bottom));
    gap: 4px;
  }
  .message-input-row {
    gap: 4px;
    min-height: 44px;
  }
  .msg-input {
    padding: 8px 10px;
    font-size: 14px;
    min-height: 44px;
    border-radius: 18px;
  }
  .send-btn {
    width: 34px;
    height: 34px;
    min-width: 34px;
  }
  .send-btn :deep(svg) {
    width: 15px;
    height: 15px;
  }
  .input-action-btn {
    width: 34px;
    height: 34px;
    min-width: 34px;
    border-radius: 9px;
  }
  .input-action-btn :deep(svg) {
    width: 15px;
    height: 15px;
  }
}
</style>
