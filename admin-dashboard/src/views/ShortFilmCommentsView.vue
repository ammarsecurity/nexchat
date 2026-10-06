<script setup>
import { ref, onMounted, watch } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'
import { formatIraqDateTime } from '../utils/iraqTime'
import UserCell from '../components/UserCell.vue'

const items = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = 30
const loading = ref(false)
const status = ref('reported')
const busyId = ref(null)

const headers = [
  { title: 'المستخدم', key: 'userName', sortable: false, minWidth: '150px' },
  { title: 'الفيلم', key: 'filmTitle', sortable: false, minWidth: '160px' },
  { title: 'التعليق', key: 'body', sortable: false },
  { title: 'بلاغات', key: 'reportCount', align: 'center', width: '90px' },
  { title: 'الحالة', key: 'isHidden', align: 'center', width: '110px' },
  { title: 'التاريخ', key: 'createdAt', width: '150px' },
  { title: 'إجراءات', key: 'actions', sortable: false, align: 'center', width: '220px' },
]

async function fetchComments() {
  loading.value = true
  try {
    const res = await api.get('/admin/short-film-comments', {
      params: { page: page.value, pageSize, status: status.value }
    })
    items.value = res.data?.items ?? []
    total.value = res.data?.total ?? 0
  } catch {
    items.value = []
    total.value = 0
  } finally {
    loading.value = false
  }
}

async function hide(id) {
  busyId.value = id
  try {
    await api.post(`/admin/short-film-comments/${id}/hide`)
    notify.success('تم إخفاء التعليق')
    await fetchComments()
  } catch (e) {
    notify.error(e.response?.data?.message || 'تعذر الإخفاء')
  } finally {
    busyId.value = null
  }
}

async function unhide(id) {
  busyId.value = id
  try {
    await api.post(`/admin/short-film-comments/${id}/unhide`)
    notify.success('تم إظهار التعليق')
    await fetchComments()
  } catch (e) {
    notify.error(e.response?.data?.message || 'تعذر الإظهار')
  } finally {
    busyId.value = null
  }
}

async function remove(id) {
  if (!confirm('حذف التعليق نهائياً؟')) return
  busyId.value = id
  try {
    await api.delete(`/admin/short-film-comments/${id}`)
    notify.success('تم الحذف')
    await fetchComments()
  } catch (e) {
    notify.error(e.response?.data?.message || 'تعذر الحذف')
  } finally {
    busyId.value = null
  }
}

watch([status, page], fetchComments)
onMounted(fetchComments)
</script>

<template>
  <div>
    <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between mb-4 mb-sm-6 gap-3">
      <div>
        <div class="text-h5 font-weight-bold">تعليقات الأفلام</div>
        <div class="text-body-2 text-medium-emphasis">{{ total }} تعليق</div>
      </div>
      <div class="d-flex flex-wrap gap-2 align-center">
        <v-btn-toggle v-model="status" mandatory density="compact" color="primary" rounded="lg">
          <v-btn value="reported" size="small">مُبلَّغ عنها</v-btn>
          <v-btn value="visible" size="small">ظاهرة</v-btn>
          <v-btn value="hidden" size="small">مخفية</v-btn>
          <v-btn value="all" size="small">الكل</v-btn>
        </v-btn-toggle>
        <v-btn icon="mdi-refresh" variant="tonal" size="small" :loading="loading" @click="fetchComments" />
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4">
      <v-data-table
        :headers="headers"
        :items="items"
        :loading="loading"
        :items-per-page="-1"
        hide-default-footer
      >
        <template #item.userName="{ item }">
          <UserCell :name="item.userName" :avatar="item.userAvatar" />
        </template>
        <template #item.filmTitle="{ item }">
          <div class="text-body-2 font-weight-medium text-truncate" style="max-width:180px">
            {{ item.filmTitle || '—' }}
          </div>
        </template>
        <template #item.body="{ item }">
          <div class="text-body-2" style="white-space: pre-wrap; max-width: 360px">{{ item.body }}</div>
        </template>
        <template #item.reportCount="{ item }">
          <v-chip size="small" :color="item.reportCount > 0 ? 'warning' : 'default'" variant="tonal">
            {{ item.reportCount }}
          </v-chip>
        </template>
        <template #item.isHidden="{ item }">
          <v-chip size="small" :color="item.isHidden ? 'error' : 'success'" variant="tonal">
            {{ item.isHidden ? 'مخفي' : 'ظاهر' }}
          </v-chip>
        </template>
        <template #item.createdAt="{ item }">
          <span class="text-medium-emphasis text-body-2">{{ formatIraqDateTime(item.createdAt) }}</span>
        </template>
        <template #item.actions="{ item }">
          <div class="d-flex justify-center gap-1">
            <v-btn
              v-if="!item.isHidden"
              size="small"
              variant="tonal"
              color="warning"
              :loading="busyId === item.id"
              @click="hide(item.id)"
            >
              إخفاء
            </v-btn>
            <v-btn
              v-else
              size="small"
              variant="tonal"
              color="success"
              :loading="busyId === item.id"
              @click="unhide(item.id)"
            >
              إظهار
            </v-btn>
            <v-btn
              size="small"
              variant="tonal"
              color="error"
              :loading="busyId === item.id"
              @click="remove(item.id)"
            >
              حذف
            </v-btn>
          </div>
        </template>
      </v-data-table>

      <div v-if="total > pageSize" class="d-flex justify-center mt-4">
        <v-pagination
          v-model="page"
          :length="Math.max(1, Math.ceil(total / pageSize))"
          density="compact"
          rounded
        />
      </div>
    </v-card>
  </div>
</template>
