<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'

const films = ref([])
const sections = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(12)
const loading = ref(false)
const sectionsLoading = ref(false)
const search = ref('')
const statusFilter = ref('all')
const sectionFilter = ref(null)
let searchTimer = null

const dialog = ref(false)
const previewDialog = ref(false)
const deleteDialog = ref(false)
const sectionDialog = ref(false)
const sectionDeleteDialog = ref(false)
const editingSectionId = ref(null)
const sectionToDelete = ref(null)
const savingSection = ref(false)
const editingId = ref(null)
const previewFilm = ref(null)
const toDelete = ref(null)
const saving = ref(false)
const deletingFilm = ref(false)
const deletingSection = ref(false)
const uploadingVideo = ref(false)
const uploadingThumb = ref(false)
const uploadingSectionImage = ref(false)

const importDialog = ref(false)
const stockProviders = ref([])
const stockProvider = ref('pexels')
const stockQuery = ref('')
const stockPage = ref(1)
const stockResults = ref([])
const stockTotal = ref(0)
const stockHasMore = ref(false)
const stockSearching = ref(false)
const stockImportingKey = ref(null)
const importSectionId = ref(null)
const importActive = ref(false)
const importFeatured = ref(false)

const videoInput = ref(null)
const thumbInput = ref(null)
const sectionImageInput = ref(null)

const form = ref({
  title: '',
  description: '',
  videoUrl: '',
  thumbnailUrl: '',
  durationSeconds: null,
  sortOrder: 0,
  isActive: true,
  isFeatured: false,
  sectionId: null
})

const sectionForm = ref({
  name: '',
  sortOrder: 0,
  isActive: true,
  imageUrl: ''
})

const stats = computed(() => ({
  total: total.value,
  active: films.value.filter(f => f.isActive).length,
  featured: films.value.filter(f => f.isFeatured).length
}))

const pageCount = computed(() => Math.max(1, Math.ceil(total.value / pageSize.value)))

const formBusy = computed(
  () => saving.value || uploadingVideo.value || uploadingThumb.value
)

function fullMediaUrl(url) {
  if (!url) return ''
  if (url.startsWith('http')) return url
  const base = (import.meta.env.VITE_API_URL || 'http://localhost:5000/api').replace(/\/api\/?$/, '')
  return `${base}${url.startsWith('/') ? '' : '/'}${url}`
}

function formatDate(date) {
  return new Date(date).toLocaleDateString('ar', { year: 'numeric', month: 'short', day: 'numeric' })
}

function formatDuration(sec) {
  if (!sec) return '—'
  const m = Math.floor(sec / 60)
  const s = sec % 60
  return m > 0 ? `${m}:${String(s).padStart(2, '0')}` : `${s}ث`
}

function probeVideoDurationFromFile(file) {
  return new Promise((resolve) => {
    if (!file) {
      resolve(null)
      return
    }
    const video = document.createElement('video')
    video.preload = 'metadata'
    const blobUrl = URL.createObjectURL(file)
    const cleanup = () => URL.revokeObjectURL(blobUrl)
    video.onloadedmetadata = () => {
      const sec = Math.round(Number(video.duration))
      cleanup()
      resolve(Number.isFinite(sec) && sec > 0 ? sec : null)
    }
    video.onerror = () => {
      cleanup()
      resolve(null)
    }
    video.src = blobUrl
  })
}

function probeVideoDurationFromUrl(url) {
  return new Promise((resolve) => {
    if (!url) {
      resolve(null)
      return
    }
    const video = document.createElement('video')
    video.preload = 'metadata'
    video.crossOrigin = 'anonymous'
    const onDone = (sec) => {
      video.removeAttribute('src')
      video.load()
      resolve(sec)
    }
    video.onloadedmetadata = () => {
      const sec = Math.round(Number(video.duration))
      onDone(Number.isFinite(sec) && sec > 0 ? sec : null)
    }
    video.onerror = () => onDone(null)
    video.src = url
  })
}

async function syncDurationFromVideoUrl(url) {
  if (!url) {
    form.value.durationSeconds = null
    return
  }
  const duration = await probeVideoDurationFromUrl(fullMediaUrl(url))
  if (duration != null) form.value.durationSeconds = duration
}

function onPreviewVideoMetadata(e) {
  const sec = Math.round(Number(e.target?.duration))
  if (Number.isFinite(sec) && sec > 0) form.value.durationSeconds = sec
}

async function fetchSections() {
  sectionsLoading.value = true
  try {
    const res = await api.get('/admin/short-film-sections')
    sections.value = res.data ?? []
  } catch {
    sections.value = []
  } finally {
    sectionsLoading.value = false
  }
}

function sectionName(sectionId) {
  if (!sectionId) return '—'
  return sections.value.find(s => s.id === sectionId)?.name ?? '—'
}

function openAddSection() {
  editingSectionId.value = null
  sectionForm.value = { name: '', sortOrder: sections.value.length, isActive: true, imageUrl: '' }
  sectionDialog.value = true
}

function openEditSection(section) {
  editingSectionId.value = section.id
  sectionForm.value = {
    name: section.name,
    sortOrder: section.sortOrder,
    isActive: section.isActive,
    imageUrl: section.imageUrl || ''
  }
  sectionDialog.value = true
}

function clearSectionImage() {
  sectionForm.value.imageUrl = ''
}

function confirmDeleteSection(section) {
  sectionToDelete.value = section
  sectionDeleteDialog.value = true
}

async function onSectionImageChange(e) {
  const file = e.target?.files?.[0]
  if (!file) return
  uploadingSectionImage.value = true
  try {
    const fd = new FormData()
    fd.append('file', file)
    const res = await api.post('/admin/short-film-sections/upload-image', fd, {
      headers: { 'Content-Type': 'multipart/form-data' }
    })
    sectionForm.value.imageUrl = res.data.url
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل رفع صورة القسم')
  } finally {
    uploadingSectionImage.value = false
    e.target.value = ''
  }
}

async function saveSection() {
  if (!sectionForm.value.name.trim()) {
    notify.warning('اسم القسم مطلوب')
    return
  }
  savingSection.value = true
  try {
    const body = {
      name: sectionForm.value.name.trim(),
      sortOrder: sectionForm.value.sortOrder,
      isActive: sectionForm.value.isActive,
      imageUrl: sectionForm.value.imageUrl || null
    }
    if (editingSectionId.value) {
      const hadImage = sections.value.find(s => s.id === editingSectionId.value)?.imageUrl
      if (!sectionForm.value.imageUrl && hadImage) {
        body.clearImageUrl = true
      }
      await api.put(`/admin/short-film-sections/${editingSectionId.value}`, body)
    } else {
      await api.post('/admin/short-film-sections', body)
    }
    sectionDialog.value = false
    await fetchSections()
  } catch (err) {
    notify.error(err.response?.data?.message || 'حدث خطأ')
  } finally {
    savingSection.value = false
  }
}

async function executeDeleteSection() {
  if (!sectionToDelete.value) return
  deletingSection.value = true
  try {
    await api.delete(`/admin/short-film-sections/${sectionToDelete.value.id}`)
    sectionDeleteDialog.value = false
    if (sectionFilter.value === sectionToDelete.value.id) sectionFilter.value = null
    await fetchSections()
    fetchFilms()
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل الحذف')
  } finally {
    deletingSection.value = false
  }
}

async function fetchStockProviders() {
  try {
    const res = await api.get('/admin/short-films/stock/providers')
    stockProviders.value = res.data?.providers ?? []
    if (stockProviders.value.length && !stockProviders.value.includes(stockProvider.value)) {
      stockProvider.value = stockProviders.value[0]
    }
  } catch {
    stockProviders.value = []
  }
}

function openImport() {
  importDialog.value = true
  stockQuery.value = ''
  stockResults.value = []
  stockPage.value = 1
  stockTotal.value = 0
  stockHasMore.value = false
  importSectionId.value = sectionFilter.value
  importActive.value = false
  importFeatured.value = false
  void fetchStockProviders()
}

async function searchStock(resetPage = true) {
  if (!stockQuery.value.trim()) return
  if (resetPage) stockPage.value = 1
  stockSearching.value = true
  try {
    const res = await api.get('/admin/short-films/stock/search', {
      params: {
        provider: stockProvider.value,
        query: stockQuery.value.trim(),
        page: stockPage.value
      }
    })
    stockResults.value = res.data?.items ?? []
    stockTotal.value = res.data?.totalResults ?? 0
    stockHasMore.value = res.data?.hasMore ?? false
  } catch (err) {
    notify.error(err.response?.data?.message || err.response?.data?.detail || 'فشل البحث')
    stockResults.value = []
  } finally {
    stockSearching.value = false
  }
}

function stockImportKey(item) {
  return `${item.provider}:${item.externalId}`
}

async function importStockItem(item) {
  const key = stockImportKey(item)
  stockImportingKey.value = key
  try {
    await api.post(
      '/admin/short-films/stock/import',
      {
        provider: item.provider,
        externalId: item.externalId,
        title: item.title,
        description: null,
        videoDownloadUrl: item.videoDownloadUrl,
        thumbnailUrl: item.thumbnailUrl,
        durationSeconds: item.durationSeconds,
        sectionId: importSectionId.value,
        sortOrder: total.value,
        isActive: importActive.value,
        isFeatured: importFeatured.value
      },
      { timeout: 180000 }
    )
    await fetchFilms()
    notify.success('تم استيراد الفيديو بنجاح')
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل الاستيراد')
  } finally {
    stockImportingKey.value = null
  }
}

async function fetchFilms() {
  loading.value = true
  try {
    const res = await api.get('/admin/short-films', {
      params: {
        page: page.value,
        pageSize: pageSize.value,
        search: search.value.trim() || undefined,
        status: statusFilter.value,
        sectionId: sectionFilter.value || undefined
      }
    })
    films.value = res.data.items ?? []
    total.value = res.data.total ?? 0
  } catch {
    films.value = []
    total.value = 0
  } finally {
    loading.value = false
  }
}

function openAdd() {
  editingId.value = null
  form.value = {
    title: '',
    description: '',
    videoUrl: '',
    thumbnailUrl: '',
    durationSeconds: null,
    sortOrder: films.value.length,
    isActive: true,
    isFeatured: false,
    sectionId: null
  }
  dialog.value = true
}

function openEdit(film) {
  editingId.value = film.id
  form.value = {
    title: film.title,
    description: film.description || '',
    videoUrl: film.videoUrl,
    thumbnailUrl: film.thumbnailUrl || '',
    durationSeconds: film.durationSeconds,
    sortOrder: film.sortOrder,
    isActive: film.isActive,
    isFeatured: film.isFeatured,
    sectionId: film.sectionId || null
  }
  dialog.value = true
}

function openPreview(film) {
  previewFilm.value = film
  previewDialog.value = true
}

function confirmDelete(film) {
  toDelete.value = film
  deleteDialog.value = true
}

async function executeDelete() {
  if (!toDelete.value) return
  deletingFilm.value = true
  try {
    await api.delete(`/admin/short-films/${toDelete.value.id}`)
    deleteDialog.value = false
    await fetchFilms()
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل الحذف')
  } finally {
    deletingFilm.value = false
    toDelete.value = null
  }
}

async function onVideoChange(e) {
  const file = e.target?.files?.[0]
  if (!file) return
  uploadingVideo.value = true
  try {
    const durationPromise = probeVideoDurationFromFile(file)
    const fd = new FormData()
    fd.append('file', file)
    const [res, duration] = await Promise.all([
      api.post('/admin/short-films/upload-video', fd, {
        headers: { 'Content-Type': 'multipart/form-data' }
      }),
      durationPromise
    ])
    form.value.videoUrl = res.data.url
    if (duration != null) form.value.durationSeconds = duration
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل رفع الفيديو')
  } finally {
    uploadingVideo.value = false
    e.target.value = ''
  }
}

async function onThumbChange(e) {
  const file = e.target?.files?.[0]
  if (!file) return
  uploadingThumb.value = true
  try {
    const fd = new FormData()
    fd.append('file', file)
    const res = await api.post('/admin/short-films/upload-thumbnail', fd, {
      headers: { 'Content-Type': 'multipart/form-data' }
    })
    form.value.thumbnailUrl = res.data.url
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل رفع الصورة')
  } finally {
    uploadingThumb.value = false
    e.target.value = ''
  }
}

async function save() {
  if (!form.value.title.trim() || !form.value.videoUrl) {
    notify.warning('العنوان والفيديو مطلوبان')
    return
  }
  saving.value = true
  try {
    const body = {
      title: form.value.title.trim(),
      description: form.value.description.trim() || null,
      videoUrl: form.value.videoUrl,
      thumbnailUrl: form.value.thumbnailUrl || null,
      durationSeconds: form.value.durationSeconds,
      sortOrder: form.value.sortOrder,
      isActive: form.value.isActive,
      isFeatured: form.value.isFeatured,
      sectionId: form.value.sectionId,
      setSectionId: true
    }
    if (editingId.value) {
      await api.put(`/admin/short-films/${editingId.value}`, body)
    } else {
      await api.post('/admin/short-films', body)
    }
    dialog.value = false
    fetchFilms()
  } catch (err) {
    notify.error(err.response?.data?.message || 'حدث خطأ')
  } finally {
    saving.value = false
  }
}

watch(page, fetchFilms)
watch(statusFilter, () => {
  page.value = 1
  fetchFilms()
})
watch(sectionFilter, () => {
  page.value = 1
  fetchFilms()
})
watch(search, () => {
  clearTimeout(searchTimer)
  searchTimer = setTimeout(() => {
    page.value = 1
    fetchFilms()
  }, 400)
})

watch(
  () => [dialog.value, form.value.videoUrl],
  ([open, url]) => {
    if (!open || !url) return
    void syncDurationFromVideoUrl(url)
  }
)

watch(deleteDialog, (open) => {
  if (!open && !deletingFilm.value) toDelete.value = null
})

watch(sectionDeleteDialog, (open) => {
  if (!open && !deletingSection.value) sectionToDelete.value = null
})

onMounted(async () => {
  await fetchSections()
  await fetchFilms()
})
</script>

<template>
  <div>
    <div class="d-flex flex-wrap align-center justify-space-between gap-4 mb-6">
      <div>
        <div class="text-h5 font-weight-bold">الأفلام القصيرة</div>
        <div class="text-body-2 text-medium-emphasis">
          إدارة محتوى الفيديو القصير — يظهر للمستخدمين في التطبيق فقط
        </div>
      </div>
      <div class="d-flex flex-wrap gap-2">
        <v-btn color="secondary" prepend-icon="mdi-cloud-download" rounded="lg" size="large" variant="tonal" @click="openImport">
          استيراد من Stock
        </v-btn>
        <v-btn
          color="primary"
          prepend-icon="mdi-movie-open"
          rounded="lg"
          size="large"
          :disabled="formBusy || deletingFilm"
          @click="openAdd"
        >
          إضافة يدوي
        </v-btn>
      </div>
    </div>

    <v-row class="mb-6" dense>
      <v-col cols="4">
        <v-card rounded="xl" elevation="0" class="stat-card pa-4">
          <div class="text-caption text-medium-emphasis">الإجمالي</div>
          <div class="text-h5 font-weight-bold">{{ stats.total }}</div>
        </v-card>
      </v-col>
      <v-col cols="4">
        <v-card rounded="xl" elevation="0" class="stat-card pa-4">
          <div class="text-caption text-medium-emphasis">نشط (هذه الصفحة)</div>
          <div class="text-h5 font-weight-bold text-success">{{ stats.active }}</div>
        </v-card>
      </v-col>
      <v-col cols="4">
        <v-card rounded="xl" elevation="0" class="stat-card pa-4">
          <div class="text-caption text-medium-emphasis">مميز (هذه الصفحة)</div>
          <div class="text-h5 font-weight-bold text-primary">{{ stats.featured }}</div>
        </v-card>
      </v-col>
    </v-row>

    <v-card rounded="xl" elevation="0" class="pa-4 mb-4">
      <div class="d-flex flex-wrap align-center justify-space-between gap-2 mb-4">
        <div class="text-subtitle-1 font-weight-bold">أقسام الأفلام</div>
        <v-btn size="small" color="primary" variant="tonal" prepend-icon="mdi-folder-plus" rounded="lg" @click="openAddSection">
          قسم جديد
        </v-btn>
      </div>
      <v-progress-linear v-if="sectionsLoading" indeterminate color="primary" class="mb-3" />
      <v-list v-if="sections.length" density="compact" class="mb-2 pa-0">
        <v-list-item v-for="section in sections" :key="section.id" rounded="lg" class="mb-1">
          <template #prepend>
            <v-avatar v-if="section.imageUrl" size="40" class="me-2">
              <v-img :src="fullMediaUrl(section.imageUrl)" cover />
            </v-avatar>
            <v-avatar v-else size="40" color="primary" variant="tonal" class="me-2">
              <span class="text-body-2 font-weight-bold">{{ section.name?.[0] || '?' }}</span>
            </v-avatar>
          </template>
          <v-list-item-title>{{ section.name }}</v-list-item-title>
          <v-list-item-subtitle>{{ section.filmCount }} فيلم · ترتيب {{ section.sortOrder }}</v-list-item-subtitle>
          <template #append>
            <v-chip v-if="!section.isActive" size="x-small" variant="tonal" class="me-2">معطل</v-chip>
            <v-btn
              icon="mdi-pencil"
              size="small"
              variant="text"
              :disabled="deletingSection || savingSection"
              @click="openEditSection(section)"
            />
            <v-btn
              icon="mdi-delete"
              size="small"
              variant="text"
              color="error"
              :loading="deletingSection && sectionToDelete?.id === section.id"
              :disabled="deletingSection || savingSection"
              @click="confirmDeleteSection(section)"
            />
          </template>
        </v-list-item>
      </v-list>
      <v-alert v-else-if="!sectionsLoading" type="info" variant="tonal" density="compact" rounded="lg">
        لا توجد أقسام. أنشئ قسماً لتجميع الأفلام في التطبيق.
      </v-alert>
    </v-card>

    <v-card rounded="xl" elevation="0" class="pa-4 mb-4">
      <v-row dense align="center">
        <v-col cols="12" md="4">
          <v-text-field
            v-model="search"
            label="بحث بالعنوان أو الوصف"
            prepend-inner-icon="mdi-magnify"
            variant="outlined"
            rounded="lg"
            density="compact"
            hide-details
            clearable
          />
        </v-col>
        <v-col cols="12" md="3">
          <v-select
            v-model="statusFilter"
            :items="[
              { title: 'الكل', value: 'all' },
              { title: 'نشط', value: 'active' },
              { title: 'معطل', value: 'inactive' }
            ]"
            item-title="title"
            item-value="value"
            label="الحالة"
            variant="outlined"
            rounded="lg"
            density="compact"
            hide-details
          />
        </v-col>
        <v-col cols="12" md="3">
          <v-select
            v-model="sectionFilter"
            :items="[{ title: 'كل الأقسام', value: null }, ...sections.map(s => ({ title: s.name, value: s.id }))]"
            item-title="title"
            item-value="value"
            label="القسم"
            variant="outlined"
            rounded="lg"
            density="compact"
            hide-details
            clearable
          />
        </v-col>
        <v-col cols="12" md="2" class="d-flex justify-end">
          <v-btn variant="tonal" prepend-icon="mdi-refresh" rounded="lg" :loading="loading" @click="fetchFilms">
            تحديث
          </v-btn>
        </v-col>
      </v-row>
    </v-card>

    <v-progress-linear v-if="loading" indeterminate color="primary" class="mb-4" />

    <v-row v-if="films.length">
      <v-col v-for="film in films" :key="film.id" cols="12" sm="6" md="4">
        <v-card
          rounded="xl"
          elevation="0"
          class="film-card overflow-hidden"
          :class="{ 'film-card--busy': deletingFilm && toDelete?.id === film.id }"
        >
          <div class="thumb-wrap" @click="openPreview(film)">
            <v-img
              v-if="film.thumbnailUrl"
              :src="fullMediaUrl(film.thumbnailUrl)"
              aspect-ratio="16/9"
              cover
            />
            <div v-else class="thumb-placeholder d-flex align-center justify-center">
              <v-icon icon="mdi-movie-play" size="48" color="primary" />
            </div>
            <div class="thumb-overlay d-flex align-center justify-center">
              <v-icon icon="mdi-play-circle" size="40" color="white" />
            </div>
          </div>
          <v-card-text class="pb-2">
            <div class="d-flex flex-wrap gap-1 mb-2">
              <v-chip v-if="film.isActive" size="x-small" color="success" variant="tonal">نشط</v-chip>
              <v-chip v-else size="x-small" variant="tonal">معطل</v-chip>
              <v-chip v-if="film.isFeatured" size="x-small" color="primary" variant="tonal">مميز</v-chip>
              <v-chip v-if="film.sectionId" size="x-small" variant="tonal">{{ sectionName(film.sectionId) }}</v-chip>
              <v-chip size="x-small" variant="tonal">{{ formatDuration(film.durationSeconds) }}</v-chip>
            </div>
            <div class="text-subtitle-2 font-weight-bold text-truncate">{{ film.title }}</div>
            <div class="text-caption text-medium-emphasis">{{ formatDate(film.createdAt) }} · {{ film.viewCount }} مشاهدة</div>
          </v-card-text>
          <v-card-actions class="pt-0 px-4 pb-4">
            <v-btn size="small" variant="tonal" prepend-icon="mdi-eye" @click="openPreview(film)">معاينة</v-btn>
            <v-spacer />
            <v-btn
              icon="mdi-pencil"
              size="small"
              variant="text"
              :disabled="deletingFilm || formBusy"
              @click="openEdit(film)"
            />
            <v-btn
              icon="mdi-delete"
              size="small"
              variant="text"
              color="error"
              :loading="deletingFilm && toDelete?.id === film.id"
              :disabled="deletingFilm || formBusy"
              @click="confirmDelete(film)"
            />
          </v-card-actions>
        </v-card>
      </v-col>
    </v-row>

    <v-alert v-else-if="!loading" type="info" variant="tonal" rounded="xl">
      لا توجد أفلام. اضغط «إضافة فيلم» للبدء.
    </v-alert>

    <div v-if="pageCount > 1" class="d-flex justify-center mt-6">
      <v-pagination v-model="page" :length="pageCount" rounded="circle" color="primary" />
    </div>

    <!-- Stock import (Pexels / Pixabay) -->
    <v-dialog v-model="importDialog" max-width="720" persistent scrollable>
      <v-card rounded="xl" elevation="0">
        <v-card-title class="font-weight-bold pa-4 pb-0">استيراد من Pexels / Pixabay</v-card-title>
        <v-card-subtitle class="px-4 pt-1 text-wrap">
          مقاطع مجانية مرخّصة للاستخدام. يُحمَّل الفيديو على السيرفر — يُنصح بمراجعة المحتوى قبل التفعيل.
        </v-card-subtitle>
        <v-card-text class="pa-4">
          <v-alert
            v-if="!stockProviders.length"
            type="warning"
            variant="tonal"
            density="compact"
            rounded="lg"
            class="mb-4"
          >
            أضف مفاتيح API في إعدادات السيرفر: <code>StockVideo:PexelsApiKey</code> و/أو
            <code>StockVideo:PixabayApiKey</code>
          </v-alert>
          <v-row dense class="mb-3">
            <v-col cols="12" sm="4">
              <v-select
                v-model="stockProvider"
                :items="[
                  { title: 'Pexels', value: 'pexels', disabled: !stockProviders.includes('pexels') },
                  { title: 'Pixabay', value: 'pixabay', disabled: !stockProviders.includes('pixabay') }
                ]"
                item-title="title"
                item-value="value"
                label="المصدر"
                variant="outlined"
                rounded="lg"
                density="compact"
                hide-details
                :disabled="!stockProviders.length"
              />
            </v-col>
            <v-col cols="12" sm="8">
              <v-text-field
                v-model="stockQuery"
                label="بحث (مثال: arabic, croatia, nature, city)"
                variant="outlined"
                rounded="lg"
                density="compact"
                hide-details
                clearable
                @keyup.enter="searchStock(true)"
              />
            </v-col>
          </v-row>
          <v-btn
            block
            color="primary"
            variant="tonal"
            prepend-icon="mdi-magnify"
            rounded="lg"
            class="mb-4"
            :loading="stockSearching"
            :disabled="!stockProviders.length || !stockQuery.trim()"
            @click="searchStock(true)"
          >
            بحث
          </v-btn>
          <v-row dense class="mb-2">
            <v-col cols="12" sm="6">
              <v-select
                v-model="importSectionId"
                :items="[{ title: 'بدون قسم', value: null }, ...sections.filter(s => s.isActive).map(s => ({ title: s.name, value: s.id }))]"
                item-title="title"
                item-value="value"
                label="القسم عند الاستيراد"
                variant="outlined"
                rounded="lg"
                density="compact"
                hide-details
                clearable
              />
            </v-col>
            <v-col cols="6" sm="3">
              <v-switch v-model="importActive" label="نشط فوراً" color="primary" hide-details density="compact" />
            </v-col>
            <v-col cols="6" sm="3">
              <v-switch v-model="importFeatured" label="مميز" color="primary" hide-details density="compact" />
            </v-col>
          </v-row>
          <div v-if="stockResults.length" class="text-caption text-medium-emphasis mb-2">
            {{ stockTotal }} نتيجة تقريباً — الصفحة {{ stockPage }}
          </div>
          <v-row v-if="stockResults.length" dense>
            <v-col v-for="item in stockResults" :key="stockImportKey(item)" cols="6" sm="4">
              <v-card rounded="lg" elevation="0" class="stock-card overflow-hidden">
                <v-img :src="item.thumbnailUrl" aspect-ratio="16/9" cover />
                <v-card-text class="pa-2">
                  <div class="text-caption font-weight-bold text-truncate">{{ item.title }}</div>
                  <div class="text-caption text-medium-emphasis">
                    {{ item.provider }} · {{ formatDuration(item.durationSeconds) }}
                  </div>
                  <v-btn
                    block
                    size="small"
                    color="primary"
                    variant="tonal"
                    class="mt-2"
                    :loading="stockImportingKey === stockImportKey(item)"
                    @click="importStockItem(item)"
                  >
                    استيراد
                  </v-btn>
                </v-card-text>
              </v-card>
            </v-col>
          </v-row>
          <v-alert v-else-if="stockQuery && !stockSearching" type="info" variant="tonal" density="compact" rounded="lg">
            لا نتائج. جرّب كلمات بحث أخرى أو مصدراً مختلفاً.
          </v-alert>
          <div v-if="stockHasMore" class="d-flex justify-center mt-4">
            <v-btn
              variant="outlined"
              rounded="lg"
              :loading="stockSearching"
              @click="stockPage++; searchStock(false)"
            >
              المزيد
            </v-btn>
          </div>
        </v-card-text>
        <v-card-actions class="pa-4 pt-0">
          <v-spacer />
          <v-btn variant="text" @click="importDialog = false">إغلاق</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Add/Edit -->
    <v-dialog v-model="dialog" max-width="560" persistent scrollable>
      <v-card rounded="xl" elevation="0" class="position-relative">
        <v-overlay
          :model-value="formBusy"
          contained
          persistent
          class="align-center justify-center dialog-busy-overlay"
          scrim="rgba(13, 13, 26, 0.72)"
        >
          <div class="d-flex flex-column align-center ga-3">
            <v-progress-circular indeterminate color="primary" size="44" width="3" />
            <span class="text-body-2 text-medium-emphasis">
              {{ saving ? (editingId ? 'جاري الحفظ…' : 'جاري الإضافة…') : uploadingVideo ? 'جاري رفع الفيديو…' : 'جاري رفع الصورة…' }}
            </span>
          </div>
        </v-overlay>
        <v-card-title class="font-weight-bold pa-4 pb-0">
          {{ editingId ? 'تعديل فيلم' : 'إضافة فيلم جديد' }}
        </v-card-title>
        <v-card-text class="pa-4">
          <input ref="videoInput" type="file" accept="video/mp4,video/webm,video/quicktime" hidden @change="onVideoChange" />
          <input ref="thumbInput" type="file" accept="image/*" hidden @change="onThumbChange" />

          <div class="mb-4">
            <div class="text-body-2 mb-2">ملف الفيديو *</div>
            <video
              v-if="form.videoUrl"
              :src="fullMediaUrl(form.videoUrl)"
              controls
              playsinline
              preload="metadata"
              class="video-preview mb-2"
              @loadedmetadata="onPreviewVideoMetadata"
            />
            <v-btn
              block
              variant="tonal"
              color="primary"
              :loading="uploadingVideo"
              prepend-icon="mdi-video-plus"
              @click="videoInput?.click()"
            >
              {{ form.videoUrl ? 'تغيير الفيديو' : 'رفع فيديو' }}
            </v-btn>
          </div>

          <div class="mb-4">
            <div class="text-body-2 mb-2">صورة مصغّرة (اختياري)</div>
            <v-img
              v-if="form.thumbnailUrl"
              :src="fullMediaUrl(form.thumbnailUrl)"
              max-height="120"
              cover
              rounded="lg"
              class="mb-2"
            />
            <v-btn
              block
              variant="outlined"
              :loading="uploadingThumb"
              prepend-icon="mdi-image"
              @click="thumbInput?.click()"
            >
              {{ form.thumbnailUrl ? 'تغيير الصورة' : 'رفع صورة مصغّرة' }}
            </v-btn>
          </div>

          <v-text-field v-model="form.title" label="العنوان *" variant="outlined" rounded="lg" density="compact" class="mb-3" />
          <v-textarea v-model="form.description" label="الوصف" variant="outlined" rounded="lg" density="compact" rows="2" class="mb-3" />
          <v-text-field v-model.number="form.sortOrder" type="number" label="الترتيب" variant="outlined" rounded="lg" density="compact" min="0" class="mb-3" />
          <v-text-field
            :model-value="form.durationSeconds != null ? formatDuration(form.durationSeconds) : ''"
            label="مدة الفيديو"
            variant="outlined"
            rounded="lg"
            density="compact"
            readonly
            persistent-hint
            hint="تُستخرج تلقائياً من ملف الفيديو عند الرفع أو التغيير"
            placeholder="—"
            class="mb-3"
          />
          <v-switch v-model="form.isActive" label="نشط" color="primary" hide-details class="mb-1" />
          <v-switch v-model="form.isFeatured" label="مميز (يظهر في الشريط الأفقي)" color="primary" hide-details class="mb-3" />
          <v-select
            v-model="form.sectionId"
            :items="[{ title: 'بدون قسم', value: null }, ...sections.filter(s => s.isActive).map(s => ({ title: s.name, value: s.id }))]"
            item-title="title"
            item-value="value"
            label="القسم"
            variant="outlined"
            rounded="lg"
            density="compact"
            hide-details
            clearable
          />
        </v-card-text>
        <v-card-actions class="pa-4 pt-0">
          <v-spacer />
          <v-btn variant="text" :disabled="formBusy" @click="dialog = false">إلغاء</v-btn>
          <v-btn
            color="primary"
            variant="tonal"
            :loading="saving"
            :disabled="!form.videoUrl || formBusy"
            @click="save"
          >
            {{ editingId ? 'حفظ التعديل' : 'إضافة' }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Preview -->
    <v-dialog v-model="previewDialog" max-width="420" content-class="preview-dialog">
      <v-card v-if="previewFilm" rounded="xl" elevation="0" class="bg-black">
        <video
          :src="fullMediaUrl(previewFilm.videoUrl)"
          controls
          autoplay
          playsinline
          class="preview-video"
        />
        <v-card-text class="text-white">
          <div class="font-weight-bold">{{ previewFilm.title }}</div>
          <div v-if="previewFilm.description" class="text-body-2 mt-1">{{ previewFilm.description }}</div>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" color="white" @click="previewDialog = false">إغلاق</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Section add/edit -->
    <v-dialog v-model="sectionDialog" max-width="420" persistent>
      <v-card rounded="xl" elevation="0" class="position-relative">
        <v-overlay
          :model-value="savingSection || uploadingSectionImage"
          contained
          persistent
          class="align-center justify-center dialog-busy-overlay"
          scrim="rgba(13, 13, 26, 0.72)"
        >
          <div class="d-flex flex-column align-center ga-3">
            <v-progress-circular indeterminate color="primary" size="40" width="3" />
            <span class="text-body-2 text-medium-emphasis">
              {{ savingSection ? 'جاري الحفظ…' : 'جاري رفع الصورة…' }}
            </span>
          </div>
        </v-overlay>
        <v-card-title class="font-weight-bold pa-4 pb-0">
          {{ editingSectionId ? 'تعديل قسم' : 'قسم جديد' }}
        </v-card-title>
        <v-card-text class="pa-4">
          <input ref="sectionImageInput" type="file" accept="image/*" hidden @change="onSectionImageChange" />
          <div class="text-body-2 mb-2">صورة القسم (دائرة في التطبيق)</div>
          <div class="d-flex flex-column align-center mb-4">
            <v-avatar size="88" class="section-avatar-preview mb-3">
              <v-img
                v-if="sectionForm.imageUrl"
                :src="fullMediaUrl(sectionForm.imageUrl)"
                cover
              />
              <span v-else class="text-h5 font-weight-bold text-primary">
                {{ sectionForm.name?.trim()?.[0] || '?' }}
              </span>
            </v-avatar>
            <div class="d-flex gap-2 flex-wrap justify-center">
              <v-btn
                size="small"
                variant="tonal"
                color="primary"
                prepend-icon="mdi-image"
                :loading="uploadingSectionImage"
                @click="sectionImageInput?.click()"
              >
                {{ sectionForm.imageUrl ? 'تغيير الصورة' : 'رفع صورة' }}
              </v-btn>
              <v-btn
                v-if="sectionForm.imageUrl"
                size="small"
                variant="text"
                color="error"
                @click="clearSectionImage"
              >
                إزالة
              </v-btn>
            </div>
          </div>
          <v-text-field v-model="sectionForm.name" label="اسم القسم *" variant="outlined" rounded="lg" density="compact" class="mb-3" />
          <v-text-field v-model.number="sectionForm.sortOrder" type="number" label="الترتيب" variant="outlined" rounded="lg" density="compact" min="0" class="mb-3" />
          <v-switch v-model="sectionForm.isActive" label="نشط" color="primary" hide-details />
        </v-card-text>
        <v-card-actions class="pa-4 pt-0">
          <v-spacer />
          <v-btn variant="text" :disabled="savingSection || uploadingSectionImage" @click="sectionDialog = false">
            إلغاء
          </v-btn>
          <v-btn
            color="primary"
            variant="tonal"
            :loading="savingSection"
            :disabled="savingSection || uploadingSectionImage"
            @click="saveSection"
          >
            حفظ
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Section delete -->
    <v-dialog v-model="sectionDeleteDialog" max-width="400" persistent>
      <v-card rounded="xl" elevation="0" class="pa-4">
        <v-card-title class="font-weight-bold">حذف القسم</v-card-title>
        <v-card-text>
          حذف «{{ sectionToDelete?.name }}»؟ ستُزال الأفلام من هذا القسم دون حذفها.
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" :disabled="deletingSection" @click="sectionDeleteDialog = false">إلغاء</v-btn>
          <v-btn color="error" variant="tonal" :loading="deletingSection" @click="executeDeleteSection">حذف</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Delete -->
    <v-dialog v-model="deleteDialog" max-width="400" persistent>
      <v-card rounded="xl" elevation="0" class="pa-4">
        <v-card-title class="font-weight-bold">حذف الفيلم</v-card-title>
        <v-card-text>هل أنت متأكد من حذف «{{ toDelete?.title }}»؟</v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" :disabled="deletingFilm" @click="deleteDialog = false">إلغاء</v-btn>
          <v-btn color="error" variant="tonal" :loading="deletingFilm" @click="executeDelete">حذف</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.stat-card {
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.08);
}
.film-card {
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.08);
  transition: transform 0.15s ease, border-color 0.15s ease;
}
.film-card:hover {
  transform: translateY(-2px);
  border-color: rgba(108, 99, 255, 0.35);
}
.film-card--busy {
  opacity: 0.55;
  pointer-events: none;
}
.dialog-busy-overlay {
  border-radius: inherit;
}
.thumb-wrap {
  position: relative;
  cursor: pointer;
  aspect-ratio: 16 / 9;
  background: #111;
}
.thumb-placeholder {
  aspect-ratio: 16 / 9;
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.2), rgba(255, 101, 132, 0.15));
}
.thumb-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.25);
  opacity: 0;
  transition: opacity 0.2s;
}
.thumb-wrap:hover .thumb-overlay {
  opacity: 1;
}
.video-preview {
  width: 100%;
  max-height: 200px;
  border-radius: 12px;
  background: #000;
}
.preview-video {
  width: 100%;
  max-height: 70vh;
  display: block;
}
.stock-card {
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.08);
}
</style>
