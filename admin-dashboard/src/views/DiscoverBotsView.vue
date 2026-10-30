<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'

const loading = ref(false)
const saving = ref(false)
const syncing = ref(false)
const refreshingPhotos = ref(false)
const deleting = ref(false)

const enabled = ref(true)
const femaleTarget = ref(100)
const maleTarget = ref(100)
const matchPercent = ref(30)
const ageMin = ref(18)
const ageMax = ref(45)
const country = ref('IQ')

const femaleBots = ref(0)
const maleBots = ref(0)
const femalePhotosAvailable = ref(0)
const malePhotosAvailable = ref(0)
const femalePhotosUsed = ref(0)
const malePhotosUsed = ref(0)
const lastSyncMsg = ref('')

function applyStatus(data) {
  const c = data?.config || data?.Config || {}
  enabled.value = !!(c.enabled ?? c.Enabled ?? true)
  femaleTarget.value = c.femaleTarget ?? c.FemaleTarget ?? 100
  maleTarget.value = c.maleTarget ?? c.MaleTarget ?? 100
  matchPercent.value = c.matchPercent ?? c.MatchPercent ?? 30
  ageMin.value = c.ageMin ?? c.AgeMin ?? 18
  ageMax.value = c.ageMax ?? c.AgeMax ?? 45
  country.value = c.country ?? c.Country ?? 'IQ'
  femaleBots.value = data?.femaleBots ?? data?.FemaleBots ?? 0
  maleBots.value = data?.maleBots ?? data?.MaleBots ?? 0
  femalePhotosAvailable.value = data?.femalePhotosAvailable ?? data?.FemalePhotosAvailable ?? 0
  malePhotosAvailable.value = data?.malePhotosAvailable ?? data?.MalePhotosAvailable ?? 0
  femalePhotosUsed.value = data?.femalePhotosUsed ?? data?.FemalePhotosUsed ?? 0
  malePhotosUsed.value = data?.malePhotosUsed ?? data?.MalePhotosUsed ?? 0
}

async function fetchConfig() {
  loading.value = true
  try {
    const res = await api.get('/admin/discover-bots/config')
    applyStatus(res.data)
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل التحميل')
  } finally {
    loading.value = false
  }
}

function payload() {
  return {
    enabled: enabled.value,
    femaleTarget: Number(femaleTarget.value),
    maleTarget: Number(maleTarget.value),
    matchPercent: Number(matchPercent.value),
    ageMin: Number(ageMin.value),
    ageMax: Number(ageMax.value),
    country: country.value || 'IQ'
  }
}

async function save() {
  saving.value = true
  try {
    const res = await api.put('/admin/discover-bots/config', payload())
    applyStatus(res.data)
    notify.success('تم الحفظ')
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل الحفظ')
  } finally {
    saving.value = false
  }
}

async function syncPool() {
  syncing.value = true
  lastSyncMsg.value = ''
  try {
    await api.put('/admin/discover-bots/config', payload())
    const res = await api.post('/admin/discover-bots/sync', null, { timeout: 180000 })
    const d = res.data || {}
    const cf = d.createdFemale ?? d.CreatedFemale ?? 0
    const cm = d.createdMale ?? d.CreatedMale ?? 0
    lastSyncMsg.value = d.message || d.Message || `أُنشئ ${cf} أنثى و ${cm} ذكر`
    await fetchConfig()
    notify.success(lastSyncMsg.value)
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشلت المزامنة')
  } finally {
    syncing.value = false
  }
}

async function refreshPhotos() {
  refreshingPhotos.value = true
  try {
    const res = await api.post('/admin/discover-bots/refresh-photos', null, { timeout: 180000 })
    const updated = res.data?.updated ?? res.data?.Updated ?? 0
    const missing = res.data?.missing ?? res.data?.Missing ?? 0
    if (res.data?.status) applyStatus(res.data.status)
    else await fetchConfig()
    notify.success(`تم تحديث ${updated} صورة` + (missing ? ` (ناقص ${missing})` : ''))
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل تحديث الصور')
  } finally {
    refreshingPhotos.value = false
  }
}

async function deleteAll() {
  if (!confirm('حذف كل بوتات التعارف؟ لا يمكن التراجع.')) return
  deleting.value = true
  try {
    const res = await api.delete('/admin/discover-bots', { timeout: 120000 })
    const deleted = res.data?.deleted ?? res.data?.Deleted ?? 0
    if (res.data?.status) applyStatus(res.data.status)
    else await fetchConfig()
    notify.success(`تم حذف ${deleted} بوت`)
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل الحذف')
  } finally {
    deleting.value = false
  }
}

onMounted(fetchConfig)
</script>

<template>
  <div>
    <div class="d-flex align-center justify-space-between mb-6 flex-wrap ga-3">
      <div>
        <div class="text-h5 font-weight-bold">بوتات التعارف</div>
        <div class="text-body-2 text-medium-emphasis">
          بركة ملفات وهمية لملء فيد التعارف. الصور جاهزة على السيرفر — اضبط الأعداد ونسبة التطابق ثم زامن.
        </div>
      </div>
      <div class="d-flex ga-2 flex-wrap">
        <v-btn color="primary" rounded="lg" :loading="saving" :disabled="loading" @click="save">حفظ</v-btn>
        <v-btn color="secondary" rounded="lg" :loading="syncing" :disabled="loading" @click="syncPool">مزامنة البركة</v-btn>
        <v-btn color="primary" variant="tonal" rounded="lg" :loading="refreshingPhotos" :disabled="loading" @click="refreshPhotos">تحديث الصور</v-btn>
        <v-btn color="error" variant="tonal" rounded="lg" :loading="deleting" :disabled="loading" @click="deleteAll">حذف الكل</v-btn>
      </div>
    </div>

    <v-alert type="info" variant="tonal" rounded="lg" class="mb-4">
      عند إيقاف التفعيل تختفي البوتات من فيد التطبيق فوراً (مفيد لمراجعة المتاجر) دون حذف الحسابات.
      نسبة التطابق تحدد احتمال أن يرد البوت بإعجاب متبادل عند إعجاب مستخدم حقيقي.
    </v-alert>

    <v-row dense class="mb-4">
      <v-col cols="6" sm="3">
        <v-card rounded="xl" elevation="0" class="pa-4 text-center">
          <div class="text-caption text-medium-emphasis">بوتات إناث</div>
          <div class="text-h5 font-weight-bold">{{ femaleBots }}</div>
        </v-card>
      </v-col>
      <v-col cols="6" sm="3">
        <v-card rounded="xl" elevation="0" class="pa-4 text-center">
          <div class="text-caption text-medium-emphasis">بوتات ذكور</div>
          <div class="text-h5 font-weight-bold">{{ maleBots }}</div>
        </v-card>
      </v-col>
      <v-col cols="6" sm="3">
        <v-card rounded="xl" elevation="0" class="pa-4 text-center">
          <div class="text-caption text-medium-emphasis">صور إناث متبقية</div>
          <div class="text-h5 font-weight-bold">{{ femalePhotosAvailable }}</div>
          <div class="text-caption">مستخدم {{ femalePhotosUsed }}</div>
        </v-card>
      </v-col>
      <v-col cols="6" sm="3">
        <v-card rounded="xl" elevation="0" class="pa-4 text-center">
          <div class="text-caption text-medium-emphasis">صور ذكور متبقية</div>
          <div class="text-h5 font-weight-bold">{{ malePhotosAvailable }}</div>
          <div class="text-caption">مستخدم {{ malePhotosUsed }}</div>
        </v-card>
      </v-col>
    </v-row>

    <v-card rounded="xl" elevation="0" class="pa-4">
      <div class="d-flex align-center justify-space-between py-2">
        <div>
          <div class="text-subtitle-1 font-weight-medium">إظهار البوتات في التعارف</div>
          <div class="text-body-2 text-medium-emphasis">عند الإيقاف تُستبعد من الفيد فوراً</div>
        </div>
        <v-switch v-model="enabled" color="primary" hide-details :disabled="loading" @update:model-value="save" />
      </div>

      <v-divider class="my-3" />

      <v-row dense>
        <v-col cols="12" sm="6" md="3">
          <v-text-field v-model.number="femaleTarget" type="number" min="0" max="500" label="هدف الإناث" variant="outlined" rounded="lg" hide-details="auto" />
        </v-col>
        <v-col cols="12" sm="6" md="3">
          <v-text-field v-model.number="maleTarget" type="number" min="0" max="500" label="هدف الذكور" variant="outlined" rounded="lg" hide-details="auto" />
        </v-col>
        <v-col cols="12" sm="6" md="3">
          <v-text-field v-model.number="matchPercent" type="number" min="0" max="100" label="نسبة التطابق %" variant="outlined" rounded="lg" hide-details="auto" />
        </v-col>
        <v-col cols="12" sm="6" md="3">
          <v-text-field v-model="country" label="الدولة" variant="outlined" rounded="lg" hide-details="auto" />
        </v-col>
        <v-col cols="12" sm="6" md="3">
          <v-text-field v-model.number="ageMin" type="number" min="18" max="60" label="أقل عمر" variant="outlined" rounded="lg" hide-details="auto" />
        </v-col>
        <v-col cols="12" sm="6" md="3">
          <v-text-field v-model.number="ageMax" type="number" min="18" max="60" label="أعلى عمر" variant="outlined" rounded="lg" hide-details="auto" />
        </v-col>
      </v-row>

      <div v-if="lastSyncMsg" class="mt-4 text-body-2 text-success">{{ lastSyncMsg }}</div>
    </v-card>
  </div>
</template>
