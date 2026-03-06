<script setup>
import { ref } from 'vue'
import api from '../services/api'

const form = ref({
  title: '',
  body: '',
  imageUrl: ''
})
const sending = ref(false)
const success = ref(false)
const recipientsCount = ref(0)

async function sendBroadcast() {
  if (!form.value.title?.trim() || !form.value.body?.trim()) {
    alert('العنوان والنص مطلوبان')
    return
  }
  sending.value = true
  success.value = false
  recipientsCount.value = 0
  try {
    const res = await api.post('/admin/notifications/broadcast', {
      title: form.value.title.trim(),
      body: form.value.body.trim(),
      imageUrl: form.value.imageUrl?.trim() || null
    })
    success.value = true
    recipientsCount.value = res.data?.recipientsCount ?? 0
    form.value = { title: '', body: '', imageUrl: '' }
  } catch (err) {
    recipientsCount.value = err.response?.data?.recipientsCount ?? 0
    alert(err.response?.data?.message || 'فشل إرسال الإشعار')
  } finally {
    sending.value = false
  }
}
</script>

<template>
  <div class="notifications-page">
    <div class="page-header mb-6">
      <div>
        <div class="text-h5 font-weight-bold">إشعارات عامة</div>
        <div class="text-body-2 text-medium-emphasis">
          إرسال إشعار push لجميع المستخدمين المشتركين
        </div>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="notifications-card">
      <v-card-title class="section-title">
        <v-icon start>mdi-bell-ring</v-icon>
        بث إشعار جديد
      </v-card-title>
      <v-card-text>
        <v-alert
          v-if="success"
          type="success"
          variant="tonal"
          class="mb-4"
          closable
        >
          تم إرسال الإشعار بنجاح إلى {{ recipientsCount }} جهاز
        </v-alert>

        <v-form @submit.prevent="sendBroadcast">
          <v-text-field
            v-model="form.title"
            label="عنوان الإشعار"
            placeholder="مثال: تحديث جديد"
            maxlength="100"
            counter="100"
            variant="outlined"
            density="comfortable"
            class="mb-3"
            :disabled="sending"
          />
          <v-textarea
            v-model="form.body"
            label="نص الإشعار"
            placeholder="اكتب محتوى الإشعار..."
            maxlength="500"
            counter="500"
            variant="outlined"
            density="comfortable"
            rows="4"
            class="mb-3"
            :disabled="sending"
          />
          <v-text-field
            v-model="form.imageUrl"
            label="رابط الصورة (اختياري)"
            placeholder="https://..."
            variant="outlined"
            density="comfortable"
            class="mb-4"
            :disabled="sending"
          />
          <v-btn
            type="submit"
            color="primary"
            size="large"
            rounded="lg"
            prepend-icon="mdi-send"
            :loading="sending"
          >
            إرسال للجميع
          </v-btn>
        </v-form>
      </v-card-text>
    </v-card>
  </div>
</template>

<style scoped>
.notifications-page {
  max-width: 600px;
}

.notifications-card {
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.section-title {
  font-size: 1rem;
  font-weight: 600;
  padding: 20px 24px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}
</style>
