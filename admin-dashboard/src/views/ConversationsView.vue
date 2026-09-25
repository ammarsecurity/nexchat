<script setup>
import { ref, watch, computed } from 'vue'
import { useRoute } from 'vue-router'
import api from '../services/api'
import { notify } from '../utils/notify'
import AvatarCircle from '../components/AvatarCircle.vue'
import { formatIraqDate, formatIraqDateTime, formatIraqTime } from '../utils/iraqTime'

const route = useRoute()
/** private = محادثات ثنائية، group = مجموعات */
const conversationKind = computed(() => route.meta.conversationKind || 'private')
const isGroupPage = computed(() => conversationKind.value === 'group')

const conversations = ref([])
const totalConvos = ref(0)
const convoPage = ref(1)
const convoPageSize = ref(30)
const searchQuery = ref('')
const loadingConvos = ref(false)

const selectedConversation = ref(null)
const messages = ref([])
const totalMessages = ref(0)
const msgSearchQuery = ref('')
const loadingMessages = ref(false)
const msgPage = ref(1)
const msgPageSize = ref(50)

const selectedConvoIds = ref(new Set())
const selectedMsgIds = ref(new Set())
const showDeleteConvoConfirm = ref(false)
const showDeleteMsgConfirm = ref(false)
const deleting = ref(false)

async function fetchConversations() {
  loadingConvos.value = true
  try {
    const res = await api.get('/admin/conversations', {
      params: {
        page: convoPage.value,
        pageSize: convoPageSize.value,
        search: searchQuery.value || undefined,
        kind: conversationKind.value
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

async function fetchMessages(conversationId) {
  if (!conversationId) {
    messages.value = []
    totalMessages.value = 0
    return
  }
  loadingMessages.value = true
  msgPage.value = 1
  try {
    const res = await api.get(`/admin/conversations/${conversationId}/messages`, {
      params: {
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

function selectConversation(conv) {
  selectedConversation.value = conv
  msgSearchQuery.value = ''
  selectedMsgIds.value = new Set()
  fetchMessages(conv.id)
}

function loadMoreMessages() {
  if (!selectedConversation.value || loadingMessages.value) return
  msgPage.value++
  api.get(`/admin/conversations/${selectedConversation.value.id}/messages`, {
    params: {
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

watch(searchQuery, () => {
  convoPage.value = 1
  fetchConversations()
})

watch(convoPage, fetchConversations)

watch(conversationKind, () => {
  convoPage.value = 1
  selectedConversation.value = null
  messages.value = []
  selectedConvoIds.value = new Set()
  fetchConversations()
})

fetchConversations()

function formatTime(dt) {
  return formatIraqTime(dt)
}

function formatDate(dt) {
  return formatIraqDate(dt)
}

function convoTitle(conv) {
  if (!conv) return ''
  const t = conv.type ?? conv.Type
  if (t === 1 || conv.groupName || conv.GroupName) {
    return conv.groupName || conv.GroupName || 'مجموعة'
  }
  return `${conv.user1Name ?? conv.User1Name ?? '—'} ↔ ${conv.user2Name ?? conv.User2Name ?? '—'}`
}

function isGroupConv(conv) {
  if (!conv) return false
  const t = conv.type ?? conv.Type
  return t === 1 || !!(conv.groupName || conv.GroupName)
}

function isFromUser1(msg) {
  if (!selectedConversation.value) return false
  if (isGroupConv(selectedConversation.value)) return false
  return msg.senderName === selectedConversation.value.user1Name
}

const filteredMessages = computed(() => {
  const q = msgSearchQuery.value?.trim().toLowerCase()
  if (!q) return messages.value
  return messages.value.filter(m =>
    (m.content && m.content.toLowerCase().includes(q)) || m.senderName?.toLowerCase().includes(q)
  )
})

const allConvosSelected = computed(() =>
  conversations.value.length > 0 && conversations.value.every(c => selectedConvoIds.value.has(c.id))
)
const someConvosSelected = computed(() => selectedConvoIds.value.size > 0)
const allMsgsSelected = computed(() =>
  filteredMessages.value.length > 0 && filteredMessages.value.every(m => selectedMsgIds.value.has(m.id))
)
const someMsgsSelected = computed(() => selectedMsgIds.value.size > 0)

function toggleConvo(c) {
  const set = new Set(selectedConvoIds.value)
  if (set.has(c.id)) set.delete(c.id)
  else set.add(c.id)
  selectedConvoIds.value = set
}

function toggleAllConvos() {
  if (allConvosSelected.value) selectedConvoIds.value = new Set()
  else selectedConvoIds.value = new Set(conversations.value.map(c => c.id))
}

function toggleMsg(m) {
  const set = new Set(selectedMsgIds.value)
  if (set.has(m.id)) set.delete(m.id)
  else set.add(m.id)
  selectedMsgIds.value = set
}

function toggleAllMsgs() {
  const list = filteredMessages.value
  if (allMsgsSelected.value) selectedMsgIds.value = new Set()
  else selectedMsgIds.value = new Set(list.map(m => m.id))
}

function openDeleteConvoConfirm() {
  if (selectedConvoIds.value.size === 0) return
  showDeleteConvoConfirm.value = true
}

async function confirmDeleteConvos() {
  const ids = [...selectedConvoIds.value]
  if (ids.length === 0) return
  deleting.value = true
  try {
    if (ids.length === 1) {
      await api.delete(`/admin/conversations/${ids[0]}`)
    } else {
      await api.delete('/admin/conversations', { data: { ids } })
    }
    selectedConvoIds.value = new Set()
    showDeleteConvoConfirm.value = false
    if (selectedConversation.value && ids.includes(selectedConversation.value.id)) {
      selectedConversation.value = null
      messages.value = []
    }
    await fetchConversations()
  } catch (e) {
    notify.error(e.response?.data?.message || 'فشل الحذف')
  } finally {
    deleting.value = false
  }
}

function openDeleteMsgConfirm() {
  if (selectedMsgIds.value.size === 0) return
  showDeleteMsgConfirm.value = true
}

async function confirmDeleteMsgs() {
  const ids = [...selectedMsgIds.value]
  const convId = selectedConversation.value?.id
  if (ids.length === 0 || !convId) return
  deleting.value = true
  try {
    if (ids.length === 1) {
      await api.delete(`/admin/conversations/${convId}/messages/${ids[0]}`)
    } else {
      await api.delete(`/admin/conversations/${convId}/messages`, { data: { ids } })
    }
    selectedMsgIds.value = new Set()
    showDeleteMsgConfirm.value = false
    await fetchMessages(convId)
    totalMessages.value = Math.max(0, totalMessages.value - ids.length)
  } catch (e) {
    notify.error(e.response?.data?.message || 'فشل الحذف')
  } finally {
    deleting.value = false
  }
}
</script>

<template>
  <div class="conversations-page">
    <div class="d-flex align-center justify-space-between mb-4 flex-wrap gap-2">
      <div>
        <div class="text-h5 font-weight-bold">{{ isGroupPage ? 'المجموعات' : 'المحادثات' }}</div>
        <div class="text-body-2 text-medium-emphasis">
          {{ totalConvos.toLocaleString() }} {{ isGroupPage ? 'مجموعة' : 'محادثة' }}
        </div>
      </div>
      <div v-if="someConvosSelected" class="page-actions">
        <v-btn
          color="error"
          variant="tonal"
          size="small"
          prepend-icon="mdi-delete"
          :loading="deleting"
          @click="openDeleteConvoConfirm"
        >
          حذف {{ selectedConvoIds.size }} {{ selectedConvoIds.size === 1 ? 'محادثة' : 'محادثات' }}
        </v-btn>
      </div>
    </div>

    <div class="messages-layout">
      <div class="conversation-list">
        <div class="search-wrap pa-3">
          <v-text-field
            v-model="searchQuery"
            :placeholder="isGroupPage ? 'بحث باسم المجموعة...' : 'بحث بالاسم...'"
            prepend-inner-icon="mdi-magnify"
            variant="outlined"
            density="compact"
            rounded="lg"
            hide-details
            clearable
            bg-color="#F8FAFC"
          />
        </div>

        <div v-if="loadingConvos" class="d-flex justify-center pa-6">
          <v-progress-circular indeterminate color="primary" size="32" />
        </div>

        <div v-else-if="conversations.length === 0" class="empty-list pa-6 text-center">
          <v-icon size="48" color="medium-emphasis">{{ isGroupPage ? 'mdi-account-group-outline' : 'mdi-forum-outline' }}</v-icon>
          <div class="text-body-2 text-medium-emphasis mt-2">{{ isGroupPage ? 'لا توجد مجموعات' : 'لا توجد محادثات' }}</div>
        </div>

        <div v-else class="convo-items">
          <div v-if="conversations.length" class="convo-select-all pa-2">
            <v-checkbox
              :model-value="allConvosSelected"
              :indeterminate="someConvosSelected && !allConvosSelected"
              hide-details
              density="compact"
              color="primary"
              @click.stop="toggleAllConvos"
            >
              <template #label>
                <span class="text-caption">تحديد الكل</span>
              </template>
            </v-checkbox>
          </div>
          <div
            v-for="c in conversations"
            :key="c.id"
            class="convo-item"
            :class="{ active: selectedConversation?.id === c.id }"
            @click="selectConversation(c)"
          >
            <v-checkbox
              :model-value="selectedConvoIds.has(c.id)"
              hide-details
              density="compact"
              color="primary"
              class="convo-checkbox"
              @click.stop="toggleConvo(c)"
            />
            <div v-if="isGroupConv(c)" class="convo-avatar convo-avatar--group">
              <v-icon size="22" color="primary">mdi-account-group</v-icon>
            </div>
            <div v-else class="convo-avatar-stack">
              <AvatarCircle :name="c.user1Name" :avatar="c.user1Avatar" :size="32" />
              <AvatarCircle :name="c.user2Name" :avatar="c.user2Avatar" :size="32" color="secondary" />
            </div>
            <div class="convo-info">
              <div class="convo-title">{{ convoTitle(c) }}</div>
              <div class="convo-meta">
                {{ c.messageCount }} رسالة · {{ c.lastMessageAt ? formatDate(c.lastMessageAt) : formatDate(c.createdAt) }}
              </div>
            </div>
          </div>
        </div>

        <div v-if="totalConvos > 0" class="pagination-bar">
          <v-pagination
            v-model="convoPage"
            :length="Math.max(1, Math.ceil(totalConvos / convoPageSize))"
            :total-visible="5"
            density="comfortable"
            active-color="primary"
          />
        </div>
      </div>

      <div class="chat-panel">
        <div v-if="!selectedConversation" class="chat-placeholder">
          <v-icon size="80" color="medium-emphasis">{{ isGroupPage ? 'mdi-account-group-outline' : 'mdi-forum-outline' }}</v-icon>
          <div class="text-h6 font-weight-medium text-medium-emphasis mt-3">
            {{ isGroupPage ? 'اختر مجموعة لعرض الرسائل' : 'اختر محادثة لعرض الرسائل' }}
          </div>
        </div>

        <template v-else>
          <div class="chat-header">
            <v-btn
              icon="mdi-arrow-right"
              variant="text"
              size="small"
              class="d-md-none"
              @click="selectedConversation = null"
            />
            <div class="chat-header-info">
              <span class="font-weight-bold">{{ convoTitle(selectedConversation) }}</span>
              <span class="text-caption text-medium-emphasis ms-2">
                {{ selectedConversation.messageCount }} رسالة
              </span>
            </div>
            <v-btn
              v-if="someMsgsSelected"
              color="error"
              variant="tonal"
              size="small"
              :loading="deleting"
              @click="openDeleteMsgConfirm"
            >
              حذف {{ selectedMsgIds.size }} {{ selectedMsgIds.size === 1 ? 'رسالة' : 'رسائل' }}
            </v-btn>
          </div>

          <div v-if="filteredMessages.length" class="msg-select-all pa-2 d-flex align-center">
            <v-checkbox
              :model-value="allMsgsSelected"
              :indeterminate="someMsgsSelected && !allMsgsSelected"
              hide-details
              density="compact"
              color="primary"
              @click.stop="toggleAllMsgs"
            >
              <template #label>
                <span class="text-caption">تحديد كل الرسائل</span>
              </template>
            </v-checkbox>
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
              bg-color="#F8FAFC"
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
              <div class="text-body-2 text-medium-emphasis mt-2">لا توجد نتائج لـ "{{ msgSearchQuery }}"</div>
            </div>

            <div
              v-for="msg in filteredMessages"
              :key="msg.id"
              class="msg-bubble d-flex align-start gap-2"
              :class="{ right: isFromUser1(msg), left: !isFromUser1(msg) }"
            >
              <v-checkbox
                :model-value="selectedMsgIds.has(msg.id)"
                hide-details
                density="compact"
                color="primary"
                class="msg-checkbox flex-shrink-0 mt-0"
                @click.stop="toggleMsg(msg)"
              />
              <div class="msg-content flex-grow-1 min-width-0">
              <div class="msg-sender d-flex align-center gap-2">
                <AvatarCircle :name="msg.senderName" :avatar="msg.senderAvatar" :size="22" />
                <span>{{ msg.senderName }}</span>
              </div>
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
          </div>
        </template>
      </div>
    </div>

    <v-dialog v-model="showDeleteConvoConfirm" persistent max-width="400">
      <v-card>
        <v-card-title>حذف المحادثات</v-card-title>
        <v-card-text>
          هل أنت متأكد من حذف {{ selectedConvoIds.size }} {{ selectedConvoIds.size === 1 ? 'محادثة' : 'محادثات' }}؟ الحذف نهائي ولا يمكن التراجع عنه.
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="showDeleteConvoConfirm = false">إلغاء</v-btn>
          <v-btn color="error" :loading="deleting" @click="confirmDeleteConvos">حذف</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="showDeleteMsgConfirm" persistent max-width="400">
      <v-card>
        <v-card-title>حذف الرسائل</v-card-title>
        <v-card-text>
          هل أنت متأكد من حذف {{ selectedMsgIds.size }} {{ selectedMsgIds.size === 1 ? 'رسالة' : 'رسائل' }}؟ الحذف نهائي ولا يمكن التراجع عنه.
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="showDeleteMsgConfirm = false">إلغاء</v-btn>
          <v-btn color="error" :loading="deleting" @click="confirmDeleteMsgs">حذف</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.conversations-page {
  height: calc(100vh - 130px);
  min-height: 400px;
}

.messages-layout {
  display: flex;
  gap: 0;
  height: 100%;
  background: #FFFFFF;
  border: 1px solid rgba(15,23,42,0.08);
  border-radius: 16px;
  overflow: hidden;
}

.conversation-list {
  width: 320px;
  min-width: 280px;
  border-left: 1px solid rgba(15,23,42,0.08);
  display: flex;
  flex-direction: column;
  background: #F8FAFC;
}

.search-wrap {
  flex-shrink: 0;
}

.convo-items {
  flex: 1;
  overflow-y: auto;
}

.convo-select-all {
  border-bottom: 1px solid rgba(15,23,42,0.06);
}
.convo-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 14px 16px;
  cursor: pointer;
  transition: background 0.15s;
  border-bottom: 1px solid rgba(15,23,42,0.05);
}
.convo-item:hover {
  background: rgba(46, 134, 251,0.08);
}
.convo-item.active {
  background: rgba(46, 134, 251,0.15);
}

.convo-checkbox { flex-shrink: 0; }
.convo-avatar {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  background: linear-gradient(135deg, #8B5CF6, #22D3EE);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  font-weight: 700;
  color: white;
  flex-shrink: 0;
}
.convo-avatar--group {
  background: rgba(46, 134, 251, 0.35);
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
  color: #94A3B8;
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
  color: #94A3B8;
}

.chat-header {
  padding: 16px 20px;
  border-bottom: 1px solid rgba(15,23,42,0.08);
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
  border-bottom: 1px solid rgba(15,23,42,0.06);
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
  border: 1px solid rgba(15,23,42,0.06);
}
.msg-bubble.right {
  align-self: flex-end;
  background: linear-gradient(135deg, rgba(139,92,246,0.14), rgba(34,211,238,0.1));
  border-color: rgba(139, 92, 246,0.3);
}
.msg-bubble.left {
  align-self: flex-start;
  background: #F1F5F9;
}

.msg-sender {
  font-size: 12px;
  font-weight: 600;
  color: #8B5CF6;
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
  color: #0EA5E9;
  text-decoration: none;
  font-size: 14px;
}
.msg-image-link:hover {
  text-decoration: underline;
}

.msg-time {
  font-size: 11px;
  color: #94A3B8;
  margin-top: 6px;
}
.msg-select-all { border-bottom: 1px solid rgba(15,23,42,0.06); }
.msg-checkbox :deep(.v-selection-control) { min-height: 32px; }

@media (max-width: 960px) {
  .messages-layout {
    flex-direction: column;
  }

  .conversation-list {
    width: 100%;
    max-height: 40%;
    border-left: none;
    border-bottom: 1px solid rgba(15,23,42,0.08);
  }

  .chat-panel {
    min-height: 50%;
  }
}
</style>
