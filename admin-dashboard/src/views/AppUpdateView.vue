<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const minVersion = ref('1.0')
const latestVersion = ref('1.0')
const downloadUrl = ref('')
const iosDownloadUrl = ref('')
const loading = ref(false)
const saving = ref(false)
const saved = ref(false)

async function fetchConfig() {
  loading.value = true
  try {
    const res = await api.get('/admin/site-content/app_update')
    const raw = res.data?.content || ''
    if (raw) {
      try {
        const obj = JSON.parse(raw)
        minVersion.value = obj.minVersion || '1.0'
        latestVersion.value = obj.latestVersion || obj.minVersion || '1.0'
        downloadUrl.value = obj.downloadUrl || ''
        iosDownloadUrl.value = obj.iosDownloadUrl || ''
      } catch {
    minVersion.value = '1.0'
    latestVersion.value = '1.0'
    downloadUrl.value = ''
    iosDownloadUrl.value = ''
      }
    }
  } catch {
    minVersion.value = '1.0'
    downloadUrl.value = ''
  } finally {
    loading.value = false
  }
}

async function save() {
  if (!downloadUrl.value?.trim() && !iosDownloadUrl.value?.trim()) {
    alert('يجب إدخال رابط تحميل واحد على الأقل (Android أو iOS)')
    return
  }
  saving.value = true
  saved.value = false
  try {
    await api.put('/admin/site-content/app_update', {
      content: JSON.stringify({
        minVersion: minVersion.value.trim() || '1.0',
        latestVersion: latestVersion.value.trim() || minVersion.value.trim() || '1.0',
        downloadUrl: downloadUrl.value.trim() || '',
        iosDownloadUrl: iosDownloadUrl.value.trim() || ''
      })
    })
    saved.value = true
    setTimeout(() => { saved.value = false }, 3000)
  } catch (err) {
    alert(err.response?.data?.message || 'فشل الحفظ')
  } finally {
    saving.value = false
  }
}

onMounted(fetchConfig)
</script>

<template>
  <div>
    <div class="d-flex align-center justify-space-between mb-6">
      <div>
        <div class="text-h5 font-weight-bold">تحديث التطبيق</div>
        <div class="text-body-2 text-medium-emphasis">
          عند رفع إصدار جديد، سيظهر مودل للمستخدمين الذين يملكون إصداراً أقدم يطلب منهم التحديث
        </div>
      </div>
      <v-btn
        color="primary"
        prepend-icon="mdi-content-save"
        rounded="lg"
        :loading="saving"
        :disabled="loading"
        @click="save"
      >
        {{ saved ? 'تم الحفظ' : 'حفظ' }}
      </v-btn>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-4">
      <v-text-field
        v-model="minVersion"
        label="أقل إصدار مطلوب"
        placeholder="مثال: 1.0"
        hint="المستخدمون الذين إصدارهم أقل من هذا سيرون مودل التحديث الإجباري"
        persistent-hint
        variant="outlined"
        rounded="lg"
        class="mb-4"
        :disabled="loading"
      />
      <v-text-field
        v-model="latestVersion"
        label="أحدث إصدار متاح"
        placeholder="مثال: 1.0.1"
        hint="يُظهر في الإعدادات 'تحديث التطبيق' للمستخدمين الذين إصدارهم أقدم"
        persistent-hint
        variant="outlined"
        rounded="lg"
        class="mb-4"
        :disabled="loading"
      />
      <v-text-field
        v-model="downloadUrl"
        label="رابط التحميل (Android)"
        placeholder="https://play.google.com/... أو رابط APK"
        hint="رابط Google Play أو APK"
        persistent-hint
        variant="outlined"
        rounded="lg"
        class="mb-4"
        :disabled="loading"
      />
      <v-text-field
        v-model="iosDownloadUrl"
        label="رابط التحميل (iOS)"
        placeholder="https://apps.apple.com/..."
        hint="رابط App Store"
        persistent-hint
        variant="outlined"
        rounded="lg"
        :disabled="loading"
      />
    </v-card>
  </div>
</template>
