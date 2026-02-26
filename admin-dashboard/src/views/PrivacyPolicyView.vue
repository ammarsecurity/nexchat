<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const content = ref('')
const loading = ref(false)
const saving = ref(false)
const saved = ref(false)

async function fetchContent() {
  loading.value = true
  try {
    const res = await api.get('/admin/site-content/privacy_policy')
    content.value = res.data.content || ''
  } catch {
    content.value = ''
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  saved.value = false
  try {
    await api.put('/admin/site-content/privacy_policy', { content: content.value })
    saved.value = true
    setTimeout(() => { saved.value = false }, 3000)
  } catch (err) {
    alert(err.response?.data?.message || 'فشل الحفظ')
  } finally {
    saving.value = false
  }
}

onMounted(fetchContent)
</script>

<template>
  <div>
    <div class="d-flex align-center justify-space-between mb-6">
      <div>
        <div class="text-h5 font-weight-bold">سياسة الخصوصية</div>
        <div class="text-body-2 text-medium-emphasis">تعديل نص سياسة الخصوصية المعروض في التطبيق</div>
      </div>
      <v-btn
        color="primary"
        prepend-icon="mdi-content-save"
        rounded="lg"
        :loading="saving"
        @click="save"
      >
        {{ saved ? 'تم الحفظ' : 'حفظ' }}
      </v-btn>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-4">
      <v-textarea
        v-model="content"
        label="نص سياسة الخصوصية"
        placeholder="اكتب سياسة الخصوصية هنا... يمكن استخدام أسطر جديدة."
        variant="outlined"
        rounded="lg"
        rows="20"
        auto-grow
        hide-details
        class="mb-4"
      />
      <div class="text-caption text-medium-emphasis">
        سيظهر هذا النص في صفحة سياسة الخصوصية في تطبيق الموبايل. استخدم Enter للأسطر الجديدة.
      </div>
    </v-card>
  </div>
</template>
