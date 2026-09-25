<script setup>
import { ref, watch, onMounted } from 'vue'
import api from '../services/api'
import UserCell from '../components/UserCell.vue'
import { formatIraqDate, formatIraqDateTime, formatIraqTime } from '../utils/iraqTime'

const contacts = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(20)
const search = ref('')
const loading = ref(false)

const headers = [
  { title: 'المستخدم', key: 'userName', sortable: false, minWidth: '160px' },
  { title: 'جهة الاتصال', key: 'contactUserName', sortable: false, minWidth: '160px' },
  { title: 'التاريخ', key: 'createdAt', sortable: false },
]

async function fetchContacts() {
  loading.value = true
  try {
    const res = await api.get('/admin/contacts', {
      params: { page: page.value, pageSize: pageSize.value, search: search.value || undefined }
    })
    contacts.value = res.data.items
    total.value = res.data.total
  } catch {
    contacts.value = []
    total.value = 0
  } finally {
    loading.value = false
  }
}

function formatDate(dt) {
  return formatIraqDate(dt)
}

let searchTimeout
function onSearch() {
  clearTimeout(searchTimeout)
  searchTimeout = setTimeout(() => { page.value = 1; fetchContacts() }, 400)
}

watch(page, fetchContacts)
onMounted(fetchContacts)
</script>

<template>
  <div>
    <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between mb-4 mb-sm-6 gap-2">
      <div>
        <div class="text-h5 font-weight-bold">جهات الاتصال</div>
        <div class="text-body-2 text-medium-emphasis">
          {{ total.toLocaleString() }} علاقة صداقة
        </div>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4 table-card">
      <div class="d-flex flex-column flex-sm-row gap-3 mb-4">
        <v-text-field
          v-model="search"
          placeholder="بحث بالاسم..."
          prepend-inner-icon="mdi-magnify"
          variant="outlined"
          density="compact"
          rounded="lg"
          hide-details
          clearable
          style="max-width: 280px;"
          @input="onSearch"
        />
      </div>

      <v-data-table
        :headers="headers"
        :items="contacts"
        :loading="loading"
        :items-per-page="-1"
        hide-default-footer
        class="contacts-table"
        no-data-text="لا توجد جهات اتصال"
        loading-text="جاري التحميل..."
      >
        <template #item.userName="{ item }">
          <UserCell :name="item.userName" :avatar="item.userAvatar" />
        </template>
        <template #item.contactUserName="{ item }">
          <UserCell :name="item.contactUserName" :avatar="item.contactUserAvatar" color="secondary" />
        </template>
        <template #item.createdAt="{ item }">
          <span class="text-medium-emphasis text-body-2">{{ formatDate(item.createdAt) }}</span>
        </template>
      </v-data-table>

      <div v-if="total > 0" class="pagination-bar">
        <v-pagination
          v-model="page"
          :length="Math.max(1, Math.ceil(total / pageSize))"
          :total-visible="7"
          density="comfortable"
          active-color="primary"
          @update:model-value="fetchContacts"
        />
      </div>
    </v-card>
  </div>
</template>

<style scoped>
.contacts-table :deep(.v-data-table__td) {
  padding: 12px 16px;
}
</style>
