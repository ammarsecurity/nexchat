<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const loading = ref(false)
const saving = ref(false)
const snackbar = ref(false)
const snackbarText = ref('')
const snackbarColor = ref('success')
const links = ref([])

const platforms = [
  { id: 'twitter', label: 'تويتر (X)', icon: 'mdi-twitter' },
  { id: 'instagram', label: 'انستغرام', icon: 'mdi-instagram' },
  { id: 'facebook', label: 'فيسبوك', icon: 'mdi-facebook' },
  { id: 'tiktok', label: 'تيك توك', icon: null }, // مخصص: أيقونة TikTok غير موجودة في MDI
  { id: 'youtube', label: 'يوتيوب', icon: 'mdi-youtube' },
  { id: 'linkedin', label: 'لينكد إن', icon: 'mdi-linkedin' },
  { id: 'whatsapp', label: 'واتساب', icon: 'mdi-whatsapp' },
  { id: 'telegram', label: 'تيليجرام', icon: 'mdi-send' }
]

function showSnackbar(text, color = 'success') {
  snackbarText.value = text
  snackbarColor.value = color
  snackbar.value = true
}

async function fetchLinks() {
  loading.value = true
  try {
    const res = await api.get('/admin/site-content/social_links')
    const raw = res.data?.content ?? res.data?.Content ?? ''
    const content = typeof raw === 'string' ? raw : ''
    if (content) {
      try {
        const parsed = JSON.parse(content)
        links.value = Array.isArray(parsed) ? parsed : []
      } catch {
        links.value = []
      }
    } else {
      links.value = []
    }
    if (links.value.length === 0) {
      links.value = platforms.map(p => ({ platform: p.id, url: '' }))
    }
    const existingIds = new Set(links.value.map(l => l.platform))
    platforms.forEach(p => {
      if (!existingIds.has(p.id)) {
        links.value.push({ platform: p.id, url: '' })
      }
    })
  } catch (err) {
    links.value = platforms.map(p => ({ platform: p.id, url: '' }))
    showSnackbar(err.response?.data?.message || 'فشل تحميل البيانات', 'error')
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  try {
    const toSave = links.value
      .filter(l => l.url?.trim())
      .map(l => ({ platform: l.platform, url: l.url.trim() }))
    await api.put('/admin/site-content/social_links', {
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

function getPlatform(p) {
  return platforms.find(x => x.id === p) || { id: p, label: p, icon: 'mdi-link' }
}

onMounted(fetchLinks)
</script>

<template>
  <div>
    <v-card class="mb-6" color="#16162A" variant="flat">
      <v-card-title class="d-flex align-center justify-space-between">
        <span>روابط التواصل الاجتماعي</span>
        <v-btn color="primary" :loading="saving" @click="save">
          حفظ
        </v-btn>
      </v-card-title>
      <v-card-subtitle class="text-medium-emphasis">
        الروابط تظهر في فوتر تطبيق الموبايل
      </v-card-subtitle>
    </v-card>

    <v-card v-if="loading" color="#16162A" variant="flat" class="pa-8 text-center">
      <v-progress-circular indeterminate color="primary" />
    </v-card>

    <v-card v-else color="#16162A" variant="flat" class="pa-4">
      <div
        v-for="(link, i) in links"
        :key="link.platform"
        class="d-flex align-center mb-4 social-link-row"
      >
        <component
          :is="getPlatform(link.platform).icon ? 'v-icon' : 'span'"
          v-if="getPlatform(link.platform).icon"
          :icon="getPlatform(link.platform).icon"
          color="primary"
          size="24"
          class="mr-3"
        />
        <span v-else class="tiktok-icon-wrap mr-3">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            width="24"
            height="24"
            class="tiktok-icon"
            fill="currentColor"
          >
            <path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-5.2 1.74 2.89 2.89 0 0 1 2.31-4.64 2.93 2.93 0 0 1 .88.13V9.4a6.84 6.84 0 0 0-1-.05A6.33 6.33 0 0 0 5 20.1a6.34 6.34 0 0 0 10.86-4.43v-7a8.16 8.16 0 0 0 4.77 1.52v-3.4a4.85 4.85 0 0 1-1-.1z"/>
          </svg>
        </span>
        <span class="text-body-2 mr-3" style="min-width: 120px">{{ getPlatform(link.platform).label }}</span>
        <v-text-field
          v-model="link.url"
          density="compact"
          placeholder="https://..."
          hide-details
          variant="outlined"
          class="flex-grow-1"
          style="max-width: 400px"
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

<style scoped>
.social-link-row {
  flex-wrap: wrap;
}
.tiktok-icon-wrap {
  display: inline-flex;
  align-items: center;
  flex-shrink: 0;
  color: #6C63FF;
}
.tiktok-icon {
  display: block;
}
</style>
