<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'
import UserCell from '../components/UserCell.vue'

const sessions = ref([])
const total = ref(0)
const page = ref(1)
const loading = ref(false)
const closingInactive = ref(false)

const headers = [
  { title: 'المستخدم 1', key: 'user1Name', sortable: false, minWidth: '160px' },
  { title: 'المستخدم 2', key: 'user2Name', sortable: false, minWidth: '160px' },
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

async function closeInactiveSessions(closeAll = false) {
  closingInactive.value = true
  try {
    const params = closeAll ? { closeAll: true } : { minutes: 15 }
    const res = await api.post('/admin/close-inactive-sessions', null, { params })
    notify.success(res.data?.message ?? `تم إغلاق ${res.data?.closedCount ?? 0} جلسة`)
    await fetchSessions()
  } catch (e) {
    notify.error(e.response?.data?.message ?? 'حدث خطأ')
  } finally {
    closingInactive.value = false
  }
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
      <div class="page-actions flex-shrink-0">
        <v-btn
          prepend-icon="mdi-clock-off-outline"
          variant="tonal"
          color="warning"
          size="small"
          :loading="closingInactive"
          @click="closeInactiveSessions(false)"
        >إغلاق غير النشطة (15 د)</v-btn>
        <v-btn
          prepend-icon="mdi-stop-circle"
          variant="tonal"
          color="error"
          size="small"
          :loading="closingInactive"
          @click="closeInactiveSessions(true)"
        >إغلاق الكل</v-btn>
        <v-btn
          prepend-icon="mdi-refresh"
          variant="tonal"
          color="primary"
          size="small"
          @click="fetchSessions"
        >تحديث</v-btn>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4 table-card">
      <v-data-table
        :headers="headers"
        :items="sessions"
        :loading="loading"
        :items-per-page="-1"
        hide-default-footer
      >
        <template #item.user1Name="{ item }">
          <UserCell :name="item.user1Name" :avatar="item.user1Avatar" />
        </template>

        <template #item.user2Name="{ item }">
          <UserCell :name="item.user2Name" :avatar="item.user2Avatar" color="secondary" />
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
      </v-data-table>
      <div v-if="total > 0" class="pagination-bar">
        <v-pagination
          v-model="page"
          :length="Math.max(1, Math.ceil(total / 20))"
          :total-visible="7"
          density="comfortable"
          active-color="primary"
          @update:model-value="fetchSessions"
        />
      </div>
    </v-card>
  </div>
</template>
