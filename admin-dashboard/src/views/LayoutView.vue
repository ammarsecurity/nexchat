<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useDisplay } from 'vuetify'

const logoUrl = '/logo-light.png'
const router = useRouter()
const route = useRoute()
const { mobile } = useDisplay()
const drawer = ref(true)
const rail = ref(false)

onMounted(() => {
  if (mobile.value) drawer.value = false
})

watch(route, () => {
  if (mobile.value) drawer.value = false
})

watch(mobile, (isMobile) => {
  if (isMobile) {
    drawer.value = false
    rail.value = false
  } else {
    drawer.value = true
  }
})

const navItems = [
  { title: 'الإحصائيات', icon: 'mdi-view-dashboard', to: '/dashboard' },
  { title: 'المستخدمين', icon: 'mdi-account-group', to: '/users' },
  { title: 'الجلسات', icon: 'mdi-chat', to: '/sessions' },
  { title: 'الرسائل', icon: 'mdi-message-text', to: '/messages' },
  { title: 'المحادثات', icon: 'mdi-forum', to: '/conversations' },
  { title: 'المجموعات', icon: 'mdi-account-group', to: '/group-conversations' },
  { title: 'المحظورون', icon: 'mdi-block-helper', to: '/blocks' },
  { title: 'جهات الاتصال', icon: 'mdi-account-multiple', to: '/contacts' },
  { title: 'دردشة الدعم', icon: 'mdi-headset', to: '/support' },
  { title: 'البلاغات', icon: 'mdi-flag', to: '/reports' },
  { title: 'الإعلانات', icon: 'mdi-image-multiple', to: '/ads' },
  { title: 'الستوريات', icon: 'mdi-circle-multiple', to: '/stories' },
  { title: 'الأفلام القصيرة', icon: 'mdi-movie-roll', to: '/short-films' },
  { title: 'الإشعارات العامة', icon: 'mdi-bell-ring', to: '/notifications' },
  { title: 'تحديث التطبيق', icon: 'mdi-cellphone-arrow-down', to: '/app-update' },
  { title: 'ميزات التطبيق', icon: 'mdi-toggle-switch', to: '/features' },
  { title: 'سياسة الخصوصية', icon: 'mdi-shield-account', to: '/privacy' },
  { title: 'شروط الاستخدام', icon: 'mdi-file-document-outline', to: '/terms' },
  { title: 'التواصل الاجتماعي', icon: 'mdi-share-variant', to: '/social' },
  { title: 'الصفحات الاسترشادية', icon: 'mdi-book-open-page-variant', to: '/onboarding' },
  { title: 'الإعدادات', icon: 'mdi-cog', to: '/settings' },
]

const currentTitle = computed(() => {
  return navItems.find(n => route.path.startsWith(n.to))?.title || 'لوحة التحكم'
})

function logout() {
  localStorage.removeItem('nexchat_admin_token')
  router.replace('/login')
}
</script>

<template>
  <div class="layout-root">
    <v-navigation-drawer
      v-model="drawer"
      :rail="rail && !mobile"
      :permanent="!mobile"
      :temporary="mobile"
      class="side-drawer"
      width="280"
    >
      <div class="drawer-brand" :class="{ 'drawer-brand-rail': rail && !mobile }">
        <img :src="logoUrl" alt="نيكس شات" class="logo-img" :class="{ 'logo-img-sm': rail && !mobile }" />
        <div v-if="!(rail && !mobile)" class="brand-text">
          <div class="brand-name">نيكس شات</div>
          <div class="brand-sub">لوحة التحكم</div>
        </div>
        <v-btn
          v-if="!rail && !mobile"
          icon="mdi-chevron-left"
          variant="text"
          density="comfortable"
          class="rail-toggle"
          @click="rail = true"
        />
      </div>

      <v-divider class="mx-4 my-1" />

      <v-list density="compact" nav class="nav-list px-2 mt-2">
        <v-list-item
          v-for="item in navItems"
          :key="item.to"
          :prepend-icon="item.icon"
          :title="!(rail && !mobile) ? item.title : ''"
          :to="item.to"
          rounded="lg"
          active-class="nav-active"
          class="mb-1 nav-item"
        />
      </v-list>

      <template #append>
        <v-divider class="mx-4 mb-2" />
        <v-list density="compact" nav class="px-2">
          <v-list-item
            prepend-icon="mdi-logout"
            :title="!(rail && !mobile) ? 'تسجيل الخروج' : ''"
            rounded="lg"
            class="mb-2 logout-item"
            @click="logout"
          />
        </v-list>
        <v-btn
          v-if="rail && !mobile"
          icon="mdi-chevron-right"
          variant="text"
          density="comfortable"
          block
          class="mb-3"
          @click="rail = false"
        />
      </template>
    </v-navigation-drawer>

    <v-main class="main-area">
      <v-app-bar elevation="0" class="top-bar" height="64">
        <v-app-bar-nav-icon
          v-if="mobile"
          @click="drawer = !drawer"
          aria-label="القائمة"
        />
        <v-app-bar-title class="bar-title" :class="{ 'text-h6': mobile }">
          {{ currentTitle }}
        </v-app-bar-title>
        <template #append>
          <div class="toolbar-append">
            <v-chip
              color="success"
              size="small"
              variant="tonal"
              density="comfortable"
              class="status-chip"
            >
              <v-icon start size="x-small" icon="mdi-circle" class="status-dot" />
              نشط
            </v-chip>
          </div>
        </template>
      </v-app-bar>

      <v-container fluid class="main-container pa-4 pa-sm-6">
        <RouterView />
      </v-container>
    </v-main>
  </div>
</template>

<style scoped>
.layout-root {
  min-height: 100vh;
  background: var(--bg);
}

.side-drawer {
  border-inline-end: 1px solid var(--border) !important;
  box-shadow: none !important;
}

.drawer-brand {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 20px 16px 16px;
}

.drawer-brand-rail {
  justify-content: center;
  padding-inline: 8px;
}

.logo-img {
  height: 40px;
  width: auto;
  object-fit: contain;
  flex-shrink: 0;
}

.logo-img-sm {
  height: 32px;
}

.brand-text {
  flex: 1;
  min-width: 0;
}

.brand-name {
  font-weight: 800;
  font-size: 1.05rem;
  color: var(--text);
  line-height: 1.2;
}

.brand-sub {
  font-size: 0.75rem;
  color: var(--text-muted);
  font-weight: 600;
}

.rail-toggle {
  flex-shrink: 0;
}

.nav-list {
  padding-bottom: 8px;
}

.nav-item {
  color: var(--text-secondary);
  font-weight: 600;
}

.nav-active {
  background: rgba(46, 134, 251, 0.12) !important;
  color: var(--blue) !important;
  font-weight: 700 !important;
}

:deep(.nav-active .v-icon) {
  color: var(--blue) !important;
}

:deep(.nav-item .v-icon) {
  opacity: 0.85;
}

.logout-item {
  color: #EF4444 !important;
}

.main-area {
  background: var(--bg);
  min-height: 100vh;
}

.top-bar {
  border-bottom: 1px solid var(--border) !important;
}

.bar-title {
  font-weight: 800 !important;
  letter-spacing: -0.02em;
}

.toolbar-append {
  display: flex;
  align-items: center;
  min-height: 48px;
  padding-inline-start: 12px;
}

.status-chip {
  flex-shrink: 0;
}

.status-chip .status-dot {
  opacity: 0.9;
}

@media (max-width: 600px) {
  .main-container {
    padding-left: 16px !important;
    padding-right: 16px !important;
  }
}

.side-drawer :deep(.v-list-item) {
  min-height: 44px;
}
</style>
