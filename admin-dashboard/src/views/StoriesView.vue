<script setup>
import { ref, watch, onMounted } from 'vue'
import api from '../services/api'

const stories = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(20)
const search = ref('')
const statusFilter = ref('all')
const loading = ref(false)
const deleteDialog = ref(false)
const deleteTarget = ref(null)
const deleteLoading = ref(false)
const previewItem = ref(null)
const previewDialog = ref(false)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

const statusOptions = [
  { title: 'الكل', value: 'all' },
  { title: 'نشطة', value: 'active' },
  { title: 'منتهية', value: 'expired' }
]

const headers = [
  { title: 'معاينة', key: 'preview', sortable: false, width: 88 },
  { title: 'الناشر', key: 'userName', sortable: false },
  { title: 'النوع', key: 'mediaType', sortable: false },
  { title: 'النص', key: 'caption', sortable: false },
  { title: 'المشاهدات', key: 'viewCount', sortable: false, align: 'center' },
  { title: 'الحالة', key: 'isActive', sortable: false, align: 'center' },
  { title: 'تاريخ النشر', key: 'createdAt', sortable: false },
  { title: 'تنتهي', key: 'expiresAt', sortable: false },
  { title: 'إجراءات', key: 'actions', sortable: false, align: 'center' }
]

const mediaTypeLabel = { image: 'صورة', video: 'فيديو', text: 'نص' }
const mediaTypeColor = { image: 'primary', video: 'secondary', text: 'info' }

function fullMediaUrl(url) {
  if (!url) return ''
  if (url.startsWith('http')) return url
  const base = API_BASE.replace('/api', '')
  return url.startsWith('/') ? base + url : base + '/' + url
}

async function fetchStories() {
  loading.value = true
  try {
    const res = await api.get('/admin/stories', {
      params: {
        page: page.value,
        pageSize: pageSize.value,
        search: search.value?.trim() || undefined,
        status: statusFilter.value
      }
    })
    stories.value = res.data.items
    total.value = res.data.total
  } catch {
    stories.value = []
    total.value = 0
  } finally {
    loading.value = false
  }
}

function formatDate(date) {
  if (!date) return '—'
  return new Date(date).toLocaleString('ar', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}

function captionPreview(caption) {
  if (!caption) return '—'
  return caption.length > 60 ? caption.slice(0, 60) + '…' : caption
}

function openPreview(item) {
  previewItem.value = item
  previewDialog.value = true
}

function confirmDelete(item) {
  deleteTarget.value = item
  deleteDialog.value = true
}

async function executeDelete() {
  if (!deleteTarget.value) return
  deleteLoading.value = true
  try {
    await api.delete(`/admin/stories/${deleteTarget.value.id}`)
    deleteDialog.value = false
    deleteTarget.value = null
    fetchStories()
  } catch (e) {
    alert(e.response?.data?.message || 'فشل الحذف')
  } finally {
    deleteLoading.value = false
  }
}

let searchTimeout
function onSearch() {
  clearTimeout(searchTimeout)
  searchTimeout = setTimeout(() => {
    page.value = 1
    fetchStories()
  }, 400)
}

watch(statusFilter, () => {
  page.value = 1
  fetchStories()
})

watch(page, fetchStories)
onMounted(fetchStories)
</script>

<template>
  <div>
    <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between mb-4 mb-sm-6 gap-2">
      <div>
        <div class="text-h5 font-weight-bold">الستوريات</div>
        <div class="text-body-2 text-medium-emphasis">
          {{ total.toLocaleString() }} ستوري
        </div>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4 stories-card">
      <div class="d-flex flex-column flex-sm-row gap-3 mb-4 flex-wrap">
        <v-text-field
          v-model="search"
          placeholder="بحث بالاسم أو النص..."
          prepend-inner-icon="mdi-magnify"
          variant="outlined"
          density="compact"
          rounded="lg"
          hide-details
          clearable
          bg-color="rgba(255,255,255,0.04)"
          style="max-width: 280px;"
          @input="onSearch"
        />
        <v-select
          v-model="statusFilter"
          :items="statusOptions"
          item-title="title"
          item-value="value"
          label="الحالة"
          variant="outlined"
          density="compact"
          rounded="lg"
          hide-details
          bg-color="rgba(255,255,255,0.04)"
          style="max-width: 160px;"
        />
        <v-spacer />
        <v-btn variant="tonal" color="primary" prepend-icon="mdi-refresh" :loading="loading" @click="fetchStories">
          تحديث
        </v-btn>
      </div>

      <v-data-table
        :headers="headers"
        :items="stories"
        :loading="loading"
        :items-per-page="pageSize"
        hide-default-footer
        class="stories-table"
        no-data-text="لا توجد ستوريات"
        loading-text="جاري التحميل..."
      >
        <template #item.preview="{ item }">
          <button type="button" class="preview-thumb-btn" @click="openPreview(item)">
            <v-img
              v-if="item.mediaType === 'image' && item.mediaUrl"
              :src="fullMediaUrl(item.mediaUrl)"
              width="56"
              height="56"
              cover
              rounded="lg"
            />
            <div
              v-else-if="item.mediaType === 'video' && item.mediaUrl"
              class="preview-thumb preview-thumb--video"
            >
              <v-icon icon="mdi-play-circle" size="28" color="white" />
            </div>
            <div
              v-else-if="item.mediaType === 'text'"
              class="preview-thumb preview-thumb--text"
              :style="{ background: item.backgroundColor || 'linear-gradient(135deg,#6c63ff,#ff6584)' }"
            >
              <span class="text-preview">{{ (item.caption || 'نص')[0] }}</span>
            </div>
            <div v-else class="preview-thumb preview-thumb--empty">
              <v-icon icon="mdi-image-off-outline" size="22" />
            </div>
          </button>
        </template>

        <template #item.userName="{ item }">
          <div class="d-flex align-center gap-2">
            <v-avatar v-if="item.userAvatar" size="28">
              <v-img :src="fullMediaUrl(item.userAvatar)" />
            </v-avatar>
            <v-avatar v-else size="28" color="primary" variant="tonal">
              <span class="text-caption">{{ item.userName?.[0] || '?' }}</span>
            </v-avatar>
            <span class="font-weight-medium">{{ item.userName }}</span>
          </div>
        </template>

        <template #item.mediaType="{ item }">
          <v-chip size="small" :color="mediaTypeColor[item.mediaType] || 'default'" variant="tonal">
            {{ mediaTypeLabel[item.mediaType] || item.mediaType }}
          </v-chip>
        </template>

        <template #item.caption="{ item }">
          <span class="text-caption text-medium-emphasis">{{ captionPreview(item.caption) }}</span>
        </template>

        <template #item.viewCount="{ item }">
          <v-chip size="small" variant="outlined" prepend-icon="mdi-eye">
            {{ item.viewCount }}
          </v-chip>
        </template>

        <template #item.isActive="{ item }">
          <v-chip size="small" :color="item.isActive ? 'success' : 'default'" variant="tonal">
            {{ item.isActive ? 'نشطة' : 'منتهية' }}
          </v-chip>
        </template>

        <template #item.createdAt="{ item }">
          <span class="text-caption">{{ formatDate(item.createdAt) }}</span>
        </template>

        <template #item.expiresAt="{ item }">
          <span class="text-caption">{{ formatDate(item.expiresAt) }}</span>
        </template>

        <template #item.actions="{ item }">
          <div class="d-flex justify-center gap-1">
            <v-btn icon size="small" variant="text" @click="openPreview(item)">
              <v-icon icon="mdi-eye" />
            </v-btn>
            <v-btn icon size="small" variant="text" color="error" @click="confirmDelete(item)">
              <v-icon icon="mdi-delete" />
            </v-btn>
          </div>
        </template>

        <template #bottom>
          <div v-if="total > pageSize" class="d-flex justify-center pt-4">
            <v-pagination
              v-model="page"
              :length="Math.ceil(total / pageSize)"
              active-color="primary"
              size="small"
            />
          </div>
        </template>
      </v-data-table>
    </v-card>

    <v-dialog v-model="previewDialog" max-width="480">
      <v-card v-if="previewItem" rounded="xl" class="pa-4">
        <div class="d-flex align-center justify-space-between mb-3">
          <div class="font-weight-bold">{{ previewItem.userName }}</div>
          <v-btn icon variant="text" @click="previewDialog = false">
            <v-icon icon="mdi-close" />
          </v-btn>
        </div>
        <div class="preview-dialog-media">
          <img
            v-if="previewItem.mediaType === 'image' && previewItem.mediaUrl"
            :src="fullMediaUrl(previewItem.mediaUrl)"
            alt=""
            class="preview-dialog-img"
          />
          <video
            v-else-if="previewItem.mediaType === 'video' && previewItem.mediaUrl"
            :src="fullMediaUrl(previewItem.mediaUrl)"
            controls
            playsinline
            class="preview-dialog-video"
          />
          <div
            v-else-if="previewItem.mediaType === 'text'"
            class="preview-dialog-text"
            :style="{ background: previewItem.backgroundColor || 'linear-gradient(135deg,#6c63ff,#ff6584)' }"
          >
            {{ previewItem.caption || '—' }}
          </div>
        </div>
        <div v-if="previewItem.caption && previewItem.mediaType !== 'text'" class="text-body-2 mt-3">
          {{ previewItem.caption }}
        </div>
        <div class="text-caption text-medium-emphasis mt-2">
          {{ previewItem.viewCount }} مشاهدة · {{ previewItem.isActive ? 'نشطة' : 'منتهية' }}
        </div>
      </v-card>
    </v-dialog>

    <v-dialog v-model="deleteDialog" max-width="400">
      <v-card rounded="xl" class="pa-4">
        <div class="text-h6 mb-2">حذف الستوري؟</div>
        <p class="text-body-2 text-medium-emphasis mb-4">
          سيتم حذف الستوري نهائياً لـ «{{ deleteTarget?.userName }}» وإشعار المستخدمين المعنيين.
        </p>
        <div class="d-flex justify-end gap-2">
          <v-btn variant="text" @click="deleteDialog = false">إلغاء</v-btn>
          <v-btn color="error" :loading="deleteLoading" @click="executeDelete">حذف</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.stories-card {
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.stories-table :deep(.v-data-table__td) {
  padding: 10px 12px;
  vertical-align: middle;
}

.preview-thumb-btn {
  border: none;
  padding: 0;
  background: none;
  cursor: pointer;
  border-radius: 8px;
  overflow: hidden;
}

.preview-thumb {
  width: 56px;
  height: 56px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.preview-thumb--video {
  background: #1a1a2e;
}

.preview-thumb--text {
  color: #fff;
  font-weight: 700;
  font-size: 18px;
}

.preview-thumb--empty {
  background: rgba(255, 255, 255, 0.06);
  color: rgba(255, 255, 255, 0.4);
}

.text-preview {
  text-transform: uppercase;
}

.preview-dialog-media {
  border-radius: 12px;
  overflow: hidden;
  background: #000;
  min-height: 120px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.preview-dialog-img,
.preview-dialog-video {
  max-width: 100%;
  max-height: 60vh;
  display: block;
  margin: 0 auto;
}

.preview-dialog-text {
  width: 100%;
  min-height: 160px;
  padding: 24px;
  color: #fff;
  font-size: 18px;
  font-weight: 600;
  text-align: center;
  display: flex;
  align-items: center;
  justify-content: center;
  line-height: 1.5;
}
</style>
