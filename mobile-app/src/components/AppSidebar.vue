<script setup>
import { useI18n } from 'vue-i18n'
import { MessageCircle, Clapperboard, Rocket, User } from 'lucide-vue-next'
import { useAppNav } from '../composables/useAppNav'
import { useReducedMotion } from '../composables/useReducedMotion'
import { hapticLight } from '../composables/useHaptics'
import { publicUrl } from '../utils/publicUrl'
import { useThemeStore } from '../stores/theme'
import { computed } from 'vue'

const { t } = useI18n()
const theme = useThemeStore()
const { tabs, isNavActive } = useAppNav()
const { reducedMotion } = useReducedMotion()

const logoImg = computed(() => publicUrl(theme.isLight ? 'logo-light.png' : 'logo.png'))

function onNavClick() {
  hapticLight()
}
</script>

<template>
  <aside class="app-sidebar" :aria-label="t('nav.main')">
    <div class="app-sidebar__brand">
      <img :src="logoImg" alt="NexChat" class="app-sidebar__logo" />
      <span class="app-sidebar__name">NexChat</span>
    </div>
    <nav class="app-sidebar__nav">
      <RouterLink
        v-for="tab in tabs"
        :key="tab.to"
        :to="tab.to"
        class="app-sidebar__item"
        :class="{ 'app-sidebar__item--active': isNavActive(tab.to) }"
        :aria-label="tab.label"
        :aria-current="isNavActive(tab.to) ? 'page' : undefined"
        @click="onNavClick"
      >
        <span class="app-sidebar__icon-wrap">
          <Vue3Lottie
            v-if="tab.icon === 'home' && !reducedMotion"
            :animation-link="publicUrl('json/Rocket%20Lunch.json')"
            :height="28"
            :width="28"
            :speed="0.9"
            :loop="true"
            :auto-play="true"
            class="app-sidebar__lottie"
          />
          <MessageCircle v-else-if="tab.icon === 'chat'" :size="22" stroke-width="2" />
          <Clapperboard v-else-if="tab.icon === 'films'" :size="22" stroke-width="2" />
          <Rocket v-else-if="tab.icon === 'home'" :size="22" stroke-width="2" />
          <User v-else :size="22" stroke-width="2" />
          <span
            v-if="tab.badge > 0"
            class="app-sidebar__badge"
          >{{ tab.badge > 99 ? '99+' : tab.badge }}</span>
        </span>
        <span class="app-sidebar__label">{{ tab.label }}</span>
      </RouterLink>
    </nav>
  </aside>
</template>

<style scoped>
.app-sidebar {
  flex-shrink: 0;
  width: var(--sidebar-width, 240px);
  height: 100%;
  min-height: 100vh;
  min-height: 100dvh;
  display: flex;
  flex-direction: column;
  padding: calc(var(--safe-top) + 16px) 12px 16px;
  background: var(--bg-card);
  border-inline-end: 1px solid var(--border);
  z-index: 110;
}

.app-sidebar__brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 8px 20px;
  margin-bottom: 8px;
  border-bottom: 1px solid var(--border);
}

.app-sidebar__logo {
  width: 36px;
  height: 36px;
  object-fit: contain;
}

.app-sidebar__name {
  font-size: 18px;
  font-weight: 800;
  color: var(--text-primary);
}

.app-sidebar__nav {
  display: flex;
  flex-direction: column;
  gap: 4px;
  flex: 1;
}

.app-sidebar__item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 12px;
  border-radius: var(--radius-lg);
  color: var(--text-muted);
  text-decoration: none;
  font-size: 14px;
  font-weight: 600;
  transition: background var(--motion-fast), color var(--motion-fast);
}

.app-sidebar__item--active,
.app-sidebar__item.router-link-active {
  background: var(--primary-soft);
  color: var(--primary);
}

.app-sidebar__icon-wrap {
  position: relative;
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.app-sidebar__badge {
  position: absolute;
  top: 0;
  inset-inline-end: 0;
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
}

.app-sidebar__label {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.app-sidebar__lottie {
  pointer-events: none;
}
</style>
