<script setup>
import { ref, onMounted, computed } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'

const supportAvatar = ref(null)
const avatarUploading = ref(false)
const avatarFileInput = ref(null)

const evoLoading = ref(false)
const evoSaving = ref(false)
const evoTesting = ref(false)
const evo = ref({
  enabled: false,
  baseUrl: '',
  apiKey: '',
  instanceName: '',
  messageTemplate: 'اسم الدخول: {name}\nرمز التحقق في NexChat هو: {code}\nصالح لمدة {minutes} دقائق. لا تشاركه مع أحد.',
  otpExpiryMinutes: 5,
  otpLength: 6,
})
const testDial = ref('964')
const testPhone = ref('')
const showApiKey = ref(false)

const evoReady = computed(() =>
  evo.value.enabled
  && evo.value.baseUrl?.trim()
  && evo.value.instanceName?.trim()
  && evo.value.apiKey?.trim()
)

async function fetchSupportAvatar() {
  try {
    const res = await api.get('/admin/support/avatar')
    supportAvatar.value = res.data.avatar ?? null
  } catch {
    supportAvatar.value = null
  }
}

function triggerAvatarUpload() {
  avatarFileInput.value?.click()
}

async function onAvatarFileChange(e) {
  const file = e.target?.files?.[0]
  if (!file) return
  avatarUploading.value = true
  try {
    const fd = new FormData()
    fd.append('file', file)
    const res = await api.post('/media/upload', fd, {
      headers: { 'Content-Type': 'multipart/form-data' }
    })
    await api.put('/admin/support/avatar', { avatar: res.data.url })
    supportAvatar.value = res.data.url
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل رفع الصورة')
  } finally {
    avatarUploading.value = false
    e.target.value = ''
  }
}

function isAvatarUrl(av) {
  return av && (av.startsWith('http://') || av.startsWith('https://'))
}

async function fetchEvolution() {
  evoLoading.value = true
  try {
    const res = await api.get('/admin/evolution-whatsapp')
    evo.value = {
      enabled: !!res.data.enabled,
      baseUrl: res.data.baseUrl || '',
      apiKey: res.data.apiKey || '',
      instanceName: res.data.instanceName || '',
      messageTemplate: res.data.messageTemplate
        || 'اسم الدخول: {name}\nرمز التحقق في NexChat هو: {code}\nصالح لمدة {minutes} دقائق. لا تشاركه مع أحد.',
      otpExpiryMinutes: res.data.otpExpiryMinutes || 5,
      otpLength: res.data.otpLength || 6,
    }
  } catch {
    notify.error('تعذر تحميل إعدادات واتساب')
  } finally {
    evoLoading.value = false
  }
}

async function saveEvolution() {
  evoSaving.value = true
  try {
    await api.put('/admin/evolution-whatsapp', {
      enabled: evo.value.enabled,
      baseUrl: evo.value.baseUrl.trim(),
      apiKey: evo.value.apiKey,
      instanceName: evo.value.instanceName.trim(),
      messageTemplate: evo.value.messageTemplate,
      otpExpiryMinutes: Number(evo.value.otpExpiryMinutes) || 5,
      otpLength: Number(evo.value.otpLength) || 6,
    })
    notify.success('تم حفظ إعدادات واتساب Evolution')
    await fetchEvolution()
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل الحفظ')
  } finally {
    evoSaving.value = false
  }
}

async function testEvolution() {
  if (!testPhone.value.trim()) {
    notify.error('أدخل رقم هاتف للاختبار')
    return
  }
  evoTesting.value = true
  try {
    await api.post('/admin/evolution-whatsapp/test', {
      countryCode: testDial.value,
      phoneNumber: testPhone.value.trim(),
    })
    notify.success('تم إرسال رسالة الاختبار')
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل الاختبار')
  } finally {
    evoTesting.value = false
  }
}

onMounted(() => {
  fetchSupportAvatar()
  fetchEvolution()
})
</script>

<template>
  <div class="settings-page">
    <div class="page-header mb-6">
      <div>
        <div class="text-h5 font-weight-bold">الإعدادات</div>
        <div class="text-body-2 text-medium-emphasis">
          إعدادات التطبيق والدعم وواتساب OTP
        </div>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="settings-card mb-4">
      <v-card-title class="section-title">
        <v-icon start>mdi-whatsapp</v-icon>
        واتساب Evolution — OTP
      </v-card-title>
      <v-card-text>
        <v-alert type="info" variant="tonal" rounded="lg" class="mb-4" density="comfortable">
          عند التفعيل يُستخدم واتساب لإرسال رمز تحقق عند: تأكيد الرقم في التسجيل، تعديل الرقم، واستعادة كلمة المرور.
          ضع رابط سيرفر Evolution واسم الـ Instance ومفتاح API.
        </v-alert>

        <v-skeleton-loader v-if="evoLoading" type="article" />
        <div v-else class="evo-form">
          <v-switch
            v-model="evo.enabled"
            color="primary"
            label="تفعيل التحقق عبر واتساب (OTP)"
            hide-details
            class="mb-4"
          />

          <v-text-field
            v-model="evo.baseUrl"
            label="Base URL"
            placeholder="https://evolution.example.com"
            variant="outlined"
            rounded="lg"
            density="comfortable"
            class="mb-3"
            hint="بدون شرطة في النهاية"
            persistent-hint
          />

          <v-text-field
            v-model="evo.instanceName"
            label="Instance Name"
            placeholder="nexchat"
            variant="outlined"
            rounded="lg"
            density="comfortable"
            class="mb-3"
          />

          <v-text-field
            v-model="evo.apiKey"
            label="API Key"
            :type="showApiKey ? 'text' : 'password'"
            variant="outlined"
            rounded="lg"
            density="comfortable"
            class="mb-3"
            :append-inner-icon="showApiKey ? 'mdi-eye-off' : 'mdi-eye'"
            @click:append-inner="showApiKey = !showApiKey"
          />

          <v-textarea
            v-model="evo.messageTemplate"
            label="نص رسالة OTP"
            variant="outlined"
            rounded="lg"
            rows="3"
            auto-grow
            class="mb-3"
            hint="استخدم {code} و {minutes} و {name} (اسم الدخول)"
            persistent-hint
          />

          <div class="d-flex flex-wrap gap-3 mb-4">
            <v-text-field
              v-model.number="evo.otpExpiryMinutes"
              label="صلاحية الرمز (دقائق)"
              type="number"
              min="1"
              max="30"
              variant="outlined"
              rounded="lg"
              density="comfortable"
              style="max-width: 180px"
              hide-details
            />
            <v-text-field
              v-model.number="evo.otpLength"
              label="طول الرمز"
              type="number"
              min="4"
              max="8"
              variant="outlined"
              rounded="lg"
              density="comfortable"
              style="max-width: 140px"
              hide-details
            />
          </div>

          <div class="d-flex flex-wrap gap-2 mb-6">
            <v-btn
              color="primary"
              rounded="lg"
              prepend-icon="mdi-content-save"
              :loading="evoSaving"
              @click="saveEvolution"
            >
              حفظ الإعدادات
            </v-btn>
            <v-chip v-if="evoReady" color="success" variant="tonal" size="small">جاهز للإرسال</v-chip>
            <v-chip v-else-if="evo.enabled" color="warning" variant="tonal" size="small">أكمل الحقول المطلوبة</v-chip>
          </div>

          <v-divider class="mb-4" />
          <div class="text-subtitle-2 font-weight-bold mb-2">اختبار الإرسال</div>
          <div class="d-flex flex-wrap gap-2 align-start">
            <v-text-field
              v-model="testDial"
              label="مفتاح الدولة"
              variant="outlined"
              rounded="lg"
              density="compact"
              style="max-width: 120px"
              hide-details
            />
            <v-text-field
              v-model="testPhone"
              label="رقم للاختبار"
              placeholder="7712345678"
              variant="outlined"
              rounded="lg"
              density="compact"
              style="max-width: 200px"
              hide-details
            />
            <v-btn
              color="success"
              variant="tonal"
              rounded="lg"
              prepend-icon="mdi-send"
              :loading="evoTesting"
              :disabled="!evoReady"
              @click="testEvolution"
            >
              إرسال تجريبي
            </v-btn>
          </div>
        </div>
      </v-card-text>
    </v-card>

    <v-card rounded="xl" elevation="0" class="settings-card">
      <v-card-title class="section-title">
        <v-icon start>mdi-account-circle</v-icon>
        صورة الدعم الفني
      </v-card-title>
      <v-card-text>
        <div class="avatar-section">
          <div class="avatar-preview">
            <img v-if="isAvatarUrl(supportAvatar)" :src="supportAvatar" alt="دعم" class="avatar-img" />
            <span v-else class="avatar-placeholder">{{ supportAvatar || 'د' }}</span>
          </div>
          <div class="avatar-controls">
            <input
              ref="avatarFileInput"
              type="file"
              accept="image/*"
              class="d-none"
              @change="onAvatarFileChange"
            />
            <v-btn
              color="primary"
              variant="tonal"
              prepend-icon="mdi-camera"
              rounded="lg"
              :loading="avatarUploading"
              @click="triggerAvatarUpload"
            >
              رفع صورة
            </v-btn>
          </div>
        </div>
      </v-card-text>
    </v-card>
  </div>
</template>

<style scoped>
.settings-page {
  max-width: 800px;
}

.settings-card {
  background: #F8FAFC;
  border: 1px solid rgba(15, 23, 42, 0.08);
}

.section-title {
  font-size: 1rem;
  font-weight: 600;
  padding: 20px 24px;
  border-bottom: 1px solid rgba(15, 23, 42, 0.06);
}

.avatar-section {
  display: flex;
  align-items: flex-start;
  gap: 24px;
  padding: 24px 0;
}

.avatar-preview {
  width: 80px;
  height: 80px;
  border-radius: 16px;
  overflow: hidden;
  background: linear-gradient(135deg, #2E86FB, #0EA5E9);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.avatar-placeholder {
  font-size: 32px;
  font-weight: 700;
  color: white;
}

.avatar-controls {
  flex: 1;
}

@media (max-width: 600px) {
  .avatar-section {
    flex-direction: column;
  }
}
</style>
