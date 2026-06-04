<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import ModernPageShell from '../components/ui/ModernPageShell.vue'
import MessageRequestsPanel from '../components/MessageRequestsPanel.vue'
import { useI18n } from 'vue-i18n'

const route = useRoute()
const { t } = useI18n()

const initialNotice = computed(() => route.query.notice || null)
</script>

<template>
  <ModernPageShell :title="t('messageRequests.title')" back-to="/conversations">
    <MessageRequestsPanel :initial-notice="initialNotice" />
  </ModernPageShell>
</template>
