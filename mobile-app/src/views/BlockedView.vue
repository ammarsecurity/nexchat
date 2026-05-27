<script setup>
import { ref, onMounted } from 'vue'
import { Ban } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import ModernPageShell from '../components/ui/ModernPageShell.vue'

const { t } = useI18n()

const loading = ref(false)
const list = ref([])

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

async function fetchBlocked() {
  loading.value = true
  try {
    const { data } = await api.get('/blocks')
    list.value = data ?? []
  } catch {
    list.value = []
  } finally {
    loading.value = false
  }
}

async function unblock(user) {
  try {
    await api.delete(`/blocks/${user.blockedUserId}`)
    list.value = list.value.filter(b => b.blockedUserId !== user.blockedUserId)
  } catch {}
}

onMounted(fetchBlocked)
</script>

<template>
  <ModernPageShell :title="t('blocked.title')" back-to="/settings">
    <div v-if="loading" class="modern-empty">{{ t('common.loading') }}</div>
    <div v-else-if="!list.length" class="modern-empty">
      <Ban :size="48" />
      <p>{{ t('blocked.empty') }}</p>
    </div>
    <div v-else class="modern-list">
      <div v-for="b in list" :key="b.id" class="modern-list-row">
        <div class="modern-list-row__avatar">
          <img v-if="b.avatar && isImageAvatar(b.avatar)" :src="ensureAbsoluteUrl(b.avatar)" alt="" />
          <span v-else>{{ b.name?.[0]?.toUpperCase() || '?' }}</span>
        </div>
        <div class="modern-list-row__body">
          <span class="modern-list-row__title">{{ b.name }}</span>
          <span class="modern-list-row__sub">{{ b.uniqueCode }}</span>
        </div>
        <button type="button" class="unblock-btn" @click="unblock(b)">
          {{ t('blocked.unblock') }}
        </button>
      </div>
    </div>
  </ModernPageShell>
</template>

<style scoped>
.unblock-btn {
  flex-shrink: 0;
  padding: 8px 14px;
  border: none;
  border-radius: var(--radius-full);
  background: var(--primary-soft);
  color: var(--primary);
  font-family: 'Cairo', sans-serif;
  font-size: 13px;
  font-weight: 700;
  cursor: pointer;
}
</style>
