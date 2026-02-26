<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const banners = ref([])
const loading = ref(false)
const placementFilter = ref('')
const dialog = ref(false)
const editingId = ref(null)
const form = ref({
  imageUrl: '',
  placement: 'home',
  order: 0,
  isActive: true,
  link: ''
})
const uploadFileInput = ref(null)

function triggerFileInput() {
  uploadFileInput.value?.click()
}
const uploading = ref(false)
const deleteDialog = ref(false)
const toDelete = ref(null)

const placementLabel = { home: 'الصفحة الرئيسية', matching: 'شاشة انتظار المطابقة' }

async function fetchBanners() {
  loading.value = true
  try {
    const res = await api.get('/admin/banners', {
      params: placementFilter.value ? { placement: placementFilter.value } : {}
    })
    banners.value = res.data
  } catch {
    banners.value = []
  } finally {
    loading.value = false
  }
}

function openAdd() {
  editingId.value = null
  form.value = { imageUrl: '', placement: 'home', order: banners.value.length, isActive: true, link: '' }
  uploadFileInput.value = null
  dialog.value = true
}

function openEdit(banner) {
  editingId.value = banner.id
  form.value = {
    imageUrl: banner.imageUrl,
    placement: banner.placement,
    order: banner.order,
    isActive: banner.isActive,
    link: banner.link || ''
  }
  uploadFileInput.value = null
  dialog.value = true
}

async function onFileChange(e) {
  const file = e.target?.files?.[0]
  if (!file) return
  uploading.value = true
  try {
    const fd = new FormData()
    fd.append('file', file)
    const res = await api.post('/media/upload', fd, {
      headers: { 'Content-Type': 'multipart/form-data' }
    })
    form.value.imageUrl = res.data.url
  } catch (err) {
    alert(err.response?.data || 'فشل رفع الصورة')
  } finally {
    uploading.value = false
    e.target.value = ''
  }
}

async function save() {
  if (!form.value.imageUrl) {
    alert('يرجى رفع صورة')
    return
  }
  try {
    if (editingId.value) {
      await api.put(`/admin/banners/${editingId.value}`, {
        imageUrl: form.value.imageUrl,
        placement: form.value.placement,
        order: form.value.order,
        isActive: form.value.isActive,
        link: form.value.link || null
      })
    } else {
      await api.post('/admin/banners', form.value)
    }
    dialog.value = false
    fetchBanners()
  } catch (err) {
    alert(err.response?.data?.message || 'حدث خطأ')
  }
}

function confirmDelete(banner) {
  toDelete.value = banner
  deleteDialog.value = true
}

async function executeDelete() {
  await api.delete(`/admin/banners/${toDelete.value.id}`)
  deleteDialog.value = false
  fetchBanners()
}

function formatDate(date) {
  return new Date(date).toLocaleDateString('ar', { year: 'numeric', month: 'short', day: 'numeric' })
}

onMounted(fetchBanners)
</script>

<template>
  <div>
    <div class="d-flex align-center justify-space-between mb-6">
      <div>
        <div class="text-h5 font-weight-bold">الإعلانات</div>
        <div class="text-body-2 text-medium-emphasis">إدارة صور الإعلانات في التطبيق</div>
      </div>
      <v-btn color="primary" prepend-icon="mdi-plus" rounded="lg" @click="openAdd">
        إضافة إعلان
      </v-btn>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-4">
      <v-select
        v-model="placementFilter"
        :items="[
          { title: 'الكل', value: '' },
          { title: 'الصفحة الرئيسية', value: 'home' },
          { title: 'شاشة انتظار المطابقة', value: 'matching' }
        ]"
        item-title="title"
        item-value="value"
        label="فلتر المكان"
        variant="outlined"
        rounded="lg"
        density="compact"
        class="mb-4"
        hide-details
        @update:model-value="fetchBanners"
      />

      <v-table v-if="!loading && banners.length">
        <thead>
          <tr>
            <th>الصورة</th>
            <th>المكان</th>
            <th>الترتيب</th>
            <th>الحالة</th>
            <th>تاريخ الإضافة</th>
            <th>إجراءات</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="b in banners" :key="b.id">
            <td>
              <v-img
                :src="b.imageUrl"
                width="80"
                height="48"
                cover
                rounded="lg"
                class="banner-thumb"
              />
            </td>
            <td>
              <v-chip size="small" variant="tonal" color="primary">
                {{ placementLabel[b.placement] }}
              </v-chip>
            </td>
            <td>{{ b.order }}</td>
            <td>
              <v-chip
                size="small"
                :color="b.isActive ? 'success' : 'default'"
                variant="tonal"
              >
                {{ b.isActive ? 'نشط' : 'معطل' }}
              </v-chip>
            </td>
            <td class="text-medium-emphasis text-body-2">{{ formatDate(b.createdAt) }}</td>
            <td>
              <v-btn icon="mdi-pencil" size="small" variant="text" @click="openEdit(b)" />
              <v-btn icon="mdi-delete" size="small" variant="text" color="error" @click="confirmDelete(b)" />
            </td>
          </tr>
        </tbody>
      </v-table>

      <v-alert v-else-if="!loading && !banners.length" type="info" variant="tonal" rounded="lg">
        لا توجد إعلانات. اضغط "إضافة إعلان" للبدء.
      </v-alert>

      <v-progress-linear v-if="loading" indeterminate color="primary" class="mt-4" />
    </v-card>

    <!-- Add/Edit Dialog -->
    <v-dialog v-model="dialog" max-width="500" persistent>
      <v-card rounded="xl" elevation="0" class="pa-4">
        <v-card-title class="font-weight-bold">
          {{ editingId ? 'تعديل إعلان' : 'إضافة إعلان' }}
        </v-card-title>

        <v-card-text class="pa-0 pt-4">
          <v-select
            v-model="form.placement"
            :items="[
              { title: 'الصفحة الرئيسية', value: 'home' },
              { title: 'شاشة انتظار المطابقة', value: 'matching' }
            ]"
            item-title="title"
            item-value="value"
            label="المكان"
            variant="outlined"
            rounded="lg"
            density="compact"
            class="mb-4"
            hide-details
          />

          <div class="mb-4">
            <div class="text-body-2 text-medium-emphasis mb-2">صورة الإعلان</div>
            <input
              ref="uploadFileInput"
              type="file"
              accept="image/jpeg,image/png,image/gif,image/webp"
              style="display: none"
              @change="onFileChange"
            />
            <div v-if="form.imageUrl" class="d-flex align-center gap-3 mb-2">
              <v-img :src="form.imageUrl" width="120" height="72" cover rounded="lg" />
              <v-btn
                variant="tonal"
                color="primary"
                size="small"
                :loading="uploading"
                @click="triggerFileInput"
              >
                تغيير الصورة
              </v-btn>
            </div>
            <v-btn
              v-else
              variant="outlined"
              block
              :loading="uploading"
              @click="triggerFileInput"
            >
              رفع ملف صورة
            </v-btn>
          </div>

          <v-text-field
            v-model="form.link"
            label="رابط اختياري (عند الضغط)"
            placeholder="https://..."
            variant="outlined"
            rounded="lg"
            density="compact"
            class="mb-4"
            hide-details
          />

          <v-text-field
            v-model.number="form.order"
            type="number"
            label="الترتيب"
            variant="outlined"
            rounded="lg"
            density="compact"
            min="0"
            class="mb-4"
            hide-details
          />

          <v-switch v-model="form.isActive" label="نشط" color="primary" hide-details />
        </v-card-text>

        <v-card-actions class="pt-4">
          <v-spacer />
          <v-btn @click="dialog = false" variant="text">إلغاء</v-btn>
          <v-btn color="primary" variant="tonal" @click="save" :disabled="!form.imageUrl">
            حفظ
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Delete Dialog -->
    <v-dialog v-model="deleteDialog" max-width="400">
      <v-card rounded="xl" elevation="0" class="pa-4">
        <v-card-title class="font-weight-bold">حذف الإعلان</v-card-title>
        <v-card-text>
          هل أنت متأكد من حذف هذا الإعلان؟
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn @click="deleteDialog = false" variant="text">إلغاء</v-btn>
          <v-btn color="error" variant="tonal" @click="executeDelete">حذف</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.banner-thumb {
  border: 1px solid rgba(255,255,255,0.08);
}
</style>
