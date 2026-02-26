import { createRouter, createWebHashHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const routes = [
  { path: '/', component: () => import('../views/SplashScreen.vue'), meta: { public: true } },
  { path: '/login', component: () => import('../views/auth/LoginView.vue'), meta: { public: true } },
  { path: '/register', component: () => import('../views/auth/RegisterView.vue'), meta: { public: true } },
  { path: '/home', component: () => import('../views/HomeView.vue') },
  { path: '/matching', component: () => import('../views/MatchingView.vue') },
  { path: '/chat/:sessionId', component: () => import('../views/ChatView.vue') },
  { path: '/video/:sessionId', component: () => import('../views/VideoCallView.vue') },
  { path: '/settings', component: () => import('../views/SettingsView.vue') },
  { path: '/privacy', component: () => import('../views/PrivacyPolicyView.vue'), meta: { public: true } },
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

router.beforeEach((to) => {
  const auth = useAuthStore()
  if (!to.meta.public && !auth.token) return '/login'
})

export default router
