<script setup>
import { ref, watch, onMounted } from 'vue'
import api from '../services/api'

const contacts = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(20)
const search = ref('')
const loading = ref(false)

const headers = [
  { title: 'المستخدم', key: 'userName', sortable: false },
  { title: 'جهة الاتصال', key: 'contactUserName', sortable: false },
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

function formatDate(date) {
  return new Date(date).toLocaleDateString('ar', { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
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

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4" style="background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08);">
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
          bg-color="rgba(255,255,255,0.04)"
          style="max-width: 280px;"
          @input="onSearch"
        />
      </div>

      <v-data-table
        :headers="headers"
        :items="contacts"
        :loading="loading"
        :items-per-page="pageSize"
        hide-default-footer
        class="contacts-table"
        no-data-text="لا توجد جهات اتصال"
        loading-text="جاري التحميل..."
      >
        <template #item.userName="{ item }">
          <span class="font-weight-medium">{{ item.userName }}</span>
        </template>
        <template #item.contactUserName="{ item }">
          <span class="font-weight-medium">{{ item.contactUserName }}</span>
        </template>
        <template #item.createdAt="{ item }">
          {{ formatDate(item.createdAt) }}
        </template>

        <template #bottom>
          <div v-if="total > pageSize" class="d-flex justify-center pt-4">
            <v-pagination
              v-model="page"
              :length="Math.ceil(total / pageSize)"
              @update:model-value="fetchContacts"
              active-color="primary"
              size="small"
            />
          </div>
        </template>
      </v-data-table>
    </v-card>
  </div>
</template>

<style scoped>
.contacts-table :deep(.v-data-table__td) {
  padding: 12px 16px;
}
</style>
