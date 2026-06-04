<script setup>
import { onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { normalizeInviteCode } from '../utils/shareLinks'
import { useI18n } from 'vue-i18n'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const { t } = useI18n()

onMounted(() => {
  const code = normalizeInviteCode(route.params.code)
  if (!code) {
    router.replace('/home')
    return
  }

  if (auth.token) {
    router.replace({ path: '/home', query: { invite: code } })
    return
  }

  sessionStorage.setItem('nexchat_pending_invite', code)
  router.replace({ path: '/login', query: { invite: code } })
})
</script>

<template>
  <div class="invite-join page">
    <p class="text-muted">{{ t('share.openingInvite') }}</p>
  </div>
</template>

<style scoped>
.invite-join {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  background: var(--bg-primary);
}
</style>
