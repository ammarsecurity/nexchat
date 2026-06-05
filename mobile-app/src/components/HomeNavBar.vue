<script setup>
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { useConversationsListStore } from '../stores/conversationsList'
import { useMessageRequestsStore } from '../stores/messageRequests'
import { publicUrl } from '../utils/publicUrl'

const listStore = useConversationsListStore()
const msgReqStore = useMessageRequestsStore()
const auth = useAuthStore()
const totalUnread = computed(() => {
  return listStore.list.reduce((sum, c) => {
    const n = c?.unreadCount ?? c?.UnreadCount ?? 0
    return sum + (typeof n === 'number' ? n : parseInt(n, 10) || 0)
  }, 0)
})

onMounted(() => {
  if (auth.token) msgReqStore.fetchPendingCount()
})

const props = defineProps({
  loading: { type: Boolean, default: false },
  randomChatEnabled: { type: Boolean, default: true },
  shortFilmsEnabled: { type: Boolean, default: false }
})

const emit = defineEmits(['launch'])

const { t } = useI18n()
const isLaunching = ref(false)

async function onRocketClick() {
  if (!props.randomChatEnabled || props.loading || isLaunching.value) return
  isLaunching.value = true
  emit('launch')
  // انتظار انتهاء الحركة قبل إعادة التفعيل
  setTimeout(() => { isLaunching.value = false }, 800)
}

</script>

<template>
  <nav class="home-nav">
    <RouterLink to="/conversations" class="nav-item" :aria-label="t('conversations.title')">
      <span class="nav-icon-wrap">
        <Vue3Lottie
          :animation-link="publicUrl('json/conv.json')"
          :height="48"
          :width="48"
          :speed="1"
          :loop="true"
          :auto-play="true"
          class="nav-lottie"
        />
        <span v-if="totalUnread > 0" class="nav-badge">{{ totalUnread > 99 ? '99+' : totalUnread }}</span>
        <span v-if="msgReqStore.pendingCount > 0" class="nav-badge nav-badge-msg-req">{{ msgReqStore.pendingCount > 99 ? '99+' : msgReqStore.pendingCount }}</span>
      </span>
      <span class="nav-label">{{ t('conversations.title') }}</span>
    </RouterLink>

    <button
      v-if="randomChatEnabled"
      type="button"
      class="nav-item nav-item--rocket"
      :class="{ launching: isLaunching || loading }"
      :disabled="loading"
      :aria-label="t('home.startRandom')"
      @click="onRocketClick"
    >
      <span class="nav-icon-wrap">
        <Vue3Lottie
            :animation-link="publicUrl('json/Rocket%20Lunch.json')"
            :height="48"
            :width="48"
            :speed="0.9"
            :loop="true"
            :auto-play="true"
          class="nav-lottie"
        />
      </span>
      <span class="nav-label">{{ t('home.randomNav') }}</span>
    </button>

    <RouterLink
      v-if="shortFilmsEnabled"
      to="/short-films"
      class="nav-item"
      :aria-label="t('shortFilms.title')"
    >
      <span class="nav-icon-wrap nav-icon-wrap--short-films">
        <Vue3Lottie
          :animation-link="publicUrl('json/shortFilm.json')"
          :height="44"
          :width="44"
          :speed="1"
          :loop="true"
          :auto-play="true"
          class="nav-lottie"
        />
      </span>
      <span class="nav-label">{{ t('shortFilms.nav') }}</span>
    </RouterLink>

  </nav>
</template>

<style scoped>
.home-nav {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  display: flex;
  align-items: flex-end;
  justify-content: space-around;
  padding: 8px var(--spacing) calc(8px + var(--safe-bottom));
  background: var(--bg-card);
  border-top: 1px solid var(--border);
  z-index: 100;
}

/* يتماشى مع عرض #app على التابلت والشاشات الأوسع */
@media (min-width: 480px) {
  .home-nav {
    left: 50%;
    right: auto;
    width: var(--app-max-width);
    max-width: 100%;
    transform: translateX(-50%);
    box-sizing: border-box;
  }
}

.nav-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  flex: 1;
  min-width: 0;
  max-width: 88px;
  padding: 8px 6px;
  color: var(--text-muted);
  text-decoration: none;
  border-radius: var(--radius-sm);
  transition: color 0.2s, background 0.2s;
  -webkit-tap-highlight-color: transparent;
}
.nav-item.router-link-active,
.nav-item:active {
  color: var(--primary);
}
.nav-icon-wrap {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 48px;
  height: 48px;
}

.nav-lottie {
  display: block;
  pointer-events: none;
}

.nav-icon-wrap--short-films {
  width: 44px;
  height: 44px;
}
.nav-badge {
  position: absolute;
  top: -6px;
  right: -8px;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  font-size: 11px;
  font-weight: 700;
  line-height: 18px;
  text-align: center;
  color: white;
  background: var(--danger);
  border-radius: 9px;
  font-family: 'Cairo', sans-serif;
}
.nav-badge-msg-req {
  top: auto;
  bottom: -4px;
  right: auto;
  left: -6px;
  background: #f97316;
}
.nav-label {
  font-size: 10px;
  font-family: 'Cairo', sans-serif;
  font-weight: 500;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  text-align: center;
}

.nav-item--rocket {
  border: none;
  background: none;
  font: inherit;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.nav-item--rocket:active:not(:disabled),
.nav-item--rocket.launching:not(:disabled) {
  color: var(--primary);
}

.nav-item--rocket:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.nav-item--rocket.launching .nav-lottie :deep(.lottie-animation-container),
.nav-item--rocket.launching .nav-lottie :deep(svg) {
  transform: translateY(-20px) scale(0.92);
  opacity: 0.35;
  transition: transform 0.55s cubic-bezier(0.34, 1.56, 0.64, 1), opacity 0.45s ease-out;
}
</style>
