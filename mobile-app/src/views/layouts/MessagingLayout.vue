<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useLayoutMode } from '../../composables/useLayoutMode'
import ConversationsView from '../ConversationsView.vue'
import ConversationChatView from '../ConversationChatView.vue'

const route = useRoute()
const { t } = useI18n()
const { isDesktop } = useLayoutMode()

const conversationId = computed(() => route.params.conversationId)

const isChatRoute = computed(
  () => !!conversationId.value && route.path.startsWith('/conversation/')
)

const showList = computed(() => isDesktop.value || !isChatRoute.value)

const showChatPane = computed(() => isDesktop.value || isChatRoute.value)
</script>

<template>
  <div
    class="messaging-layout page"
    :class="{ 'messaging-layout--desktop': isDesktop }"
  >
    <aside v-if="showList" class="messaging-layout__list">
      <ConversationsView :pane-mode="isDesktop" />
    </aside>
    <main v-if="showChatPane" class="messaging-layout__chat">
      <ConversationChatView
        v-if="isChatRoute"
        :key="String(conversationId)"
        :pane-mode="isDesktop"
      />
      <div v-else-if="isDesktop" class="messaging-layout__empty">
        <p>{{ t('conversations.selectChat') }}</p>
      </div>
    </main>
  </div>
</template>

<style scoped>
.messaging-layout {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  width: 100%;
  overflow: hidden;
  background: var(--bg-primary);
}

.messaging-layout:not(.messaging-layout--desktop) {
  position: absolute;
  inset: 0;
}

.messaging-layout__list,
.messaging-layout__chat {
  flex: 1;
  min-height: 0;
  min-width: 0;
  overflow: hidden;
}

.messaging-layout:not(.messaging-layout--desktop) .messaging-layout__list,
.messaging-layout:not(.messaging-layout--desktop) .messaging-layout__chat {
  flex: 1;
  width: 100%;
}

/* Desktop split: override scoped column flex (was stacking list + chat vertically) */
@media (min-width: 1024px) {
  .messaging-layout.messaging-layout--desktop {
    display: grid;
    grid-template-columns: var(--messaging-list-width, min(380px, 32vw)) minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr);
    flex-direction: unset;
    position: relative;
    inset: auto;
    height: 100%;
    max-height: 100%;
  }

  .messaging-layout--desktop .messaging-layout__list {
    grid-column: 1;
    grid-row: 1;
    flex: unset;
    display: flex;
    flex-direction: column;
    border-inline-end: 1px solid var(--border);
  }

  .messaging-layout--desktop .messaging-layout__chat {
    grid-column: 2;
    grid-row: 1;
    flex: unset;
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
}
</style>
