<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import ModernPageShell from '../components/ui/ModernPageShell.vue'

const { t } = useI18n()
const content = ref('')
const loading = ref(true)

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

onMounted(async () => {
  try {
    const res = await fetch(`${API_BASE}/sitecontent/terms_of_service`)
    const data = await res.json()
    content.value = data.content || t('terms.empty')
  } catch {
    content.value = t('terms.loadError')
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <ModernPageShell :title="t('terms.title')" back-to="/settings">
    <LoaderOverlay :show="loading" :text="t('terms.loading')" />
    <div v-if="!loading" class="policy-content" v-html="content.replace(/\n/g, '<br>')" />
  </ModernPageShell>
</template>

<style scoped>
.policy-content {
  color: var(--text-secondary);
  font-size: 14px;
  line-height: 1.7;
}
</style>
