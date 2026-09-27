<script setup>
import { ref, watch, onMounted, computed } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'
import { fullMediaUrl } from '../utils/media'
import UserCell from '../components/UserCell.vue'
import { formatIraqDate, formatIraqDateTime } from '../utils/iraqTime'

const stories = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(20)
const search = ref('')
const statusFilter = ref('all')
const scopeFilter = ref('all')
const loading = ref(false)
const deleteDialog = ref(false)
const deleteTarget = ref(null)
const deleteLoading = ref(false)
const previewItem = ref(null)
const previewDialog = ref(false)

const engagementDialog = ref(false)
const engagementLoading = ref(false)
const engagementItem = ref(null)
const engagementPeople = ref([])
const engagementTab = ref('all') // all | liked | viewed

const composeDialog = ref(false)
const composeLoading = ref(false)
const uploading = ref(false)
const fileInput = ref(null)
const form = ref({
  mediaType: 'image',
  mediaUrl: '',
  caption: '',
  backgroundColor: 'linear-gradient(135deg,#2E86FB,#0EA5E9)',
  sendPush: false,
  videoDurationSeconds: null
})

const statusOptions = [
  { title: 'الكل', value: 'all' },
  { title: 'نشطة', value: 'active' },
  { title: 'منتهية', value: 'expired' }
]

const scopeOptions = [
  { title: 'الكل', value: 'all' },
  { title: 'رسمي', value: 'official' },
  { title: 'مستخدمين', value: 'user' }
]

const mediaTypeOptions = [
  { title: 'صورة', value: 'image' },
  { title: 'فيديو', value: 'video' },
  { title: 'نص', value: 'text' }
]

const bgPresets = [
  'linear-gradient(135deg,#2E86FB,#0EA5E9)',
  'linear-gradient(135deg,#7C3AED,#EC4899)',
  'linear-gradient(135deg,#059669,#14B8A6)',
  'linear-gradient(135deg,#EA580C,#F59E0B)',
  'linear-gradient(135deg,#0F172A,#334155)'
]

const headers = [
  { title: 'معاينة', key: 'preview', sortable: false, width: 88 },
  { title: 'الناشر', key: 'userName', sortable: false, minWidth: '160px' },
  { title: 'النوع', key: 'mediaType', sortable: false },
  { title: 'النص', key: 'caption', sortable: false },
  { title: 'المشاهدات', key: 'viewCount', sortable: false, align: 'center' },
  { title: 'الإعجابات', key: 'likeCount', sortable: false, align: 'center' },
  { title: 'الحالة', key: 'isActive', sortable: false, align: 'center' },
  { title: 'تاريخ النشر', key: 'createdAt', sortable: false },
  { title: 'تنتهي', key: 'expiresAt', sortable: false },
  { title: 'إجراءات', key: 'actions', sortable: false, align: 'center' }
]

const mediaTypeLabel = { image: 'صورة', video: 'فيديو', text: 'نص' }
const mediaTypeColor = { image: 'primary', video: 'secondary', text: 'info' }

async function fetchStories() {
  loading.value = true
  try {
    const res = await api.get('/admin/stories', {
      params: {
        page: page.value,
        pageSize: pageSize.value,
        search: search.value?.trim() || undefined,
        status: statusFilter.value,
        scope: scopeFilter.value
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

function formatDate(dt) {
  return formatIraqDate(dt)
}

function formatDateTime(dt) {
  return formatIraqDateTime(dt)
}

function captionPreview(caption) {
  if (!caption) return '—'
  return caption.length > 60 ? caption.slice(0, 60) + '…' : caption
}

const filteredEngagementPeople = computed(() => {
  const list = engagementPeople.value || []
  if (engagementTab.value === 'liked') return list.filter((p) => p.liked)
  if (engagementTab.value === 'viewed') return list.filter((p) => !!p.viewedAt)
  return list
})

async function openEngagement(item, tab = 'all') {
  engagementItem.value = item
  engagementTab.value = tab
  engagementDialog.value = true
  engagementLoading.value = true
  engagementPeople.value = []
  try {
    const res = await api.get(`/admin/stories/${item.id}/engagement`)
    engagementPeople.value = res.data.people || []
    if (engagementItem.value) {
      engagementItem.value = {
        ...engagementItem.value,
        viewCount: res.data.viewCount ?? engagementItem.value.viewCount,
        likeCount: res.data.likeCount ?? engagementItem.value.likeCount
      }
    }
  } catch {
    notify.error('تعذر تحميل المشاهدات والإعجابات')
    engagementPeople.value = []
  } finally {
    engagementLoading.value = false
  }
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
    notify.error(e.response?.data?.message || 'فشل الحذف')
  } finally {
    deleteLoading.value = false
  }
}

function openCompose() {
  form.value = {
    mediaType: 'image',
    mediaUrl: '',
    caption: '',
    backgroundColor: bgPresets[0],
    sendPush: false,
    videoDurationSeconds: null
  }
  composeDialog.value = true
}

function triggerUpload() {
  fileInput.value?.click()
}

async function onFileChange(e) {
  const file = e.target?.files?.[0]
  if (!file) return
  uploading.value = true
  try {
    const fd = new FormData()
    fd.append('file', file)
    const endpoint = form.value.mediaType === 'video'
      ? '/media/upload-story-video'
      : '/media/upload'
    const res = await api.post(endpoint, fd, {
      headers: { 'Content-Type': 'multipart/form-data' }
    })
    form.value.mediaUrl = res.data.url
    if (form.value.mediaType === 'video' && file.type?.startsWith('video/')) {
      // duration optional — client may leave null
      form.value.videoDurationSeconds = null
    }
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل رفع الملف')
  } finally {
    uploading.value = false
    e.target.value = ''
  }
}

watch(() => form.value.mediaType, () => {
  form.value.mediaUrl = ''
})

async function publishStory() {
  const mediaType = form.value.mediaType
  if (mediaType !== 'text' && !form.value.mediaUrl) {
    notify.warning(mediaType === 'video' ? 'يرجى رفع فيديو' : 'يرجى رفع صورة')
    return
  }
  if (mediaType === 'text' && !form.value.caption?.trim()) {
    notify.warning('أدخل نص الستوري')
    return
  }

  composeLoading.value = true
  try {
    await api.post('/admin/stories', {
      mediaUrl: mediaType === 'text' ? null : form.value.mediaUrl,
      mediaType,
      caption: form.value.caption?.trim() || null,
      backgroundColor: mediaType === 'text' ? form.value.backgroundColor : null,
      videoDurationSeconds: mediaType === 'video' ? form.value.videoDurationSeconds : null,
      sendPush: !!form.value.sendPush
    })
    composeDialog.value = false
    notify.success('تم نشر الستوري الرسمي لكل المستخدمين')
    page.value = 1
    fetchStories()
  } catch (e) {
    notify.error(e.response?.data?.message || 'فشل النشر')
  } finally {
    composeLoading.value = false
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

watch(scopeFilter, () => {
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
          {{ total.toLocaleString() }} ستوري · انشر ستوري رسمي يظهر للجميع
        </div>
      </div>
      <v-btn color="primary" rounded="lg" prepend-icon="mdi-plus" @click="openCompose">
        إضافة ستوري رسمي
      </v-btn>
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
          bg-color="#F8FAFC"
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
          bg-color="#F8FAFC"
          style="max-width: 160px;"
        />
        <v-select
          v-model="scopeFilter"
          :items="scopeOptions"
          item-title="title"
          item-value="value"
          label="النطاق"
          variant="outlined"
          density="compact"
          rounded="lg"
          hide-details
          bg-color="#F8FAFC"
          style="max-width: 160px;"
        />
        <v-spacer />
        <div class="page-actions">
          <v-btn variant="tonal" color="primary" prepend-icon="mdi-refresh" size="small" :loading="loading" @click="fetchStories">
            تحديث
          </v-btn>
        </div>
      </div>

      <v-data-table
        :headers="headers"
        :items="stories"
        :loading="loading"
        :items-per-page="-1"
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
              :style="{ background: item.backgroundColor || 'linear-gradient(135deg,#2E86FB,#0EA5E9)' }"
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
            <UserCell :name="item.userName" :avatar="item.userAvatar" :size="36" />
            <v-chip v-if="item.isBroadcast" size="x-small" color="primary" variant="flat" prepend-icon="mdi-check-decagram">
              رسمي
            </v-chip>
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
          <v-chip
            size="small"
            variant="outlined"
            prepend-icon="mdi-eye"
            class="engagement-chip"
            @click="openEngagement(item, 'viewed')"
          >
            {{ item.viewCount ?? 0 }}
          </v-chip>
        </template>

        <template #item.likeCount="{ item }">
          <v-chip
            size="small"
            variant="outlined"
            color="error"
            prepend-icon="mdi-heart"
            class="engagement-chip"
            @click="openEngagement(item, 'liked')"
          >
            {{ item.likeCount ?? 0 }}
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
          <div class="action-btns">
            <v-btn
              icon="mdi-eye"
              size="small"
              variant="tonal"
              color="primary"
              title="معاينة"
              @click="openPreview(item)"
            />
            <v-btn
              icon="mdi-delete"
              size="small"
              variant="tonal"
              color="error"
              title="حذف"
              @click="confirmDelete(item)"
            />
          </div>
        </template>
      </v-data-table>
      <div v-if="total > 0" class="pagination-bar">
        <v-pagination
          v-model="page"
          :length="Math.max(1, Math.ceil(total / pageSize))"
          :total-visible="7"
          density="comfortable"
          active-color="primary"
          @update:model-value="fetchStories"
        />
      </div>
    </v-card>

    <!-- Compose official story -->
    <v-dialog v-model="composeDialog" max-width="520" persistent>
      <v-card rounded="xl" class="pa-4">
        <div class="d-flex align-center justify-space-between mb-3">
          <div>
            <div class="text-h6 font-weight-bold">ستوري رسمي</div>
            <div class="text-caption text-medium-emphasis">يظهر لكل المستخدمين لمدة 24 ساعة باسم NexChat</div>
          </div>
          <v-btn icon variant="text" :disabled="composeLoading" @click="composeDialog = false">
            <v-icon icon="mdi-close" />
          </v-btn>
        </div>

        <v-select
          v-model="form.mediaType"
          :items="mediaTypeOptions"
          item-title="title"
          item-value="value"
          label="نوع الستوري"
          variant="outlined"
          density="comfortable"
          rounded="lg"
          class="mb-3"
        />

        <template v-if="form.mediaType !== 'text'">
          <input
            ref="fileInput"
            type="file"
            class="d-none"
            :accept="form.mediaType === 'video' ? 'video/mp4,video/webm,video/quicktime' : 'image/jpeg,image/png,image/webp,image/gif'"
            @change="onFileChange"
          />
          <div
            class="upload-zone mb-3"
            :class="{ 'upload-zone--has': !!form.mediaUrl }"
            @click="triggerUpload"
          >
            <template v-if="form.mediaUrl && form.mediaType === 'image'">
              <img :src="fullMediaUrl(form.mediaUrl)" alt="" class="upload-preview" />
            </template>
            <template v-else-if="form.mediaUrl && form.mediaType === 'video'">
              <video :src="fullMediaUrl(form.mediaUrl)" class="upload-preview" muted playsinline />
            </template>
            <template v-else>
              <v-icon :icon="form.mediaType === 'video' ? 'mdi-video-plus' : 'mdi-image-plus'" size="36" color="primary" />
              <div class="text-body-2 mt-2">
                {{ uploading ? 'جاري الرفع...' : (form.mediaType === 'video' ? 'اختر فيديو' : 'اختر صورة') }}
              </div>
            </template>
            <v-progress-linear v-if="uploading" indeterminate color="primary" class="mt-2" />
          </div>
        </template>

        <v-textarea
          v-model="form.caption"
          :label="form.mediaType === 'text' ? 'نص الستوري' : 'تعليق (اختياري)'"
          variant="outlined"
          density="comfortable"
          rounded="lg"
          rows="3"
          auto-grow
          class="mb-3"
        />

        <div v-if="form.mediaType === 'text'" class="mb-3">
          <div class="text-caption text-medium-emphasis mb-2">خلفية النص</div>
          <div class="d-flex gap-2 flex-wrap">
            <button
              v-for="bg in bgPresets"
              :key="bg"
              type="button"
              class="bg-swatch"
              :class="{ 'bg-swatch--active': form.backgroundColor === bg }"
              :style="{ background: bg }"
              @click="form.backgroundColor = bg"
            />
          </div>
          <div class="text-preview-card mt-3" :style="{ background: form.backgroundColor }">
            {{ form.caption?.trim() || 'معاينة النص...' }}
          </div>
        </div>

        <v-switch
          v-model="form.sendPush"
          color="primary"
          density="compact"
          hide-details
          label="إرسال إشعار Push للجميع"
          class="mb-4"
        />

        <div class="d-flex justify-end gap-2">
          <v-btn variant="text" :disabled="composeLoading" @click="composeDialog = false">إلغاء</v-btn>
          <v-btn color="primary" rounded="lg" :loading="composeLoading || uploading" @click="publishStory">
            نشر للجميع
          </v-btn>
        </div>
      </v-card>
    </v-dialog>

    <v-dialog v-model="previewDialog" max-width="480">
      <v-card v-if="previewItem" rounded="xl" class="pa-4">
        <div class="d-flex align-center justify-space-between mb-3">
          <div class="d-flex align-center gap-2">
            <div class="font-weight-bold">{{ previewItem.userName }}</div>
            <v-chip v-if="previewItem.isBroadcast" size="x-small" color="primary" variant="flat">رسمي</v-chip>
          </div>
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
            :style="{ background: previewItem.backgroundColor || 'linear-gradient(135deg,#2E86FB,#0EA5E9)' }"
          >
            {{ previewItem.caption || '—' }}
          </div>
        </div>
        <div v-if="previewItem.caption && previewItem.mediaType !== 'text'" class="text-body-2 mt-3">
          {{ previewItem.caption }}
        </div>
        <div class="text-caption text-medium-emphasis mt-2 d-flex align-center gap-3 flex-wrap">
          <button type="button" class="engagement-link" @click="openEngagement(previewItem, 'viewed')">
            <v-icon icon="mdi-eye" size="16" start />
            {{ previewItem.viewCount ?? 0 }} مشاهدة
          </button>
          <button type="button" class="engagement-link" @click="openEngagement(previewItem, 'liked')">
            <v-icon icon="mdi-heart" size="16" start color="error" />
            {{ previewItem.likeCount ?? 0 }} إعجاب
          </button>
          <span>· {{ previewItem.isActive ? 'نشطة' : 'منتهية' }}</span>
        </div>
      </v-card>
    </v-dialog>

    <v-dialog v-model="engagementDialog" max-width="460">
      <v-card rounded="xl" class="pa-4">
        <div class="d-flex align-center justify-space-between mb-2">
          <div>
            <div class="text-h6 font-weight-bold">المشاهدات والإعجابات</div>
            <div class="text-caption text-medium-emphasis">
              {{ engagementItem?.userName || '—' }}
              · {{ engagementItem?.viewCount ?? 0 }} مشاهدة
              · {{ engagementItem?.likeCount ?? 0 }} إعجاب
            </div>
          </div>
          <v-btn icon variant="text" @click="engagementDialog = false">
            <v-icon icon="mdi-close" />
          </v-btn>
        </div>

        <div class="d-flex gap-2 mb-3 flex-wrap">
          <v-chip
            size="small"
            :variant="engagementTab === 'all' ? 'flat' : 'tonal'"
            :color="engagementTab === 'all' ? 'primary' : undefined"
            @click="engagementTab = 'all'"
          >
            الكل ({{ engagementPeople.length }})
          </v-chip>
          <v-chip
            size="small"
            :variant="engagementTab === 'viewed' ? 'flat' : 'tonal'"
            :color="engagementTab === 'viewed' ? 'primary' : undefined"
            @click="engagementTab = 'viewed'"
          >
            شاهدوا ({{ engagementPeople.filter((p) => !!p.viewedAt).length }})
          </v-chip>
          <v-chip
            size="small"
            :variant="engagementTab === 'liked' ? 'flat' : 'tonal'"
            :color="engagementTab === 'liked' ? 'error' : undefined"
            @click="engagementTab = 'liked'"
          >
            أعجبوا ({{ engagementPeople.filter((p) => p.liked).length }})
          </v-chip>
        </div>

        <div v-if="engagementLoading" class="py-8 text-center">
          <v-progress-circular indeterminate color="primary" size="32" />
        </div>
        <div v-else-if="!filteredEngagementPeople.length" class="py-8 text-center text-medium-emphasis text-body-2">
          لا يوجد أحد بعد
        </div>
        <div v-else class="engagement-list">
          <div
            v-for="person in filteredEngagementPeople"
            :key="person.userId"
            class="engagement-row"
          >
            <UserCell
              :name="person.name"
              :avatar="person.avatar"
              :size="36"
              :subtitle="person.viewedAt ? formatDateTime(person.viewedAt) : 'بدون وقت مشاهدة'"
            />
            <v-icon
              v-if="person.liked"
              icon="mdi-heart"
              color="error"
              size="18"
              title="أعجب"
            />
          </div>
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
  background: #FFFFFF;
  border: 1px solid rgba(15, 23, 42, 0.08);
}

.preview-thumb-btn {
  border: none;
  background: transparent;
  padding: 0;
  cursor: pointer;
}

.preview-thumb {
  width: 56px;
  height: 56px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}

.preview-thumb--video {
  background: linear-gradient(135deg, #0F172A, #334155);
}

.preview-thumb--text {
  color: white;
  font-weight: 700;
  font-size: 18px;
}

.preview-thumb--empty {
  background: #F1F5F9;
  color: #94A3B8;
}

.text-preview {
  line-height: 1;
}

.action-btns {
  display: flex;
  gap: 6px;
  justify-content: center;
}

.engagement-chip {
  cursor: pointer;
}

.engagement-link {
  border: none;
  background: transparent;
  padding: 0;
  cursor: pointer;
  color: inherit;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font: inherit;
}

.engagement-link:hover {
  color: #2E86FB;
}

.engagement-list {
  max-height: 420px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.engagement-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 8px 10px;
  border-radius: 12px;
  background: #F8FAFC;
  border: 1px solid rgba(15, 23, 42, 0.06);
}

.pagination-bar {
  display: flex;
  justify-content: center;
  padding-top: 12px;
}

.preview-dialog-media {
  border-radius: 16px;
  overflow: hidden;
  background: #0F172A;
  min-height: 280px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.preview-dialog-img,
.preview-dialog-video {
  width: 100%;
  max-height: 420px;
  object-fit: contain;
  display: block;
}

.preview-dialog-text {
  width: 100%;
  min-height: 280px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  color: white;
  font-size: 1.25rem;
  font-weight: 600;
  text-align: center;
}

.upload-zone {
  border: 1.5px dashed rgba(46, 134, 251, 0.45);
  border-radius: 16px;
  min-height: 160px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  background: #F8FAFC;
  overflow: hidden;
  padding: 12px;
}

.upload-zone--has {
  border-style: solid;
  padding: 0;
}

.upload-preview {
  width: 100%;
  max-height: 240px;
  object-fit: contain;
  display: block;
  border-radius: 14px;
}

.bg-swatch {
  width: 36px;
  height: 36px;
  border-radius: 10px;
  border: 2px solid transparent;
  cursor: pointer;
}

.bg-swatch--active {
  border-color: #0F172A;
  box-shadow: 0 0 0 2px white inset;
}

.text-preview-card {
  border-radius: 16px;
  min-height: 120px;
  padding: 20px;
  color: white;
  font-weight: 600;
  text-align: center;
  display: flex;
  align-items: center;
  justify-content: center;
}
</style>
