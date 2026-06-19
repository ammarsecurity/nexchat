<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'

const randomChatEnabled = ref(true)
const codeConnectFeaturesEnabled = ref(true)
const shortFilmsEnabled = ref(true)
const loading = ref(false)
const saving = ref(false)
const saved = ref(false)

function parseBoolContent(content) {
  if (content === undefined || content === null || String(content).trim() === '') return true
  const c = String(content).toLowerCase()
  return c === 'true' || c === '1'
}

async function fetchConfig() {
  loading.value = true
  try {
    const [randomRes, codeRes, filmsRes] = await Promise.all([
      api.get('/admin/site-content/random_chat_enabled'),
      api.get('/admin/site-content/code_connect_features_enabled'),
      api.get('/admin/site-content/short_films_enabled')
    ])
    randomChatEnabled.value = parseBoolContent(randomRes.data?.content)
    codeConnectFeaturesEnabled.value = parseBoolContent(codeRes.data?.content)
    shortFilmsEnabled.value = parseBoolContent(filmsRes.data?.content)
  } catch {
    randomChatEnabled.value = true
    codeConnectFeaturesEnabled.value = true
    shortFilmsEnabled.value = true
  } finally {
    loading.value = false
  }
}

async function saveAll() {
  saving.value = true
  saved.value = false
  try {
    await Promise.all([
      api.put('/admin/site-content/random_chat_enabled', {
        content: randomChatEnabled.value ? 'true' : 'false'
      }),
      api.put('/admin/site-content/code_connect_features_enabled', {
        content: codeConnectFeaturesEnabled.value ? 'true' : 'false'
      }),
      api.put('/admin/site-content/short_films_enabled', {
        content: shortFilmsEnabled.value ? 'true' : 'false'
      })
    ])
    saved.value = true
    setTimeout(() => { saved.value = false }, 3000)
  } catch (err) {
    notify.error(err.response?.data?.message || 'فشل الحفظ')
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
        <div class="text-h5 font-weight-bold">ميزات التطبيق</div>
        <div class="text-body-2 text-medium-emphasis">
          إظهار أو إخفاء عناصر في تطبيق الموبايل (iOS و Android). إيقاف المفتاحين الأولين معاً يفعّل وضع «محادثات فقط» لمراجعة App Store.
        </div>
      </div>
      <v-btn
        color="primary"
        prepend-icon="mdi-content-save"
        rounded="lg"
        :loading="saving"
        :disabled="loading"
        @click="saveAll"
      >
        {{ saved ? 'تم الحفظ' : 'حفظ' }}
      </v-btn>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-4 mb-4">
      <v-alert
        type="info"
        variant="tonal"
        rounded="lg"
        class="mb-0"
        title="وضع مراجعة App Store (محادثات فقط)"
      >
        لإخفاء الدردشة العشوائية والاتصال بالكود بالكامل من تطبيق iOS/Android (مثلاً أثناء مراجعة Apple):
        أوقف <strong>الدردشة العشوائية</strong> و<strong>الاتصال بالكود</strong> معاً. يبقى للمستخدم: المحادثات، طلبات المراسلة، المجموعات، وجهات الاتصال فقط — بدون تبويب «اتصال» وبدون أكواد NX.
      </v-alert>
    </v-card>

    <v-card rounded="xl" elevation="0" class="pa-4">
      <div class="d-flex align-center justify-space-between py-2">
        <div>
          <div class="text-subtitle-1 font-weight-medium">إظهار الدردشة العشوائية</div>
          <div class="text-body-2 text-medium-emphasis mt-1">
            إظهار زر «ابدأ محادثة عشوائية» وفلتر المطابقة في تبويب الاتصال. عند الإلغاء يُخفى البحث العشوائي ويُمنع الوصول لمسارات `/matching` و`/chat` من التطبيق والخادم.
          </div>
        </div>
        <v-switch
          v-model="randomChatEnabled"
          color="primary"
          hide-details
          :disabled="loading"
          @update:model-value="saveAll"
        />
      </div>

      <v-divider class="my-2" />

      <div class="d-flex align-center justify-space-between py-2">
        <div>
          <div class="text-subtitle-1 font-weight-medium">إظهار الاتصال بالكود والأكواد المحفوظة</div>
          <div class="text-body-2 text-medium-emphasis mt-1">
            إظهار الاتصال بكود NX، الأكواد المحفوظة، دردشة الدعم، وروابط الدعوة. عند الإلغاء تُخفى كل واجهات الكود وتُحظر واجهات API المرتبطة.
          </div>
        </div>
        <v-switch
          v-model="codeConnectFeaturesEnabled"
          color="primary"
          hide-details
          :disabled="loading"
          @update:model-value="saveAll"
        />
      </div>

      <v-divider class="my-2" />

      <div class="d-flex align-center justify-space-between py-2">
        <div>
          <div class="text-subtitle-1 font-weight-medium">إظهار الأفلام القصيرة</div>
          <div class="text-body-2 text-medium-emphasis mt-1">
            إظهار مدخل الأفلام القصيرة في الصفحة الرئيسية والمحادثات، وصفحة المشاهدة في التطبيق.
          </div>
        </div>
        <v-switch
          v-model="shortFilmsEnabled"
          color="primary"
          hide-details
          :disabled="loading"
          @update:model-value="saveAll"
        />
      </div>
    </v-card>
  </div>
</template>
