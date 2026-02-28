<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const sessions = ref([])
const total = ref(0)
const page = ref(1)
const loading = ref(false)

const headers = [
  { title: 'المستخدم 1', key: 'user1Name' },
  { title: 'المستخدم 2', key: 'user2Name' },
  { title: 'النوع', key: 'type' },
  { title: 'الرسائل', key: 'messageCount', align: 'center' },
  { title: 'البداية', key: 'startedAt' },
  { title: 'الحالة', key: 'endedAt' },
]

async function fetchSessions() {
  loading.value = true
  try {
    const res = await api.get('/admin/sessions', { params: { page: page.value, pageSize: 20 } })
    sessions.value = res.data.items
    total.value = res.data.total
  } catch {
    sessions.value = []
  } finally {
    loading.value = false
  }
}

function formatTime(date) {
  return new Date(date).toLocaleString('ar', {
    month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit'
  })
}

function getDuration(start, end) {
  const s = new Date(start)
  const e = end ? new Date(end) : new Date()
  const diffMs = e - s
  const m = Math.floor(diffMs / 60000)
  const s2 = Math.floor((diffMs % 60000) / 1000)
  return `${m}:${s2.toString().padStart(2, '0')}`
}

onMounted(fetchSessions)
</script>

<template>
  <div>
    <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between mb-4 mb-sm-6 gap-3">
      <div>
        <div class="text-h5 font-weight-bold">الجلسات</div>
        <div class="text-body-2 text-medium-emphasis">{{ total.toLocaleString() }} جلسة إجمالاً</div>
      </div>
      <v-btn
        prepend-icon="mdi-refresh"
        variant="tonal"
        color="primary"
        size="small"
        class="flex-shrink-0"
        @click="fetchSessions"
      >تحديث</v-btn>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4 table-card">
      <v-data-table
        :headers="headers"
        :items="sessions"
        :loading="loading"
        :items-per-page="20"
        hide-default-footer
      >
        <template #item.user1Name="{ item }">
          <v-chip size="small" variant="tonal" color="primary" prepend-icon="mdi-account">
            {{ item.user1Name }}
          </v-chip>
        </template>

        <template #item.user2Name="{ item }">
          <v-chip size="small" variant="tonal" color="secondary" prepend-icon="mdi-account">
            {{ item.user2Name }}
          </v-chip>
        </template>

        <template #item.type="{ item }">
          <v-chip
            size="small"
            :color="item.type === 'random' ? 'info' : 'warning'"
            variant="tonal"
            :prepend-icon="item.type === 'random' ? 'mdi-shuffle' : 'mdi-key'"
          >
            {{ item.type === 'random' ? 'عشوائي' : 'كود' }}
          </v-chip>
        </template>

        <template #item.messageCount="{ item }">
          <v-chip size="small" variant="text" prepend-icon="mdi-message">
            {{ item.messageCount }}
          </v-chip>
        </template>

        <template #item.startedAt="{ item }">
          <span class="text-medium-emphasis text-body-2">{{ formatTime(item.startedAt) }}</span>
        </template>

        <template #item.endedAt="{ item }">
          <div>
            <v-chip
              size="small"
              :color="item.endedAt ? 'default' : 'success'"
              variant="tonal"
              :prepend-icon="item.endedAt ? 'mdi-stop-circle' : 'mdi-circle'"
            >
              {{ item.endedAt ? 'منتهية' : 'نشطة' }}
            </v-chip>
            <div class="text-caption text-medium-emphasis mt-1">
              {{ getDuration(item.startedAt, item.endedAt) }}
            </div>
          </div>
        </template>

        <template #bottom>
          <div class="d-flex justify-center pt-4">
            <v-pagination
              v-model="page"
              :length="Math.ceil(total / 20)"
              @update:model-value="fetchSessions"
              active-color="primary"
              size="small"
            ></v-pagination>
          </div>
        </template>
      </v-data-table>
    </v-card>
  </div>
</template>
