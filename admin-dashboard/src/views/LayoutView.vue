<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useDisplay } from 'vuetify'

const router = useRouter()
const route = useRoute()
const { mobile } = useDisplay()
const drawer = ref(true)
const rail = ref(false)

onMounted(() => {
  if (mobile.value) drawer.value = false
})

// على الجوال: إغلاق الدرج عند تغيير الصفحة
watch(route, () => {
  if (mobile.value) drawer.value = false
})

// عند الانتقال من سطح المكتب للجوال: إغلاق الدرج
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
  { title: 'البلاغات', icon: 'mdi-flag', to: '/reports' },
  { title: 'الإعلانات', icon: 'mdi-image-multiple', to: '/ads' },
  { title: 'سياسة الخصوصية', icon: 'mdi-shield-account', to: '/privacy' },
  { title: 'التواصل الاجتماعي', icon: 'mdi-share-variant', to: '/social' },
  { title: 'الصفحات الاسترشادية', icon: 'mdi-book-open-page-variant', to: '/onboarding' },
]

const currentTitle = computed(() => {
  return navItems.find(n => route.path.startsWith(n.to))?.title || 'NexChat Admin'
})

function logout() {
  localStorage.removeItem('nexchat_admin_token')
  router.replace('/login')
}
</script>

<template>
  <div>
    <!-- Navigation Drawer -->
    <v-navigation-drawer
      v-model="drawer"
      :rail="rail && !mobile"
      :permanent="!mobile"
      :temporary="mobile"
      color="#0D0D1A"
      border="end"
      style="border-color: rgba(255,255,255,0.06) !important"
      class="mobile-drawer"
    >
      <!-- Logo -->
      <v-list-item
        class="py-5"
        :prepend-icon="rail ? undefined : undefined"
      >
        <template #prepend>
          <div class="logo-chip" :class="{ 'logo-chip-sm': rail }">N</div>
        </template>
        <v-list-item-title v-if="!rail" class="gradient-text text-h6 font-weight-black">
          NexChat
        </v-list-item-title>
        <v-list-item-subtitle v-if="!rail" class="text-caption">
          Admin Panel
        </v-list-item-subtitle>

        <template #append>
          <v-btn
            v-if="!rail && !mobile"
            :icon="rail ? 'mdi-chevron-right' : 'mdi-chevron-left'"
            variant="text"
            density="compact"
            @click="rail = !rail"
          ></v-btn>
        </template>
      </v-list-item>

      <v-divider style="border-color: rgba(255,255,255,0.06)"></v-divider>

      <v-list density="compact" nav class="mt-2">
        <v-list-item
          v-for="item in navItems"
          :key="item.to"
          :prepend-icon="item.icon"
          :title="!rail ? item.title : ''"
          :to="item.to"
          rounded="xl"
          active-class="nav-active"
          class="mb-1"
        ></v-list-item>
      </v-list>

      <template #append>
        <v-divider style="border-color: rgba(255,255,255,0.06)" class="mb-2"></v-divider>
        <v-list density="compact" nav>
          <v-list-item
            prepend-icon="mdi-logout"
            :title="!rail ? 'تسجيل الخروج' : ''"
            rounded="xl"
            class="mb-2"
            @click="logout"
            color="error"
          ></v-list-item>
        </v-list>
        <v-btn
          v-if="rail && !mobile"
          icon="mdi-chevron-right"
          variant="text"
          density="compact"
          block
          class="mb-2"
          @click="rail = false"
        ></v-btn>
      </template>
    </v-navigation-drawer>

    <!-- Main Content -->
    <v-main style="background: #0D0D1A; min-height: 100vh;">
      <!-- Top App Bar -->
      <v-app-bar
        color="#0D0D1A"
        elevation="0"
        border="b"
        style="border-color: rgba(255,255,255,0.06) !important"
      >
        <v-app-bar-nav-icon
          v-if="mobile"
          @click="drawer = !drawer"
          aria-label="القائمة"
        />
        <v-app-bar-title class="font-weight-bold" :class="{ 'text-h6': mobile }">{{ currentTitle }}</v-app-bar-title>
        <template #append>
          <v-chip
            v-if="!mobile"
            prepend-icon="mdi-circle"
            color="success"
            size="small"
            variant="tonal"
            class="mr-4"
          >
            <span class="online-dot mr-1"></span>
            نشط
          </v-chip>
          <v-chip
            v-else
            prepend-icon="mdi-circle"
            color="success"
            size="x-small"
            variant="tonal"
            density="compact"
          >
            <span class="online-dot mr-1"></span>
            نشط
          </v-chip>
        </template>
      </v-app-bar>

      <v-container fluid class="main-container pa-4 pa-sm-6">
        <RouterView />
      </v-container>
    </v-main>
  </div>
</template>

<style scoped>
.logo-chip {
  align-items: center;
  background: linear-gradient(135deg, #6C63FF, #FF6584);
  border-radius: 10px;
  color: white;
  display: flex;
  font-size: 18px;
  font-weight: 900;
  height: 36px;
  justify-content: center;
  width: 36px;
  flex-shrink: 0;
}
.logo-chip-sm {
  font-size: 14px;
  height: 30px;
  width: 30px;
  border-radius: 8px;
}

.nav-active {
  background: rgba(108, 99, 255, 0.15) !important;
  color: #6C63FF !important;
}

:deep(.v-list-item--active .v-icon) { color: #6C63FF !important; }

/* تحسينات الجوال */
@media (max-width: 600px) {
  .main-container {
    padding-left: 16px !important;
    padding-right: 16px !important;
  }
}

.mobile-drawer :deep(.v-list-item) {
  min-height: 48px;
}
</style>
