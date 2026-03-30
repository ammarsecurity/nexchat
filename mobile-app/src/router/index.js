import { createRouter, createWebHashHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import api from '../services/api'
import { getCodeConnectFeaturesEnabled } from '../services/siteContentFlags'

const routes = [
  { path: '/', component: () => import('../views/SplashScreen.vue'), meta: { public: true } },
  { path: '/onboarding', component: () => import('../views/OnboardingView.vue'), meta: { public: true } },
  { path: '/login', component: () => import('../views/auth/LoginView.vue'), meta: { public: true } },
  { path: '/register', component: () => import('../views/auth/RegisterView.vue'), meta: { public: true } },
  { path: '/complete-profile', component: () => import('../views/auth/CompleteProfileView.vue') },
  { path: '/home', component: () => import('../views/HomeView.vue') },
  { path: '/saved-codes', component: () => import('../views/SavedCodesView.vue'), meta: { requiresCodeConnectFeatures: true } },
  { path: '/connection-history', component: () => import('../views/ConnectionHistoryView.vue'), meta: { requiresCodeConnectFeatures: true } },
  { path: '/blocked', component: () => import('../views/BlockedView.vue') },
  { path: '/matching', component: () => import('../views/MatchingView.vue') },
  { path: '/chat/:sessionId', component: () => import('../views/ChatView.vue') },
  { path: '/video/:sessionId', component: () => import('../views/VideoCallView.vue') },
  { path: '/conversations', component: () => import('../views/ConversationsView.vue') },
  { path: '/message-requests', component: () => import('../views/MessageRequestsView.vue') },
  { path: '/conversations/create-group', component: () => import('../views/CreateGroupView.vue') },
  { path: '/conversation/:conversationId/group-info', component: () => import('../views/GroupInfoView.vue') },
  { path: '/conversations/:conversationId/options', component: () => import('../views/ConversationOptionsView.vue') },
  { path: '/profile/:userId', component: () => import('../views/UserProfileView.vue') },
  { path: '/contacts', component: () => import('../views/ContactsView.vue') },
  { path: '/conversation/:conversationId', component: () => import('../views/ConversationChatView.vue') },
  { path: '/share-message', component: () => import('../views/ShareMessageView.vue') },
  { path: '/settings', component: () => import('../views/SettingsView.vue') },
  { path: '/notifications', component: () => import('../views/NotificationsView.vue') },
  { path: '/privacy', component: () => import('../views/PrivacyPolicyView.vue'), meta: { public: true } },
  { path: '/terms', component: () => import('../views/TermsOfServiceView.vue'), meta: { public: true } },
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (!to.meta.public && !auth.token) return '/login'
  if (auth.token && auth.needsProfileContactRedirect && to.path !== '/complete-profile')
    return '/complete-profile'
  if (to.meta.requiresCodeConnectFeatures && auth.token) {
    const ok = await getCodeConnectFeaturesEnabled(api)
    if (!ok) return '/home'
  }
})

export default router
