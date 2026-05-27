<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { MessageCircle, Clapperboard, Rocket, User } from 'lucide-vue-next'
import { useConversationsListStore } from '../stores/conversationsList'
import { useMessageRequestsStore } from '../stores/messageRequests'
import { getShortFilmsEnabled } from '../services/siteContentFlags'
import api from '../services/api'
import { useReducedMotion } from '../composables/useReducedMotion'
import { hapticLight } from '../composables/useHaptics'
import { publicUrl } from '../utils/publicUrl'

const route = useRoute()
const { t } = useI18n()
const listStore = useConversationsListStore()
const msgReqStore = useMessageRequestsStore()
const { reducedMotion } = useReducedMotion()

const shortFilmsEnabled = ref(false)

const totalUnread = computed(() =>
  listStore.list.reduce((sum, c) => {
    const n = c?.unreadCount ?? c?.UnreadCount ?? 0
    return sum + (typeof n === 'number' ? n : parseInt(n, 10) || 0)
  }, 0)
)

const showTabBar = computed(() => {
  const paths = ['/home', '/conversations', '/contacts', '/settings']
  if (shortFilmsEnabled.value) paths.push('/short-films')
  return paths.includes(route.path)
})

const tabs = computed(() => {
  const items = [
    { to: '/conversations', label: t('nav.conversations'), icon: 'chat', badge: totalUnread.value },
    ...(shortFilmsEnabled.value
      ? [{ to: '/short-films', label: t('nav.discover'), icon: 'films', badge: 0 }]
      : []),
    { to: '/home', label: t('nav.connect'), icon: 'home', badge: 0 },
    { to: '/settings', label: t('nav.profile'), icon: 'profile', badge: msgReqStore.pendingCount }
  ]
  return items
})

function isActive(path) {
  return route.path === path
}

function onTabClick() {
  hapticLight()
}

onMounted(async () => {
  msgReqStore.fetchPendingCount()
  shortFilmsEnabled.value = await getShortFilmsEnabled(api)
})

defineExpose({ showTabBar })
</script>

<template>
  <nav v-if="showTabBar" class="app-tab-bar" :aria-label="t('nav.main')">
    <RouterLink
      v-for="tab in tabs"
      :key="tab.to"
      :to="tab.to"
      class="app-tab-bar__item"
      :class="{ 'app-tab-bar__item--active': isActive(tab.to) }"
      :aria-label="tab.label"
      :aria-current="isActive(tab.to) ? 'page' : undefined"
      @click="onTabClick"
    >
      <span class="app-tab-bar__icon-wrap">
        <Vue3Lottie
          v-if="tab.icon === 'home' && !reducedMotion"
          :animation-link="publicUrl('json/Rocket%20Lunch.json')"
          :height="40"
          :width="40"
          :speed="0.9"
          :loop="true"
          :auto-play="true"
          class="app-tab-bar__lottie"
        />
        <MessageCircle v-else-if="tab.icon === 'chat'" :size="24" stroke-width="2" />
        <Clapperboard v-else-if="tab.icon === 'films'" :size="24" stroke-width="2" />
        <Rocket v-else-if="tab.icon === 'home'" :size="24" stroke-width="2" />
        <User v-else :size="24" stroke-width="2" />
        <span
          v-if="tab.badge > 0 && tab.icon === 'chat'"
          class="app-tab-bar__badge"
        >{{ tab.badge > 99 ? '99+' : tab.badge }}</span>
      </span>
      <span class="app-tab-bar__label">{{ tab.label }}</span>
    </RouterLink>
  </nav>
</template>

<style scoped>
.app-tab-bar {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  z-index: 100;
  display: flex;
  align-items: flex-end;
  justify-content: space-around;
  padding: 10px var(--spacing) calc(10px + var(--safe-bottom));
  background: var(--bg-card);
  border-top: none;
  border-radius: var(--radius-xl) var(--radius-xl) 0 0;
  box-shadow: var(--shadow-tab);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
}

@media (min-width: 480px) {
  .app-tab-bar {
    left: 50%;
    right: auto;
    width: min(var(--app-max-width), 100%);
    transform: translateX(-50%);
  }
}

.app-tab-bar__item {
  flex: 1;
  max-width: 72px;
  min-width: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 6px 4px;
  color: var(--text-muted);
  text-decoration: none;
  border-radius: var(--radius-full);
  -webkit-tap-highlight-color: transparent;
  transition: color var(--motion-fast) var(--ease-out), background var(--motion-fast);
}

.app-tab-bar__item--active,
.app-tab-bar__item.router-link-active {
  color: var(--primary);
}

.app-tab-bar__item--active .app-tab-bar__icon-wrap,
.app-tab-bar__item.router-link-active .app-tab-bar__icon-wrap {
  background: var(--primary-soft);
}

.app-tab-bar__item:active {
  opacity: 0.85;
}

.app-tab-bar__icon-wrap {
  position: relative;
  width: 44px;
  height: 44px;
  border-radius: var(--radius-full);
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background var(--motion-fast);
}

.app-tab-bar__lottie {
  pointer-events: none;
}

.app-tab-bar__badge {
  position: absolute;
  top: 2px;
  inset-inline-end: 2px;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  font-size: 10px;
  font-weight: 700;
  line-height: 18px;
  text-align: center;
  color: #fff;
  background: var(--primary);
  border-radius: var(--radius-full);
  box-shadow: 0 2px 6px rgba(59, 130, 246, 0.35);
}

.app-tab-bar__label {
  font-size: 10px;
  font-weight: 600;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
