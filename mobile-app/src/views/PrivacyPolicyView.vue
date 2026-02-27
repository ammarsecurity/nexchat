<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight } from 'lucide-vue-next'
import LoaderOverlay from '../components/LoaderOverlay.vue'

const router = useRouter()
const content = ref('')
const loading = ref(true)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

onMounted(async () => {
  try {
    const res = await fetch(`${API_BASE}/sitecontent/privacy_policy`)
    const data = await res.json()
    content.value = data.content || 'لم يتم إضافة سياسة الخصوصية بعد.'
  } catch {
    content.value = 'حدث خطأ في تحميل سياسة الخصوصية.'
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div class="privacy page">
    <LoaderOverlay :show="loading" text="جاري تحميل سياسة الخصوصية..." />
    <header class="top-bar">
      <button class="back-btn" @click="router.back()"><ChevronRight :size="22" /></button>
      <span class="top-title">سياسة الخصوصية</span>
      <div style="width:40px"></div>
    </header>

    <div class="scroll-area">
      <div v-if="!loading" class="policy-content" v-html="content.replace(/\n/g, '<br>')"></div>
    </div>
  </div>
</template>

<style scoped>
.privacy {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.top-bar {
  align-items: center;
  display: flex;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 12px;
}
.back-btn {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  height: var(--touch-min);
  justify-content: center;
  min-width: var(--touch-min);
}
.back-btn:active { background: var(--bg-card-hover); }
.top-title { font-size: 17px; font-weight: 600; }

.scroll-area {
  flex: 1;
  overflow-y: auto;
  padding: var(--spacing);
  padding-bottom: calc(var(--spacing) + var(--safe-bottom));
}

.loading-text { text-align: center; padding: 24px; }

.policy-content {
  color: var(--text-secondary);
  font-size: 15px;
  line-height: 1.7;
  white-space: pre-wrap;
}
.policy-content :deep(br) { display: block; }
</style>
