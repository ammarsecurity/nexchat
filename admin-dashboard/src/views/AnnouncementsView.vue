<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'
import { formatIraqDateTime } from '../utils/iraqTime'

const content = ref('')
const mediaUrl = ref('')
const mediaType = ref('text') // text | image | video
const mediaFile = ref(null)
const mediaPreview = ref('')
const mediaInput = ref(null)
const uploading = ref(false)
const sending = ref(false)
const success = ref(false)
const recipientsCount = ref(0)
const totalUsers = ref(0)

const history = ref([])
const historyTotal = ref(0)
const historyPage = ref(1)
const loadingHistory = ref(false)

const editing = ref(null)
const editContent = ref('')
const editCaption = ref('')
const editSaving = ref(false)
const deletingId = ref(null)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

function fullUrl(url) {
  if (!url) return ''
  if (url.startsWith('http')) return url
  const base = API_BASE.replace(/\/api\/?$/, '')
  return url.startsWith('/') ? base + url : `${base}/${url}`
}

async function fetchHistory() {
  loadingHistory.value = true
  try {
    const res = await api.get('/admin/announcements/history', {
      params: { page: historyPage.value, pageSize: 20 }
    })
    history.value = res.data?.items || []
    historyTotal.value = res.data?.total || 0
  } catch {
    history.value = []
    historyTotal.value = 0
  } finally {
    loadingHistory.value = false
  }
}

onMounted(fetchHistory)

function clearMedia() {
  mediaFile.value = null
  mediaPreview.value = ''
  mediaUrl.value = ''
  if (mediaType.value !== 'text') mediaType.value = 'text'
  if (mediaInput.value) mediaInput.value.value = ''
}

function onMediaSelect(e) {
  const file = e.target?.files?.[0]
  if (!file) return
  const isImage = file.type?.startsWith('image/')
  const isVideo = file.type?.startsWith('video/')
  if (!isImage && !isVideo) {
    notify.warning('اختر صورة أو فيديو')
    return
  }
  if (isImage && file.size > 8 * 1024 * 1024) {
    notify.warning('الحد الأقصى للصورة 8 ميجابايت')
    return
  }
  if (isVideo && file.size > 80 * 1024 * 1024) {
    notify.warning('الحد الأقصى للفيديو 80 ميجابايت')
    return
  }
  mediaFile.value = file
  mediaType.value = isVideo ? 'video' : 'image'
  mediaPreview.value = URL.createObjectURL(file)
  mediaUrl.value = ''
}

async function uploadMediaIfNeeded() {
  if (!mediaFile.value) return mediaUrl.value || null
  uploading.value = true
  try {
    const fd = new FormData()
    fd.append('file', mediaFile.value)
    const res = await api.post('/admin/announcements/upload', fd, {
      headers: { 'Content-Type': 'multipart/form-data' },
      timeout: 120000
    })
    mediaUrl.value = res.data?.url || ''
    if (res.data?.type) mediaType.value = res.data.type
    return mediaUrl.value
  } catch (e) {
    notify.error(e.response?.data?.message || 'فشل رفع الملف')
    return null
  } finally {
    uploading.value = false
  }
}

async function sendAnnouncement() {
  const text = content.value?.trim() || ''

  if (mediaType.value === 'text' && !text) {
    notify.warning('نص الرسالة مطلوب')
    return
  }
  if (mediaType.value !== 'text' && !mediaFile.value && !mediaUrl.value) {
    notify.warning('أرفق صورة أو فيديو، أو اكتب نصاً فقط')
    return
  }

  sending.value = true
  success.value = false
  recipientsCount.value = 0
  totalUsers.value = 0
  try {
    let url = null
    if (mediaType.value !== 'text') {
      url = await uploadMediaIfNeeded()
      if (!url) {
        sending.value = false
        return
      }
    }

    const payload =
      mediaType.value === 'text'
        ? { content: text, type: 'text' }
        : { mediaUrl: url, type: mediaType.value, caption: text || null, content: url }

    const res = await api.post('/admin/announcements/broadcast', payload, { timeout: 300000 })
    success.value = true
    recipientsCount.value = res.data?.recipientsCount ?? 0
    totalUsers.value = res.data?.totalUsers ?? 0
    content.value = ''
    clearMedia()
    notify.success(res.data?.message || 'تم إرسال الرسالة الرسمية')
    historyPage.value = 1
    fetchHistory()
  } catch (err) {
    const msg = err.response?.data?.message || err.response?.data?.detail || 'فشل إرسال الرسالة الرسمية'
    notify.error(msg)
  } finally {
    sending.value = false
  }
}

function startEdit(item) {
  editing.value = item
  editContent.value = item.type === 'text' ? item.content : item.content
  editCaption.value = item.caption || ''
}

function cancelEdit() {
  editing.value = null
  editContent.value = ''
  editCaption.value = ''
}

async function saveEdit() {
  if (!editing.value) return
  editSaving.value = true
  try {
    const item = editing.value
    const payload =
      item.type === 'text'
        ? { content: editContent.value.trim(), type: 'text' }
        : { mediaUrl: editContent.value.trim(), content: editContent.value.trim(), type: item.type, caption: editCaption.value.trim() || null }
    if (item.type === 'text' && !payload.content) {
      notify.warning('النص مطلوب')
      return
    }
    const res = await api.put(`/admin/announcements/${item.id}`, payload)
    notify.success(res.data?.message || 'تم التحديث')
    cancelEdit()
    fetchHistory()
  } catch (e) {
    notify.error(e.response?.data?.message || 'فشل التعديل')
  } finally {
    editSaving.value = false
  }
}

async function removeBroadcast(item) {
  if (!confirm('حذف هذه الرسالة من عند جميع المستخدمين؟')) return
  deletingId.value = item.id
  try {
    const res = await api.delete(`/admin/announcements/${item.id}`)
    notify.success(res.data?.message || 'تم الحذف')
    if (editing.value?.id === item.id) cancelEdit()
    fetchHistory()
  } catch (e) {
    notify.error(e.response?.data?.message || 'فشل الحذف')
  } finally {
    deletingId.value = null
  }
}

function typeLabel(t) {
  return t === 'image' ? 'صورة' : t === 'video' ? 'فيديو' : 'نص'
}
</script>

<template>
  <div class="announcements-page">
    <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between mb-4 mb-sm-6 gap-2">
      <div>
        <div class="text-h5 font-weight-bold">رسائل نكس جات الرسمية</div>
        <div class="text-body-2 text-medium-emphasis">
          بث رسالة من حساب NexChat لكل المستخدمين — قراءة فقط مثل قنوات واتساب. يدعم نص / صورة / فيديو.
        </div>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4 mb-4">
      <div class="d-flex align-center gap-2 mb-4 pb-3 border-b">
        <v-icon color="primary">mdi-bullhorn</v-icon>
        <span class="text-h6 font-weight-bold">إرسال رسالة رسمية</span>
      </div>

      <v-alert type="info" variant="tonal" class="mb-4" density="comfortable">
        تظهر في محادثة «نكس جات / NexChat». لا يمكن للمستخدمين الرد أو حذف أو إخفاء المحادثة.
      </v-alert>

      <v-alert v-if="success" type="success" variant="tonal" class="mb-4" closable @click:close="success = false">
        تم الإرسال إلى {{ recipientsCount }} مستخدم
        <span v-if="totalUsers">(من أصل {{ totalUsers }})</span>
      </v-alert>

      <v-form @submit.prevent="sendAnnouncement">
        <v-textarea
          v-model="content"
          :label="mediaType === 'text' ? 'نص الرسالة' : 'تعليق / نص مرافق (اختياري)'"
          placeholder="اكتب الإعلان الرسمي هنا..."
          variant="outlined"
          rounded="lg"
          rows="4"
          maxlength="5000"
          counter="5000"
          auto-grow
          :disabled="sending || uploading"
          class="mb-3"
        />

        <input ref="mediaInput" type="file" accept="image/jpeg,image/png,image/gif,image/webp,video/*" class="d-none" @change="onMediaSelect" />

        <div
          class="upload-zone mb-3"
          :class="{ 'upload-zone--has': !!mediaPreview || !!mediaUrl }"
          @click="mediaInput?.click()"
        >
          <template v-if="mediaPreview || mediaUrl">
            <img v-if="mediaType === 'image'" :src="mediaPreview || fullUrl(mediaUrl)" alt="" class="upload-preview" />
            <video v-else-if="mediaType === 'video'" :src="mediaPreview || fullUrl(mediaUrl)" class="upload-preview" muted playsinline controls />
            <div class="d-flex justify-center gap-2 mt-2">
              <v-chip size="small" color="primary" variant="tonal">{{ typeLabel(mediaType) }}</v-chip>
              <v-btn size="small" variant="text" color="error" @click.stop="clearMedia">إزالة المرفق</v-btn>
            </div>
          </template>
          <template v-else>
            <v-icon icon="mdi-paperclip" size="36" color="primary" />
            <div class="text-body-2 mt-2">إرفاق صورة أو فيديو (اختياري)</div>
          </template>
          <v-progress-linear v-if="uploading" indeterminate color="primary" class="mt-2" />
        </div>

        <div class="d-flex justify-end">
          <v-btn
            type="submit"
            color="primary"
            size="large"
            rounded="lg"
            :loading="sending || uploading"
            :disabled="mediaType === 'text' ? !content.trim() : !(mediaFile || mediaUrl)"
            prepend-icon="mdi-send"
          >
            إرسال للجميع
          </v-btn>
        </div>
      </v-form>
    </v-card>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4">
      <div class="d-flex align-center justify-space-between mb-4 pb-3 border-b">
        <div class="d-flex align-center gap-2">
          <v-icon>mdi-history</v-icon>
          <span class="text-h6 font-weight-bold">الرسائل المرسلة</span>
        </div>
        <v-btn icon="mdi-refresh" variant="text" :loading="loadingHistory" @click="fetchHistory" />
      </div>

      <div v-if="loadingHistory" class="text-center py-8 text-medium-emphasis">جاري التحميل...</div>
      <div v-else-if="!history.length" class="text-center py-8 text-medium-emphasis">لا توجد رسائل بعد</div>

      <div v-for="item in history" :key="item.id" class="history-item mb-3">
        <div class="d-flex align-start justify-space-between gap-2">
          <div class="flex-grow-1">
            <div class="d-flex align-center gap-2 mb-1 flex-wrap">
              <v-chip size="x-small" variant="tonal" :color="item.type === 'text' ? 'primary' : item.type === 'image' ? 'success' : 'secondary'">
                {{ typeLabel(item.type) }}
              </v-chip>
              <span class="text-caption text-medium-emphasis">{{ formatIraqDateTime(item.sentAt) }}</span>
              <span class="text-caption text-medium-emphasis">• {{ item.recipientsCount }} مستلم</span>
              <span v-if="item.updatedAt" class="text-caption text-medium-emphasis">• معدّلة</span>
            </div>
            <div v-if="item.type === 'image'" class="mb-2">
              <img :src="fullUrl(item.content)" alt="" class="history-thumb" />
            </div>
            <div v-else-if="item.type === 'video'" class="mb-2">
              <video :src="fullUrl(item.content)" class="history-thumb" controls muted playsinline />
            </div>
            <div v-if="item.caption" class="text-body-2 mb-1">{{ item.caption }}</div>
            <div v-if="item.type === 'text'" class="text-body-1" style="white-space: pre-wrap">{{ item.content }}</div>
            <div v-else-if="!item.caption" class="text-caption text-medium-emphasis text-truncate">{{ item.content }}</div>
          </div>
          <div class="d-flex flex-column gap-1">
            <v-btn size="small" variant="tonal" color="primary" prepend-icon="mdi-pencil" @click="startEdit(item)">تعديل</v-btn>
            <v-btn size="small" variant="tonal" color="error" prepend-icon="mdi-delete" :loading="deletingId === item.id" @click="removeBroadcast(item)">حذف</v-btn>
          </div>
        </div>
      </div>

      <div v-if="historyTotal > 20" class="d-flex justify-center mt-4">
        <v-pagination
          v-model="historyPage"
          :length="Math.ceil(historyTotal / 20)"
          density="comfortable"
          @update:model-value="fetchHistory"
        />
      </div>
    </v-card>

    <v-dialog :model-value="!!editing" max-width="560" @update:model-value="(v) => !v && cancelEdit()">
      <v-card v-if="editing" rounded="xl" class="pa-4">
        <div class="text-h6 font-weight-bold mb-3">تعديل الرسالة</div>
        <v-textarea
          v-if="editing.type === 'text'"
          v-model="editContent"
          label="نص الرسالة"
          variant="outlined"
          rounded="lg"
          rows="5"
          auto-grow
        />
        <template v-else>
          <v-text-field v-model="editContent" label="رابط الوسائط" variant="outlined" rounded="lg" class="mb-2" />
          <v-textarea v-model="editCaption" label="التعليق" variant="outlined" rounded="lg" rows="3" auto-grow />
        </template>
        <div class="d-flex justify-end gap-2 mt-4">
          <v-btn variant="text" @click="cancelEdit">إلغاء</v-btn>
          <v-btn color="primary" :loading="editSaving" @click="saveEdit">حفظ</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.border-b {
  border-bottom: 1px solid rgba(var(--v-border-color), var(--v-border-opacity));
}
.upload-zone {
  border: 1.5px dashed rgba(var(--v-border-color), var(--v-border-opacity));
  border-radius: 16px;
  padding: 20px;
  text-align: center;
  cursor: pointer;
  background: rgba(var(--v-theme-surface-variant), 0.25);
}
.upload-zone--has {
  border-style: solid;
}
.upload-preview {
  max-width: 100%;
  max-height: 220px;
  border-radius: 12px;
  object-fit: contain;
}
.history-item {
  border: 1px solid rgba(var(--v-border-color), var(--v-border-opacity));
  border-radius: 14px;
  padding: 12px 14px;
}
.history-thumb {
  max-width: 220px;
  max-height: 140px;
  border-radius: 10px;
  object-fit: cover;
}
</style>
