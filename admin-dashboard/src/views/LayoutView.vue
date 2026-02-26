<script setup>
import { ref, computed } from 'vue'
import { useRouter, useRoute } from 'vue-router'

const router = useRouter()
const route = useRoute()
const drawer = ref(true)
const rail = ref(false)

const navItems = [
  { title: 'الإحصائيات', icon: 'mdi-view-dashboard', to: '/dashboard' },
  { title: 'المستخدمين', icon: 'mdi-account-group', to: '/users' },
  { title: 'الجلسات', icon: 'mdi-chat', to: '/sessions' },
  { title: 'الرسائل', icon: 'mdi-message-text', to: '/messages' },
  { title: 'البلاغات', icon: 'mdi-flag', to: '/reports' },
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
      :rail="rail"
      permanent
      color="#0D0D1A"
      border="end"
      style="border-color: rgba(255,255,255,0.06) !important"
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
            v-if="!rail"
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
          v-if="rail"
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
        <v-app-bar-title class="font-weight-bold">{{ currentTitle }}</v-app-bar-title>
        <template #append>
          <v-chip
            prepend-icon="mdi-circle"
            color="success"
            size="small"
            variant="tonal"
            class="mr-4"
          >
            <span class="online-dot mr-1"></span>
            نشط
          </v-chip>
        </template>
      </v-app-bar>

      <v-container fluid class="pa-6">
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
</style>
