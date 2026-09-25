<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'
import UserCell from '../components/UserCell.vue'

const reports = ref([])
const total = ref(0)
const page = ref(1)
const loading = ref(false)
const showPending = ref(true)

const headers = [
  { title: 'المُبلِّغ', key: 'reporterName', sortable: false, minWidth: '160px' },
  { title: 'المُبلَّغ عنه', key: 'reportedName', sortable: false, minWidth: '160px' },
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
        :items-per-page="-1"
        hide-default-footer
      >
        <template #item.reporterName="{ item }">
          <UserCell :name="item.reporterName" :avatar="item.reporterAvatar" color="info" />
        </template>

        <template #item.reportedName="{ item }">
          <UserCell :name="item.reportedName" :avatar="item.reportedAvatar" color="error" />
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
          <div class="action-btns">
            <v-btn
              v-if="!item.isReviewed"
              icon="mdi-check-circle"
              size="small"
              variant="tonal"
              color="success"
              title="تمت المراجعة"
              @click="reviewReport(item.id)"
            />
            <v-btn
              icon="mdi-account-cancel"
              size="small"
              variant="tonal"
              color="error"
              title="حظر المُبلَّغ عنه"
            />
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
          @update:model-value="fetchReports"
        />
      </div>
    </v-card>
  </div>
</template>
