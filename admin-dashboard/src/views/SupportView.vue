<script setup>
import { ref, watch, computed } from 'vue'
import api from '../services/api'

const conversations = ref([])
const totalConvos = ref(0)
const convoPage = ref(1)
const convoPageSize = ref(30)
const searchQuery = ref('')
const loadingConvos = ref(false)

const selectedSession = ref(null)
const messages = ref([])
const totalMessages = ref(0)
const msgSearchQuery = ref('')
const loadingMessages = ref(false)
const msgPage = ref(1)
const msgPageSize = ref(50)
const replyText = ref('')
const sending = ref(false)

async function fetchConversations() {
  loadingConvos.value = true
  try {
    const res = await api.get('/admin/support/sessions', {
      params: {
        page: convoPage.value,
        pageSize: convoPageSize.value,
        search: searchQuery.value || undefined
      }
    })
    conversations.value = res.data.items
    totalConvos.value = res.data.total
  } catch {
    conversations.value = []
    totalConvos.value = 0
  } finally {
    loadingConvos.value = false
  }
}

async function fetchMessages(sessionId) {
  if (!sessionId) {
    messages.value = []
    totalMessages.value = 0
    return
  }
  loadingMessages.value = true
  msgPage.value = 1
  try {
    const res = await api.get('/admin/messages', {
      params: {
        sessionId,
        page: 1,
        pageSize: msgPageSize.value
      }
    })
    messages.value = (res.data.items || []).sort((a, b) =>
      new Date(a.sentAt) - new Date(b.sentAt)
    )
    totalMessages.value = res.data.total
  } catch {
    messages.value = []
    totalMessages.value = 0
  } finally {
    loadingMessages.value = false
  }
}

function selectConversation(session) {
  selectedSession.value = session
  msgSearchQuery.value = ''
  replyText.value = ''
  fetchMessages(session.id)
}

function loadMoreMessages() {
  if (!selectedSession.value || loadingMessages.value) return
  msgPage.value++
  api.get('/admin/messages', {
    params: {
      sessionId: selectedSession.value.id,
      page: msgPage.value,
      pageSize: msgPageSize.value
    }
  }).then(res => {
    const newMsgs = (res.data.items || []).sort((a, b) =>
      new Date(a.sentAt) - new Date(b.sentAt)
    )
    messages.value = [...newMsgs, ...messages.value]
  })
}

async function sendReply() {
  const text = replyText.value?.trim()
  if (!text || !selectedSession.value || sending.value) return
  sending.value = true
  try {
    await api.post('/admin/support/send', {
      sessionId: selectedSession.value.id,
      content: text
    })
    replyText.value = ''
    const newMsg = {
      id: crypto.randomUUID(),
      senderName: 'دعم',
      content: text,
      type: 'text',
      sentAt: new Date().toISOString()
    }
    messages.value = [...messages.value, newMsg]
  } catch (e) {
    console.error(e)
  } finally {
    sending.value = false
  }
}

watch(searchQuery, () => {
  convoPage.value = 1
  fetchConversations()
})

watch(convoPage, fetchConversations)

fetchConversations()

function formatTime(dt) {
  return new Date(dt).toLocaleString('ar-SA', {
    month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit'
  })
}

function formatDate(dt) {
  return new Date(dt).toLocaleDateString('ar-SA', {
    weekday: 'short', month: 'short', day: 'numeric'
  })
}

function convoTitle(session) {
  return session.user2Name
}

function isFromUser1(msg) {
  return selectedSession.value && msg.senderName === selectedSession.value.user1Name
}

const filteredMessages = computed(() => {
  const q = msgSearchQuery.value?.trim().toLowerCase()
  if (!q) return messages.value
  return messages.value.filter(m =>
    (m.content && m.content.toLowerCase().includes(q)) || m.senderName?.toLowerCase().includes(q)
  )
})
</script>

<template>
  <div class="support-page">
    <div class="page-header mb-4">
      <div>
        <div class="text-h5 font-weight-bold">دردشة الدعم</div>
        <div class="text-body-2 text-medium-emphasis">
          {{ totalConvos.toLocaleString() }} محادثة
        </div>
      </div>
    </div>

    <div class="messages-layout">
      <div class="conversation-list">
        <div class="search-wrap pa-3">
          <v-text-field
            v-model="searchQuery"
            placeholder="بحث بالاسم..."
            prepend-inner-icon="mdi-magnify"
            variant="outlined"
            density="compact"
            rounded="lg"
            hide-details
            clearable
            bg-color="rgba(255,255,255,0.04)"
          />
        </div>

        <div v-if="loadingConvos" class="d-flex justify-center pa-6">
          <v-progress-circular indeterminate color="primary" size="32" />
        </div>

        <div v-else-if="conversations.length === 0" class="empty-list pa-6 text-center">
          <v-icon size="48" color="medium-emphasis">mdi-headset</v-icon>
          <div class="text-body-2 text-medium-emphasis mt-2">لا توجد محادثات دعم</div>
        </div>

        <div v-else class="convo-items">
          <div
            v-for="c in conversations"
            :key="c.id"
            class="convo-item"
            :class="{ active: selectedSession?.id === c.id }"
            @click="selectConversation(c)"
          >
            <div class="convo-avatar">
              {{ c.user2Name?.[0]?.toUpperCase() }}
            </div>
            <div class="convo-info">
              <div class="convo-title">{{ convoTitle(c) }}</div>
              <div class="convo-meta">
                {{ c.messageCount }} رسالة · {{ formatDate(c.startedAt) }}
              </div>
            </div>
          </div>
        </div>

        <div v-if="totalConvos > convoPageSize" class="pa-2">
          <v-pagination
            v-model="convoPage"
            :length="Math.ceil(totalConvos / convoPageSize)"
            :total-visible="4"
            density="compact"
            size="small"
          />
        </div>
      </div>

      <div class="chat-panel">
        <div v-if="!selectedSession" class="chat-placeholder">
          <v-icon size="80" color="medium-emphasis">mdi-headset</v-icon>
          <div class="text-h6 font-weight-medium text-medium-emphasis mt-3">
            اختر محادثة للرد
          </div>
        </div>

        <template v-else>
          <div class="chat-header">
            <v-btn
              icon="mdi-arrow-right"
              variant="text"
              size="small"
              class="d-md-none"
              @click="selectedSession = null"
            />
            <div class="chat-header-info">
              <span class="font-weight-bold">{{ convoTitle(selectedSession) }}</span>
              <span class="text-caption text-medium-emphasis ms-2">
                {{ selectedSession.messageCount }} رسالة
              </span>
            </div>
          </div>

          <div class="chat-search pa-3">
            <v-text-field
              v-model="msgSearchQuery"
              placeholder="بحث في الرسائل..."
              prepend-inner-icon="mdi-magnify"
              variant="outlined"
              density="compact"
              rounded="lg"
              hide-details
              clearable
              bg-color="rgba(255,255,255,0.04)"
            />
          </div>

          <div class="chat-messages">
            <div v-if="totalMessages > messages.length && !msgSearchQuery" class="load-more-wrap">
              <v-btn
                variant="tonal"
                size="small"
                :loading="loadingMessages"
                @click="loadMoreMessages"
              >
                تحميل المزيد
              </v-btn>
            </div>

            <div v-if="msgSearchQuery && filteredMessages.length === 0" class="empty-search pa-6 text-center">
              <v-icon size="48" color="medium-emphasis">mdi-magnify-close</v-icon>
              <div class="text-body-2 text-medium-emphasis mt-2">لا توجد نتائج</div>
            </div>

            <div
              v-for="msg in filteredMessages"
              :key="msg.id"
              class="msg-bubble"
              :class="{ right: isFromUser1(msg), left: !isFromUser1(msg) }"
            >
              <div class="msg-sender">{{ msg.senderName }}</div>
              <template v-if="msg.type === 'image'">
                <a :href="msg.content" target="_blank" class="msg-image-link">
                  <v-icon size="20">mdi-image</v-icon>
                  عرض الصورة
                </a>
              </template>
              <div v-else class="msg-text">{{ msg.content }}</div>
              <div class="msg-time">{{ formatTime(msg.sentAt) }}</div>
            </div>
          </div>

          <div class="chat-reply pa-3">
            <v-text-field
              v-model="replyText"
              placeholder="اكتب ردك..."
              variant="outlined"
              density="compact"
              rounded="lg"
              hide-details
              clearable
              @keyup.enter="sendReply"
            >
              <template #append-inner>
                <v-btn
                  icon="mdi-send"
                  variant="flat"
                  color="primary"
                  size="small"
                  :loading="sending"
                  :disabled="!replyText?.trim()"
                  @click="sendReply"
                />
              </template>
            </v-text-field>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.support-page {
  height: calc(100vh - 130px);
  min-height: 400px;
}

.page-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 24px;
  flex-wrap: wrap;
}

.messages-layout {
  display: flex;
  gap: 0;
  height: 100%;
  background: rgba(255,255,255,0.03);
  border: 1px solid rgba(255,255,255,0.08);
  border-radius: 16px;
  overflow: hidden;
}

.conversation-list {
  width: 320px;
  min-width: 280px;
  border-left: 1px solid rgba(255,255,255,0.08);
  display: flex;
  flex-direction: column;
  background: rgba(0,0,0,0.2);
}

.search-wrap {
  flex-shrink: 0;
}

.convo-items {
  flex: 1;
  overflow-y: auto;
}

.convo-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 14px 16px;
  cursor: pointer;
  transition: background 0.15s;
  border-bottom: 1px solid rgba(255,255,255,0.04);
}
.convo-item:hover {
  background: rgba(108,99,255,0.08);
}
.convo-item.active {
  background: rgba(108,99,255,0.15);
}

.convo-avatar {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  background: linear-gradient(135deg, #6C63FF, #FF6584);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  font-weight: 700;
  color: white;
  flex-shrink: 0;
}

.convo-info {
  flex: 1;
  min-width: 0;
}

.convo-title {
  font-size: 14px;
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.convo-meta {
  font-size: 12px;
  color: rgba(255,255,255,0.5);
  margin-top: 2px;
}

.empty-list {
  flex: 1;
}

.chat-panel {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.chat-placeholder {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: rgba(255,255,255,0.4);
}

.chat-header {
  padding: 16px 20px;
  border-bottom: 1px solid rgba(255,255,255,0.08);
  display: flex;
  align-items: center;
  gap: 12px;
  flex-shrink: 0;
}

.chat-header-info {
  flex: 1;
}

.chat-search {
  flex-shrink: 0;
  border-bottom: 1px solid rgba(255,255,255,0.06);
}

.chat-messages {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.load-more-wrap {
  margin-bottom: 8px;
}

.msg-bubble {
  max-width: 75%;
  border-radius: 16px;
  padding: 12px 16px;
  border: 1px solid rgba(255,255,255,0.06);
}
.msg-bubble.right {
  align-self: flex-end;
  background: linear-gradient(135deg, rgba(108,99,255,0.25), rgba(255,101,132,0.2));
  border-color: rgba(108,99,255,0.3);
}
.msg-bubble.left {
  align-self: flex-start;
  background: rgba(255,255,255,0.06);
}

.msg-sender {
  font-size: 12px;
  font-weight: 600;
  color: #6C63FF;
  margin-bottom: 4px;
}

.msg-text {
  font-size: 14px;
  line-height: 1.5;
  word-break: break-word;
}

.msg-image-link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: #00D4FF;
  text-decoration: none;
  font-size: 14px;
}
.msg-image-link:hover {
  text-decoration: underline;
}

.msg-time {
  font-size: 11px;
  color: rgba(255,255,255,0.45);
  margin-top: 6px;
}

.chat-reply {
  flex-shrink: 0;
  border-top: 1px solid rgba(255,255,255,0.08);
}

@media (max-width: 960px) {
  .messages-layout {
    flex-direction: column;
  }

  .conversation-list {
    width: 100%;
    max-height: 40%;
    border-left: none;
    border-bottom: 1px solid rgba(255,255,255,0.08);
  }

  .chat-panel {
    min-height: 50%;
  }
}
</style>
