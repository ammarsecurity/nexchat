<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, Ban } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'

const router = useRouter()
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

function goBack() {
  router.replace('/settings')
}

onMounted(fetchBlocked)
</script>

<template>
  <div class="blocked page auth-pattern">
    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('blocked.title') }}</span>
      <div class="top-bar-width-spacer" aria-hidden="true"></div>
    </header>

    <div class="scroll-area">
      <div v-if="loading" class="loading-msg">{{ t('common.loading') }}</div>
      <div v-else-if="!list.length" class="empty-state">
        <Ban :size="48" class="empty-icon" />
        <p>{{ t('blocked.empty') }}</p>
      </div>
      <div v-else class="blocked-list">
        <div
          v-for="b in list"
          :key="b.id"
          class="blocked-item glass-card"
        >
          <div class="item-avatar" :style="{ background: b.avatar && !isImageAvatar(b.avatar) ? 'var(--primary)' : 'var(--bg-elevated)' }">
            <img v-if="b.avatar && isImageAvatar(b.avatar)" :src="ensureAbsoluteUrl(b.avatar)" class="avatar-img" referrerpolicy="no-referrer" />
            <span v-else>{{ b.name?.[0]?.toUpperCase() || '?' }}</span>
          </div>
          <div class="item-content">
            <span class="item-name">{{ b.name }}</span>
            <span class="item-meta">{{ b.uniqueCode }}</span>
          </div>
          <button class="unblock-btn" @click="unblock(b)">
            {{ t('blocked.unblock') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.blocked {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  padding-bottom: var(--safe-bottom);
}

.top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 12px;
  flex-shrink: 0;
}

.back-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  background: var(--bg-card);
  border: none;
  border-radius: 12px;
  color: var(--text-primary);
  cursor: pointer;
}

.top-title {
  font-size: 18px;
  font-weight: 600;
}

.scroll-area {
  flex: 1;
  overflow-y: auto;
  padding: var(--spacing);
}

.loading-msg, .empty-state {
  text-align: center;
  padding: 48px 24px;
}

.empty-state .empty-icon {
  opacity: 0.5;
  margin-bottom: 16px;
}

.blocked-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.blocked-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  border-radius: 12px;
}

.item-avatar {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 18px;
  color: white;
  flex-shrink: 0;
}

.avatar-img {
  width: 100%;
  height: 100%;
  border-radius: 50%;
  object-fit: cover;
}

.item-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.item-name { font-weight: 600; }
.item-meta { font-size: 13px; color: var(--text-secondary); }

.unblock-btn {
  padding: 8px 16px;
  font-size: 14px;
  font-family: 'Cairo', sans-serif;
  font-weight: 500;
  color: var(--primary);
  background: rgba(108, 99, 255, 0.15);
  border: 1px solid rgba(108, 99, 255, 0.3);
  border-radius: 10px;
  cursor: pointer;
  flex-shrink: 0;
}

.unblock-btn:active {
  opacity: 0.9;
}
</style>
