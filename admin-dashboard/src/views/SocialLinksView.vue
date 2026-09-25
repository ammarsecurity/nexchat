<script setup>
import { ref, computed, onMounted } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'

const loading = ref(false)
const saving = ref(false)
const links = ref([])

const platforms = [
  { id: 'facebook', label: 'فيسبوك', icon: 'mdi-facebook', color: '#1877F2', hint: 'https://facebook.com/...' },
  { id: 'twitter', label: 'تويتر (X)', icon: 'mdi-twitter', color: '#0F1419', hint: 'https://x.com/...' },
  { id: 'instagram', label: 'انستغرام', icon: 'mdi-instagram', color: '#E4405F', hint: 'https://instagram.com/...' },
  { id: 'tiktok', label: 'تيك توك', icon: null, color: '#111111', hint: 'https://tiktok.com/@...' },
  { id: 'youtube', label: 'يوتيوب', icon: 'mdi-youtube', color: '#FF0000', hint: 'https://youtube.com/...' },
  { id: 'linkedin', label: 'لينكد إن', icon: 'mdi-linkedin', color: '#0A66C2', hint: 'https://linkedin.com/...' },
  { id: 'whatsapp', label: 'واتساب', icon: 'mdi-whatsapp', color: '#25D366', hint: 'https://wa.me/9647...' },
  { id: 'telegram', label: 'تيليجرام', icon: 'mdi-send', color: '#2AABEE', hint: 'https://t.me/...' },
]

const filledCount = computed(() => links.value.filter((l) => l.url?.trim()).length)

function getPlatform(id) {
  return platforms.find((x) => x.id === id) || { id, label: id, icon: 'mdi-link', color: '#2E86FB', hint: 'https://...' }
}

async function fetchLinks() {
  loading.value = true
  try {
    const res = await api.get('/admin/site-content/social_links')
    const raw = res.data?.content ?? res.data?.Content ?? ''
    const content = typeof raw === 'string' ? raw : ''
    let parsed = []
    if (content) {
      try {
        const data = JSON.parse(content)
        parsed = Array.isArray(data) ? data : []
      } catch {
        parsed = []
      }
    }
    const byId = new Map(parsed.map((l) => [l.platform, l.url || '']))
    links.value = platforms.map((p) => ({
      platform: p.id,
      url: byId.get(p.id) || '',
    }))
  } catch (err) {
    links.value = platforms.map((p) => ({ platform: p.id, url: '' }))
    notify.error(err.response?.data?.message || 'فشل تحميل البيانات')
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  try {
    const toSave = links.value
      .filter((l) => l.url?.trim())
      .map((l) => ({ platform: l.platform, url: l.url.trim() }))
    await api.put('/admin/site-content/social_links', {
      content: JSON.stringify(toSave),
    })
    notify.success('تم الحفظ بنجاح')
  } catch (err) {
    const msg = err.response?.data?.message || err.response?.data?.title || err.message || 'حدث خطأ'
    notify.error(msg)
  } finally {
    saving.value = false
  }
}

onMounted(fetchLinks)
</script>

<template>
  <div class="social-page">
    <div class="page-header mb-6">
      <div>
        <div class="page-title">التواصل الاجتماعي</div>
        <div class="page-subtitle">الروابط تظهر في ملف تطبيق الموبايل — اترك الحقل فارغاً لإخفاء المنصة</div>
      </div>
      <div class="page-actions">
        <v-chip v-if="!loading" size="small" variant="tonal" color="primary">
          {{ filledCount }} مفعّل
        </v-chip>
        <v-btn color="primary" rounded="lg" prepend-icon="mdi-content-save" :loading="saving" :disabled="loading" @click="save">
          حفظ
        </v-btn>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="social-card">
      <v-card-text class="pa-4 pa-sm-6">
        <div v-if="loading" class="text-center py-12">
          <v-progress-circular indeterminate color="primary" size="40" />
        </div>

        <div v-else class="social-list">
          <div v-for="link in links" :key="link.platform" class="social-row">
            <div class="social-meta">
              <div class="social-icon" :style="{ background: getPlatform(link.platform).color + '18', color: getPlatform(link.platform).color }">
                <v-icon v-if="getPlatform(link.platform).icon" size="22">{{ getPlatform(link.platform).icon }}</v-icon>
                <svg
                  v-else
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 24 24"
                  width="20"
                  height="20"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-5.2 1.74 2.89 2.89 0 0 1 2.31-4.64 2.93 2.93 0 0 1 .88.13V9.4a6.84 6.84 0 0 0-1-.05A6.33 6.33 0 0 0 5 20.1a6.34 6.34 0 0 0 10.86-4.43v-7a8.16 8.16 0 0 0 4.77 1.52v-3.4a4.85 4.85 0 0 1-1-.1z" />
                </svg>
              </div>
              <div class="social-label">
                <div class="social-name">{{ getPlatform(link.platform).label }}</div>
                <div class="social-hint">{{ getPlatform(link.platform).hint }}</div>
              </div>
            </div>

            <v-text-field
              v-model="link.url"
              :label="'رابط ' + getPlatform(link.platform).label"
              :placeholder="getPlatform(link.platform).hint"
              variant="outlined"
              density="comfortable"
              rounded="lg"
              hide-details="auto"
              clearable
              dir="ltr"
              class="social-input"
              prepend-inner-icon="mdi-link-variant"
            />
          </div>
        </div>
      </v-card-text>
    </v-card>
  </div>
</template>

<style scoped>
.social-page {
  max-width: 920px;
}

.page-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  flex-wrap: wrap;
}

.social-card {
  background: #fff !important;
  border: 1px solid rgba(15, 23, 42, 0.08) !important;
  box-shadow: 0 4px 14px rgba(15, 35, 80, 0.05) !important;
}

.social-list {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.social-row {
  display: grid;
  grid-template-columns: minmax(160px, 220px) 1fr;
  gap: 16px;
  align-items: center;
  padding: 16px;
  border-radius: 16px;
  background: #F8FAFC;
  border: 1px solid rgba(15, 23, 42, 0.06);
}

.social-meta {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
}

.social-icon {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.social-label {
  min-width: 0;
}

.social-name {
  font-size: 15px;
  font-weight: 700;
  color: #0B1220;
  line-height: 1.3;
}

.social-hint {
  font-size: 12px;
  color: #94A3B8;
  margin-top: 2px;
  direction: ltr;
  text-align: start;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.social-input {
  width: 100%;
  min-width: 0;
}

.social-input :deep(input) {
  font-family: ui-monospace, 'Cascadia Code', 'Segoe UI', monospace;
  font-size: 13px;
}

@media (max-width: 700px) {
  .social-row {
    grid-template-columns: 1fr;
    gap: 12px;
  }
}
</style>
