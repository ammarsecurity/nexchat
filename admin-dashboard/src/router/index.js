import { createRouter, createWebHashHistory } from 'vue-router'

const routes = [
  {
    path: '/login',
    component: () => import('../views/LoginView.vue'),
    meta: { public: true }
  },
  {
    path: '/',
    component: () => import('../views/LayoutView.vue'),
    redirect: '/dashboard',
    children: [
      { path: 'dashboard', component: () => import('../views/DashboardView.vue') },
      { path: 'users', component: () => import('../views/UsersView.vue') },
      { path: 'sessions', component: () => import('../views/SessionsView.vue') },
      { path: 'messages', component: () => import('../views/MessagesView.vue') },
      { path: 'support', component: () => import('../views/SupportView.vue') },
      { path: 'reports', component: () => import('../views/ReportsView.vue') },
      { path: 'ads', component: () => import('../views/AdsView.vue') },
      { path: 'privacy', component: () => import('../views/PrivacyPolicyView.vue') },
      { path: 'social', component: () => import('../views/SocialLinksView.vue') },
      { path: 'onboarding', component: () => import('../views/OnboardingView.vue') },
      { path: 'settings', component: () => import('../views/SettingsView.vue') },
    ]
  }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

router.beforeEach((to) => {
  const token = localStorage.getItem('nexchat_admin_token')
  if (!to.meta.public && !token) return '/login'
})

export default router
