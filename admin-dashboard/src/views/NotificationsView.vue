<script setup>
import { ref, watch } from 'vue'
import api from '../services/api'

const form = ref({
  title: '',
  body: '',
  imageUrl: ''
})
const imageFile = ref(null)
const imagePreview = ref('')
const imageInput = ref(null)
const sending = ref(false)
const success = ref(false)
const recipientsCount = ref(0)

const history = ref([])
const historyTotal = ref(0)
const historyPage = ref(1)
const historyPageSize = ref(15)
const historySearch = ref('')
const loadingHistory = ref(false)
const resendingId = ref(null)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

async function fetchHistory() {
  loadingHistory.value = true
  try {
    const res = await api.get('/admin/notifications/broadcast-history', {
      params: {
        page: historyPage.value,
        pageSize: historyPageSize.value,
        search: historySearch.value || undefined
      }
    })
    history.value = res.data.items || []
    historyTotal.value = res.data.total || 0
  } catch {
    history.value = []
    historyTotal.value = 0
  } finally {
    loadingHistory.value = false
  }
}

watch(historySearch, () => { historyPage.value = 1 })
watch([historyPage, historySearch], fetchHistory)

fetchHistory()

function onImageSelect(e) {
  const file = e.target?.files?.[0]
  if (!file) return
  const allowed = ['image/jpeg', 'image/png', 'image/gif', 'image/webp']
  if (!allowed.includes(file.type)) {
    alert('الصور المسموحة: JPEG, PNG, GIF, WebP')
    return
  }
  if (file.size > 5 * 1024 * 1024) {
    alert('الحد الأقصى 5 ميجابايت')
    return
  }
  imageFile.value = file
  imagePreview.value = URL.createObjectURL(file)
}

function clearImage() {
  imageFile.value = null
  imagePreview.value = ''
  form.value.imageUrl = ''
}

async function uploadImage() {
  if (!imageFile.value) return null
  const fd = new FormData()
  fd.append('file', imageFile.value)
  try {
    const res = await api.post('/admin/notifications/upload-image', fd, {
      headers: { 'Content-Type': 'multipart/form-data' }
    })
    return res.data?.url || null
  } catch (e) {
    alert(e.response?.data?.message || 'فشل رفع الصورة')
    return null
  }
}

async function sendBroadcast() {
  if (!form.value.title?.trim() || !form.value.body?.trim()) {
    alert('العنوان والنص مطلوبان')
    return
  }
  sending.value = true
  success.value = false
  recipientsCount.value = 0
  try {
    let imageUrl = form.value.imageUrl?.trim() || null
    if (imageFile.value && !imageUrl) {
      imageUrl = await uploadImage()
    }
    const res = await api.post('/admin/notifications/broadcast', {
      title: form.value.title.trim(),
      body: form.value.body.trim(),
      imageUrl: imageUrl || null
    })
    success.value = true
    recipientsCount.value = res.data?.recipientsCount ?? 0
    form.value = { title: '', body: '', imageUrl: '' }
    clearImage()
    fetchHistory()
  } catch (err) {
    recipientsCount.value = err.response?.data?.recipientsCount ?? 0
    alert(err.response?.data?.message || 'فشل إرسال الإشعار')
  } finally {
    sending.value = false
  }
}

async function resend(item) {
  resendingId.value = item.id
  try {
    const res = await api.post(`/admin/notifications/broadcast/${item.id}/resend`)
    alert(`تم إعادة الإرسال بنجاح إلى ${res.data?.recipientsCount ?? 0} جهاز`)
    fetchHistory()
  } catch (e) {
    alert(e.response?.data?.message || 'فشل إعادة الإرسال')
  } finally {
    resendingId.value = null
  }
}

function fullImageUrl(url) {
  if (!url) return ''
  if (url.startsWith('http')) return url
  const base = API_BASE.replace('/api', '')
  return url.startsWith('/') ? base + url : base + '/' + url
}

function formatDate(dt) {
  return new Date(dt).toLocaleString('ar-SA', {
    dateStyle: 'short',
    timeStyle: 'short'
  })
}
</script>

<template>
  <div class="notifications-page">
    <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between mb-4 mb-sm-6 gap-2">
      <div>
        <div class="text-h5 font-weight-bold">إشعارات عامة</div>
        <div class="text-body-2 text-medium-emphasis">
          إرسال إشعار push لجميع المستخدمين المشتركين
        </div>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4 mb-4 mb-sm-6">
      <div class="d-flex align-center gap-2 mb-4 pb-3 border-b">
        <v-icon>mdi-bell-ring</v-icon>
        <span class="text-h6 font-weight-bold">بث إشعار جديد</span>
      </div>
      <div>
        <v-alert
          v-if="success"
          type="success"
          variant="tonal"
          class="mb-4"
          closable
        >
          تم إرسال الإشعار بنجاح إلى {{ recipientsCount }} جهاز
        </v-alert>

        <v-form @submit.prevent="sendBroadcast">
          <v-text-field
            v-model="form.title"
            label="عنوان الإشعار"
            placeholder="مثال: تحديث جديد"
            maxlength="100"
            counter="100"
            variant="outlined"
            density="compact"
            rounded="lg"
            class="mb-3"
            hide-details
            :disabled="sending"
          />
          <v-textarea
            v-model="form.body"
            label="نص الإشعار"
            placeholder="اكتب محتوى الإشعار..."
            maxlength="500"
            counter="500"
            variant="outlined"
            density="compact"
            rounded="lg"
            rows="4"
            class="mb-3"
            hide-details
            :disabled="sending"
          />

          <div class="mb-4">
            <div class="text-body-2 text-medium-emphasis mb-2">صورة الإشعار (اختياري)</div>
            <div class="d-flex align-center gap-3 flex-wrap">
              <v-btn
                variant="outlined"
                size="small"
                prepend-icon="mdi-upload"
                :disabled="sending"
                @click="imageInput?.click()"
              >
                رفع صورة
              </v-btn>
              <input
                ref="imageInput"
                type="file"
                accept="image/jpeg,image/png,image/gif,image/webp"
                style="display:none"
                @change="onImageSelect"
              />
              <v-btn
                v-if="imagePreview || form.imageUrl"
                variant="text"
                size="small"
                color="error"
                @click="clearImage"
              >
                إزالة
              </v-btn>
              <div v-if="imagePreview" class="image-preview-wrap">
                <img :src="imagePreview" alt="معاينة" class="image-preview" />
              </div>
              <div v-else-if="form.imageUrl" class="image-preview-wrap">
                <img :src="fullImageUrl(form.imageUrl)" alt="صورة" class="image-preview" />
              </div>
            </div>
          </div>

          <v-btn
            type="submit"
            color="primary"
            size="default"
            rounded="lg"
            prepend-icon="mdi-send"
            :loading="sending"
          >
            إرسال للجميع
          </v-btn>
        </v-form>
      </div>
    </v-card>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4 table-card">
      <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between gap-3 mb-4 pb-3 border-b">
        <div class="d-flex align-center gap-2">
          <v-icon>mdi-history</v-icon>
          <span class="text-h6 font-weight-bold">سجل الإشعارات المرسلة</span>
        </div>
        <v-text-field
          v-model="historySearch"
          placeholder="بحث..."
          prepend-inner-icon="mdi-magnify"
          variant="outlined"
          density="compact"
          rounded="lg"
          hide-details
          clearable
          class="search-field"
          bg-color="rgba(255,255,255,0.04)"
          style="max-width: 240px"
        />
      </div>
      <div>
        <div v-if="loadingHistory" class="d-flex justify-center py-8">
          <v-progress-circular indeterminate color="primary" size="40" />
        </div>
        <div v-else-if="history.length === 0" class="empty-list pa-6 text-center">
          <v-icon size="48" color="medium-emphasis">mdi-bell-off-outline</v-icon>
          <div class="text-body-2 text-medium-emphasis mt-2">لا توجد إشعارات مرسلة</div>
        </div>
        <div v-else>
          <div
            v-for="item in history"
            :key="item.id"
            class="history-item"
          >
            <div class="history-item-content">
              <div class="d-flex align-start gap-3">
                <img
                  v-if="item.imageUrl"
                  :src="fullImageUrl(item.imageUrl)"
                  alt=""
                  class="history-item-image"
                />
                <div class="flex-grow-1 min-width-0">
                  <div class="history-item-title">{{ item.title }}</div>
                  <div class="history-item-body">{{ item.body }}</div>
                  <div class="history-item-meta">
                    {{ item.recipientsCount }} مستقبل · {{ formatDate(item.sentAt) }}
                  </div>
                </div>
              </div>
            </div>
            <v-btn
              color="primary"
              variant="tonal"
              size="small"
              :loading="resendingId === item.id"
              @click="resend(item)"
            >
              إعادة الإرسال
            </v-btn>
          </div>
          <div v-if="historyTotal > historyPageSize" class="d-flex justify-center pt-4">
            <v-pagination
              v-model="historyPage"
              :length="Math.ceil(historyTotal / historyPageSize)"
              :total-visible="5"
              density="compact"
              size="small"
            />
          </div>
        </div>
      </div>
    </v-card>
  </div>
</template>

<style scoped>
.notifications-page {
  width: 100%;
}

.border-b {
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.image-preview-wrap {
  width: 80px;
  height: 80px;
  border-radius: 8px;
  overflow: hidden;
  border: 1px solid rgba(255, 255, 255, 0.1);
}
.image-preview {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.history-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 14px 16px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}
.history-item:last-of-type {
  border-bottom: none;
}
.history-item-content {
  flex: 1;
  min-width: 0;
}
.history-item-image {
  width: 48px;
  height: 48px;
  border-radius: 8px;
  object-fit: cover;
  flex-shrink: 0;
}
.history-item-title {
  font-weight: 600;
  font-size: 14px;
  margin-bottom: 4px;
}
.history-item-body {
  font-size: 13px;
  color: rgba(255, 255, 255, 0.7);
  line-height: 1.4;
  overflow: hidden;
  text-overflow: ellipsis;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
}
.history-item-meta {
  font-size: 12px;
  color: rgba(255, 255, 255, 0.5);
  margin-top: 6px;
}

.empty-list {
  flex: 1;
  min-height: 120px;
}
</style>
