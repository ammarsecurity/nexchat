<script setup>
import { ref, computed, onMounted } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'

const loading = ref(false)
const saving = ref(false)
const probing = ref(false)
const showKey = ref(false)
const showSecret = ref(false)

const form = ref({
  url: '',
  apiKey: '',
  apiSecret: '',
  hasApiKey: false,
  hasApiSecret: false,
  configured: false,
  httpHost: '',
  source: 'appsettings',
})

const probe = ref(null)

const sourceLabel = computed(() =>
  form.value.source === 'database' ? 'قاعدة البيانات (لوحة التحكم)' : 'appsettings.json (افتراضي)'
)

async function fetchSettings() {
  loading.value = true
  probe.value = null
  try {
    const res = await api.get('/admin/livekit')
    form.value = {
      url: res.data.url || '',
      apiKey: res.data.apiKey || '',
      apiSecret: res.data.apiSecret || '',
      hasApiKey: !!res.data.hasApiKey,
      hasApiSecret: !!res.data.hasApiSecret,
      configured: !!res.data.configured,
      httpHost: res.data.httpHost || '',
      source: res.data.source || 'appsettings',
    }
  } catch (err) {
    notify.error(err.response?.data?.message || 'تعذر تحميل إعدادات LiveKit')
  } finally {
    loading.value = false
  }
}

async function saveSettings() {
  saving.value = true
  try {
    await api.put('/admin/livekit', {
      url: form.value.url.trim(),
      apiKey: form.value.apiKey,
      apiSecret: form.value.apiSecret,
    })
    notify.success('تم حفظ إعدادات LiveKit')
    await fetchSettings()
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل الحفظ')
  } finally {
    saving.value = false
  }
}

async function runProbe() {
  probing.value = true
  probe.value = null
  try {
    // Server HttpClient is 12s — keep client above that so 422 probe body still arrives.
    const res = await api.post('/admin/livekit/probe', null, { timeout: 20000 })
    probe.value = res.data
    if (res.data?.ok) notify.success(res.data.message || 'LiveKit يعمل')
    else notify.error(res.data?.message || 'LiveKit غير متصل')
  } catch (err) {
    const data = err.response?.data
    if (data && typeof data === 'object' && Array.isArray(data.checks)) {
      probe.value = data
      notify.error(data.message || 'فشل الفحص')
    } else if (err.code === 'ECONNABORTED') {
      notify.error('انتهت مهلة الفحص — تحقق من رابط السيرفر')
    } else {
      notify.error(data?.message || 'فشل فحص LiveKit')
    }
  } finally {
    probing.value = false
  }
}

onMounted(fetchSettings)
</script>

<template>
  <div class="livekit-page">
    <div class="d-flex align-center justify-space-between mb-6 flex-wrap ga-3">
      <div>
        <div class="text-h5 font-weight-bold">LiveKit — المكالمات</div>
        <div class="text-body-2 text-medium-emphasis">
          فحص اتصال سيرفر المكالمات وتعديل Url و ApiKey و ApiSecret
        </div>
      </div>
      <div class="d-flex ga-2 flex-wrap">
        <v-btn
          variant="tonal"
          color="primary"
          prepend-icon="mdi-refresh"
          rounded="lg"
          :loading="loading"
          @click="fetchSettings"
        >
          تحديث
        </v-btn>
        <v-btn
          color="success"
          prepend-icon="mdi-stethoscope"
          rounded="lg"
          :loading="probing"
          :disabled="loading"
          @click="runProbe"
        >
          فحص شامل
        </v-btn>
        <v-btn
          color="primary"
          prepend-icon="mdi-content-save"
          rounded="lg"
          :loading="saving"
          :disabled="loading"
          @click="saveSettings"
        >
          حفظ
        </v-btn>
      </div>
    </div>

    <v-row>
      <v-col cols="12" md="7">
        <v-card rounded="xl" elevation="0" class="pa-4 mb-4">
          <v-skeleton-loader v-if="loading" type="article" />
          <div v-else>
            <div class="d-flex align-center justify-space-between mb-4 flex-wrap ga-2">
              <div class="text-subtitle-1 font-weight-medium">الإعدادات</div>
              <v-chip size="small" :color="form.configured ? 'success' : 'warning'" variant="tonal">
                {{ form.configured ? 'مكتمل' : 'غير مكتمل' }}
              </v-chip>
            </div>

            <v-alert type="info" variant="tonal" rounded="lg" class="mb-4" density="comfortable">
              المصدر الحالي: <strong>{{ sourceLabel }}</strong>.
              عند الحفظ تُحفظ القيم في قاعدة البيانات وتتجاوز appsettings.json فوراً بدون إعادة تشغيل.
              اترك المفتاح/السر كما هو (مقنّع) إن لم ترد تغييره.
            </v-alert>

            <v-text-field
              v-model="form.url"
              label="LiveKit URL (WSS)"
              placeholder="wss://livekit.example.com"
              variant="outlined"
              rounded="lg"
              density="comfortable"
              class="mb-3"
              hint="رابط WebSocket للعملاء — يُحوَّل تلقائياً لـ HTTPS عند الفحص"
              persistent-hint
            />

            <v-text-field
              v-if="form.httpHost"
              :model-value="form.httpHost"
              label="HTTP Host (لـ Room Service)"
              variant="outlined"
              rounded="lg"
              density="comfortable"
              class="mb-3"
              readonly
              hide-details
            />

            <v-text-field
              v-model="form.apiKey"
              label="Api Key"
              variant="outlined"
              rounded="lg"
              density="comfortable"
              class="mb-3"
              :type="showKey ? 'text' : 'password'"
              :append-inner-icon="showKey ? 'mdi-eye-off' : 'mdi-eye'"
              @click:append-inner="showKey = !showKey"
            />

            <v-text-field
              v-model="form.apiSecret"
              label="Api Secret"
              variant="outlined"
              rounded="lg"
              density="comfortable"
              class="mb-1"
              :type="showSecret ? 'text' : 'password'"
              :append-inner-icon="showSecret ? 'mdi-eye-off' : 'mdi-eye'"
              hint="32 حرفاً على الأقل"
              persistent-hint
              @click:append-inner="showSecret = !showSecret"
            />
          </div>
        </v-card>
      </v-col>

      <v-col cols="12" md="5">
        <v-card rounded="xl" elevation="0" class="pa-4 mb-4">
          <div class="text-subtitle-1 font-weight-medium mb-3">نتيجة الفحص</div>

          <v-alert
            v-if="!probe && !probing"
            type="info"
            variant="tonal"
            rounded="lg"
            density="comfortable"
          >
            اضغط «فحص شامل» للتحقق من المفاتيح والاتصال بالسيرفر (ListRooms).
          </v-alert>

          <div v-if="probing" class="text-center py-8">
            <v-progress-circular indeterminate color="primary" size="48" />
            <div class="mt-3 text-medium-emphasis">جاري الفحص…</div>
          </div>

          <template v-if="probe && !probing">
            <v-alert
              :type="probe.ok ? 'success' : 'error'"
              variant="tonal"
              rounded="lg"
              class="mb-4"
              :title="probe.ok ? 'متصل' : 'غير متصل'"
            >
              {{ probe.message }}
            </v-alert>

            <div class="meta-grid mb-4">
              <div class="meta-item">
                <div class="meta-label">Latency</div>
                <div class="meta-value">{{ probe.latencyMs != null ? `${probe.latencyMs} ms` : '—' }}</div>
              </div>
              <div class="meta-item">
                <div class="meta-label">غرف نشطة</div>
                <div class="meta-value">{{ probe.roomCount != null ? probe.roomCount : '—' }}</div>
              </div>
            </div>

            <v-list density="compact" class="bg-transparent">
              <v-list-item
                v-for="(c, i) in probe.checks || []"
                :key="i"
                :prepend-icon="c.ok ? 'mdi-check-circle' : 'mdi-close-circle'"
                :title="c.name"
                :subtitle="c.detail || ''"
                :class="c.ok ? 'check-ok' : 'check-fail'"
              />
            </v-list>
          </template>
        </v-card>
      </v-col>
    </v-row>
  </div>
</template>

<style scoped>
.livekit-page :deep(.v-card) {
  border: 1px solid rgba(var(--v-border-color), var(--v-border-opacity));
}
.meta-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
.meta-item {
  padding: 12px 14px;
  border-radius: 14px;
  background: rgba(var(--v-theme-on-surface), 0.04);
}
.meta-label {
  font-size: 12px;
  opacity: 0.65;
}
.meta-value {
  font-size: 18px;
  font-weight: 700;
  margin-top: 2px;
}
.check-ok :deep(.v-list-item__prepend .v-icon) {
  color: rgb(var(--v-theme-success));
}
.check-fail :deep(.v-list-item__prepend .v-icon) {
  color: rgb(var(--v-theme-error));
}
</style>
