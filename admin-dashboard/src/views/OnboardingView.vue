<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const loading = ref(false)
const saving = ref(false)
const snackbar = ref(false)
const snackbarText = ref('')
const snackbarColor = ref('success')
const enabled = ref(true)
const slides = ref([])

function showSnackbar(text, color = 'success') {
  snackbarText.value = text
  snackbarColor.value = color
  snackbar.value = true
}

const defaultSlides = [
  { title: 'مرحباً بك في NexChat', description: 'تواصل مع أشخاص جدد من حول العالم', imageUrl: '' },
  { title: 'محادثات عشوائية', description: 'ابدأ محادثة مع شخص جديد بنقرة واحدة', imageUrl: '' },
  { title: 'مكالمات فيديو', description: 'تواصل وجهًا لوجه مع من تتحدث', imageUrl: '' }
]

async function fetchOnboarding() {
  loading.value = true
  try {
    const res = await api.get('/admin/site-content/onboarding')
    const raw = res.data?.content ?? res.data?.Content ?? ''
    if (raw) {
      try {
        const parsed = JSON.parse(raw)
        enabled.value = parsed.enabled !== false
        slides.value = Array.isArray(parsed.slides) && parsed.slides.length > 0
          ? parsed.slides
          : [...defaultSlides]
      } catch {
        slides.value = [...defaultSlides]
      }
    } else {
      slides.value = [...defaultSlides]
    }
  } catch {
    slides.value = [...defaultSlides]
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  try {
    const toSave = {
      enabled: enabled.value,
      slides: slides.value.map((s, i) => ({
        title: s.title?.trim() || '',
        description: s.description?.trim() || '',
        imageUrl: s.imageUrl?.trim() || '',
        order: i
      }))
    }
    await api.put('/admin/site-content/onboarding', {
      content: JSON.stringify(toSave)
    })
    showSnackbar('تم الحفظ بنجاح')
  } catch (err) {
    const msg = err.response?.data?.message || err.response?.data?.title || err.message || 'حدث خطأ'
    showSnackbar(msg, 'error')
  } finally {
    saving.value = false
  }
}

function addSlide() {
  slides.value.push({ title: '', description: '', imageUrl: '' })
}

function removeSlide(i) {
  slides.value.splice(i, 1)
}

function moveUp(i) {
  if (i <= 0) return
  ;[slides.value[i], slides.value[i - 1]] = [slides.value[i - 1], slides.value[i]]
}

function moveDown(i) {
  if (i >= slides.value.length - 1) return
  ;[slides.value[i], slides.value[i + 1]] = [slides.value[i + 1], slides.value[i]]
}

onMounted(fetchOnboarding)
</script>

<template>
  <div>
    <v-card class="mb-6" color="#16162A" variant="flat">
      <v-card-title class="d-flex align-center justify-space-between flex-wrap">
        <span>الصفحات الاسترشادية (Onboarding)</span>
        <v-btn color="primary" :loading="saving" @click="save">
          حفظ
        </v-btn>
      </v-card-title>
      <v-card-subtitle class="text-medium-emphasis">
        تظهر للمستخدمين الجدد عند أول فتح للتطبيق. يمكنك تفعيلها أو تعطيلها وتعديل المحتوى.
      </v-card-subtitle>
      <div class="mt-4">
        <v-switch
          v-model="enabled"
          color="primary"
          hide-details
          label="تفعيل الصفحات الاسترشادية"
        />
      </div>
    </v-card>

    <v-card v-if="loading" color="#16162A" variant="flat" class="pa-8 text-center">
      <v-progress-circular indeterminate color="primary" />
    </v-card>

    <v-card v-else color="#16162A" variant="flat" class="pa-4">
      <div class="d-flex align-center justify-space-between mb-4">
        <span class="text-h6">الشريحة</span>
        <v-btn color="primary" variant="tonal" size="small" @click="addSlide">
          إضافة شريحة
        </v-btn>
      </div>

      <div
        v-for="(slide, i) in slides"
        :key="i"
        class="slide-card mb-4 pa-4"
        style="border: 1px solid rgba(255,255,255,0.08); border-radius: 12px;"
      >
        <div class="d-flex align-center justify-space-between mb-3">
          <span class="text-body-2 text-medium-emphasis">شريحة {{ i + 1 }}</span>
          <div class="d-flex gap-1">
            <v-btn icon size="small" variant="text" :disabled="i === 0" @click="moveUp(i)">
              <v-icon>mdi-chevron-up</v-icon>
            </v-btn>
            <v-btn icon size="small" variant="text" :disabled="i === slides.length - 1" @click="moveDown(i)">
              <v-icon>mdi-chevron-down</v-icon>
            </v-btn>
            <v-btn icon size="small" variant="text" color="error" :disabled="slides.length <= 1" @click="removeSlide(i)">
              <v-icon>mdi-delete</v-icon>
            </v-btn>
          </div>
        </div>
        <v-text-field
          v-model="slide.title"
          label="العنوان"
          density="compact"
          variant="outlined"
          hide-details
          class="mb-3"
        />
        <v-textarea
          v-model="slide.description"
          label="الوصف"
          density="compact"
          variant="outlined"
          hide-details
          rows="2"
          class="mb-3"
        />
        <v-text-field
          v-model="slide.imageUrl"
          label="رابط الصورة (اختياري)"
          density="compact"
          variant="outlined"
          hide-details
          placeholder="https://..."
        />
      </div>
    </v-card>

    <v-snackbar
      v-model="snackbar"
      :color="snackbarColor"
      :timeout="4000"
      location="bottom"
    >
      {{ snackbarText }}
    </v-snackbar>
  </div>
</template>
