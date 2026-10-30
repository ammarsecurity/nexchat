<script setup>
import { ref, computed, onMounted } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'

const randomChatEnabled = ref(true)
const discoverSwipeEnabled = ref(true)
const shortFilmsEnabled = ref(true)
const loading = ref(false)
const saving = ref(false)
const saved = ref(false)

/** Messaging-only App Store mode: instant chat + discover off (code connect removed). */
const messagingOnlyMode = computed(
  () => !randomChatEnabled.value && !discoverSwipeEnabled.value
)

function parseBoolContent(content, { emptyMeans = true } = {}) {
  if (content === undefined || content === null || String(content).trim() === '') return emptyMeans
  const c = String(content).toLowerCase()
  return c === 'true' || c === '1'
}

async function fetchConfig() {
  loading.value = true
  try {
    const [randomRes, discoverRes, filmsRes] = await Promise.all([
      api.get('/admin/site-content/random_chat_enabled'),
      api.get('/admin/site-content/discover_swipe_enabled'),
      api.get('/admin/site-content/short_films_enabled'),
      // Retired feature: always keep code connect off.
      api.put('/admin/site-content/code_connect_features_enabled', { content: 'false' }).catch(() => null)
    ])
    randomChatEnabled.value = parseBoolContent(randomRes.data?.content, { emptyMeans: false })
    discoverSwipeEnabled.value = parseBoolContent(discoverRes.data?.content, { emptyMeans: true })
    shortFilmsEnabled.value = parseBoolContent(filmsRes.data?.content, { emptyMeans: false })
  } catch {
    randomChatEnabled.value = true
    discoverSwipeEnabled.value = true
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
      // Code connect UI removed from the app — keep the flag forced off.
      api.put('/admin/site-content/code_connect_features_enabled', {
        content: 'false'
      }),
      api.put('/admin/site-content/discover_swipe_enabled', {
        content: discoverSwipeEnabled.value ? 'true' : 'false'
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
          إظهار أو إخفاء عناصر في تطبيق الموبايل (iOS و Android). إيقاف المحادثة الفورية والتعارف معاً يفعّل وضع «محادثات فقط» لمراجعة App Store.
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
        لإخفاء التعارف والمحادثة الفورية من تطبيق iOS/Android (مثلاً أثناء مراجعة Apple):
        أوقف <strong>المحادثة الفورية</strong> و<strong>التعارف (Discover)</strong> معاً.
        يبقى للمستخدم: المحادثات، طلبات المراسلة، المجموعات، وجهات الاتصال، والإعدادات — بدون تبويب «تعارف / العالم».
        <template v-if="shortFilmsEnabled"> تبويب «اكتشف» (الأفلام القصيرة) يبقى ظاهراً إن كان مفعّلاً أدناه.</template>
        <div v-if="messagingOnlyMode" class="mt-2 text-success font-weight-medium">
          الوضع الحالي: محادثات فقط (المحادثة الفورية والتعارف متوقفان).
        </div>
      </v-alert>
    </v-card>

    <v-card rounded="xl" elevation="0" class="pa-4">
      <div class="d-flex align-center justify-space-between py-2">
        <div class="me-4">
          <div class="text-subtitle-1 font-weight-medium">إظهار المحادثة الفورية</div>
          <div class="text-body-2 text-medium-emphasis mt-1">
            إظهار صفحة «محادثة فورية» (بحث فوري فقط، بلون مميز) داخل تبويب العالم مع التعارف. عند الإلغاء تُخفى ويُمنع `/matching` و`/chat`.
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
        <div class="me-4">
          <div class="text-subtitle-1 font-weight-medium">إظهار التعارف (Discover)</div>
          <div class="text-body-2 text-medium-emphasis mt-1">
            تفعيل التعارف (سحب البطاقات). إن كانت المحادثة الفورية مفعّلة أيضاً تظهران معاً في تبويب واحد «العالم». عند الإلغاء يُحظر `/api/discover`.
          </div>
        </div>
        <v-switch
          v-model="discoverSwipeEnabled"
          color="primary"
          hide-details
          :disabled="loading"
          @update:model-value="saveAll"
        />
      </div>

      <v-divider class="my-2" />

      <div class="d-flex align-center justify-space-between py-2">
        <div class="me-4">
          <div class="text-subtitle-1 font-weight-medium">إظهار الأفلام القصيرة</div>
          <div class="text-body-2 text-medium-emphasis mt-1">
            إظهار تبويب «اكتشف» ومدخل الأفلام القصيرة في الصفحة الرئيسية وصفحة المشاهدة في التطبيق.
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
