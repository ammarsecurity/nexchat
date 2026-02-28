<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const reports = ref([])
const total = ref(0)
const page = ref(1)
const loading = ref(false)
const showPending = ref(true)

const headers = [
  { title: 'المُبلِّغ', key: 'reporterName' },
  { title: 'المُبلَّغ عنه', key: 'reportedName' },
  { title: 'السبب', key: 'reason' },
  { title: 'التاريخ', key: 'createdAt' },
  { title: 'الحالة', key: 'isReviewed', align: 'center' },
  { title: 'إجراءات', key: 'actions', sortable: false, align: 'center' },
]

async function fetchReports() {
  loading.value = true
  try {
    const res = await api.get('/admin/reports', {
      params: { page: page.value, pageSize: 20, onlyPending: showPending.value }
    })
    reports.value = res.data.items
    total.value = res.data.total
  } catch {
    reports.value = []
  } finally {
    loading.value = false
  }
}

async function reviewReport(id) {
  await api.put(`/admin/reports/${id}/review`)
  fetchReports()
}

async function banReported(userId) {
  await api.put(`/admin/users/${userId}/ban`, true)
  fetchReports()
}

function formatDate(date) {
  return new Date(date).toLocaleDateString('ar', {
    year: 'numeric', month: 'short', day: 'numeric'
  })
}

onMounted(fetchReports)
</script>

<template>
  <div>
    <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between mb-4 mb-sm-6 gap-3">
      <div>
        <div class="text-h5 font-weight-bold">البلاغات</div>
        <div class="text-body-2 text-medium-emphasis">{{ total }} بلاغ</div>
      </div>
      <v-switch
        v-model="showPending"
        label="البلاغات المعلقة فقط"
        color="primary"
        hide-details
        density="compact"
        class="flex-shrink-0"
        @update:model-value="fetchReports"
      />
    </div>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4 table-card">
      <v-data-table
        :headers="headers"
        :items="reports"
        :loading="loading"
        :items-per-page="20"
        hide-default-footer
      >
        <template #item.reporterName="{ item }">
          <v-chip size="small" variant="tonal" prepend-icon="mdi-account" color="info">
            {{ item.reporterName }}
          </v-chip>
        </template>

        <template #item.reportedName="{ item }">
          <v-chip size="small" variant="tonal" prepend-icon="mdi-account-alert" color="error">
            {{ item.reportedName }}
          </v-chip>
        </template>

        <template #item.reason="{ item }">
          <v-tooltip :text="item.reason" location="top">
            <template #activator="{ props }">
              <span v-bind="props" class="text-truncate d-inline-block" style="max-width:160px">
                {{ item.reason }}
              </span>
            </template>
          </v-tooltip>
        </template>

        <template #item.createdAt="{ item }">
          <span class="text-medium-emphasis text-body-2">{{ formatDate(item.createdAt) }}</span>
        </template>

        <template #item.isReviewed="{ item }">
          <v-chip
            size="small"
            :color="item.isReviewed ? 'success' : 'warning'"
            variant="tonal"
          >
            {{ item.isReviewed ? 'تمت المراجعة' : 'معلق' }}
          </v-chip>
        </template>

        <template #item.actions="{ item }">
          <div class="d-flex gap-1 justify-center">
            <v-btn
              v-if="!item.isReviewed"
              icon="mdi-check-circle"
              size="small"
              variant="tonal"
              color="success"
              @click="reviewReport(item.id)"
            ></v-btn>
            <v-btn
              icon="mdi-account-cancel"
              size="small"
              variant="tonal"
              color="error"
              title="حظر المُبلَّغ عنه"
            ></v-btn>
          </div>
        </template>

        <template #bottom>
          <div class="d-flex justify-center pt-4">
            <v-pagination
              v-model="page"
              :length="Math.ceil(total / 20)"
              @update:model-value="fetchReports"
              active-color="primary"
              size="small"
            ></v-pagination>
          </div>
        </template>
      </v-data-table>
    </v-card>
  </div>
</template>
