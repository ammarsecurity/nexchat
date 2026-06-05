import { ref, computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useAuthStore } from '../stores/auth'
import { useConversationsListStore } from '../stores/conversationsList'
import { useMessageRequestsStore } from '../stores/messageRequests'
import { getShortFilmsEnabled } from '../services/siteContentFlags'
import api from '../services/api'

export function useAppNav() {
  const route = useRoute()
  const { t } = useI18n()
  const listStore = useConversationsListStore()
  const msgReqStore = useMessageRequestsStore()
  const shortFilmsEnabled = ref(false)

  const totalUnread = computed(() =>
    listStore.list.reduce((sum, c) => {
      const n = c?.unreadCount ?? c?.UnreadCount ?? 0
      return sum + (typeof n === 'number' ? n : parseInt(n, 10) || 0)
    }, 0)
  )

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

  const tabBarPaths = computed(() => {
    const paths = ['/home', '/conversations', '/contacts', '/settings']
    if (shortFilmsEnabled.value) paths.push('/short-films')
    return paths
  })

  const showTabBar = computed(() => tabBarPaths.value.includes(route.path))

  function isNavActive(path) {
    if (path === '/conversations') {
      return (
        route.path === '/conversations' ||
        route.path.startsWith('/conversation/') ||
        route.path.startsWith('/conversations/')
      )
    }
    return route.path === path
  }

  onMounted(async () => {
    const auth = useAuthStore()
    if (auth.token) msgReqStore.fetchPendingCount()
    shortFilmsEnabled.value = await getShortFilmsEnabled(api)
  })

  return {
    tabs,
    showTabBar,
    isNavActive,
    shortFilmsEnabled
  }
}
