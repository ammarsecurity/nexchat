<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const randomChatEnabled = ref(true)
const loading = ref(false)
const saving = ref(false)
const saved = ref(false)

async function fetchConfig() {
  loading.value = true
  try {
    const res = await api.get('/admin/site-content/random_chat_enabled')
    const content = (res.data?.content ?? 'true').toLowerCase()
    randomChatEnabled.value = content === 'true' || content === '1'
  } catch {
    randomChatEnabled.value = true
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  saved.value = false
  try {
    await api.put('/admin/site-content/random_chat_enabled', {
      content: randomChatEnabled.value ? 'true' : 'false'
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
        <div class="text-h5 font-weight-bold">ميزات التطبيق</div>
        <div class="text-body-2 text-medium-emphasis">
          إظهار أو إخفاء عناصر في الصفحة الرئيسية لتطبيق الموبايل (iOS و Android)
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
      <div class="d-flex align-center justify-space-between py-2">
        <div>
          <div class="text-subtitle-1 font-weight-medium">إظهار الدردشة العشوائية</div>
          <div class="text-body-2 text-medium-emphasis mt-1">
            إظهار زر «ابدأ محادثة عشوائية» وفلتر المطابقة (الكل / ذكور / إناث) في الصفحة الرئيسية. عند الإلغاء، يرى المستخدم بديلاً يوجّهه للمحادثات وكود الاتصال.
          </div>
        </div>
        <v-switch
          v-model="randomChatEnabled"
          color="primary"
          hide-details
          :disabled="loading"
          @change="save"
        />
      </div>
    </v-card>
  </div>
</template>
