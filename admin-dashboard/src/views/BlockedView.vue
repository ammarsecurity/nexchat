<script setup>
import { ref, watch, onMounted } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'
import UserCell from '../components/UserCell.vue'

const blocks = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(20)
const search = ref('')
const loading = ref(false)
const deleteDialog = ref(false)
const selectedBlock = ref(null)
const deleteLoading = ref(false)

const headers = [
  { title: 'الحاظر', key: 'blockerName', sortable: false, minWidth: '160px' },
  { title: 'المحظور', key: 'blockedUserName', sortable: false, minWidth: '160px' },
  { title: 'التاريخ', key: 'createdAt', sortable: false },
  { title: 'إجراءات', key: 'actions', sortable: false, align: 'center' },
]

async function fetchBlocks() {
  loading.value = true
  try {
    const res = await api.get('/admin/blocks', {
      params: { page: page.value, pageSize: pageSize.value, search: search.value || undefined }
    })
    blocks.value = res.data.items
    total.value = res.data.total
  } catch {
    blocks.value = []
    total.value = 0
  } finally {
    loading.value = false
  }
}

function confirmUnblock(block) {
  selectedBlock.value = block
  deleteDialog.value = true
}

async function executeUnblock() {
  deleteLoading.value = true
  try {
    await api.delete(`/admin/blocks/${selectedBlock.value.id}`)
    deleteDialog.value = false
    selectedBlock.value = null
    fetchBlocks()
  } catch (e) {
    notify.error(e.response?.data?.message || 'حدث خطأ')
  } finally {
    deleteLoading.value = false
  }
}

function cancelDelete() {
  deleteDialog.value = false
  selectedBlock.value = null
}

function formatDate(date) {
  return new Date(date).toLocaleDateString('ar', { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

let searchTimeout
function onSearch() {
  clearTimeout(searchTimeout)
  searchTimeout = setTimeout(() => { page.value = 1; fetchBlocks() }, 400)
}

watch(page, fetchBlocks)
onMounted(fetchBlocks)
</script>

<template>
  <div>
    <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between mb-4 mb-sm-6 gap-2">
      <div>
        <div class="text-h5 font-weight-bold">المحظورون</div>
        <div class="text-body-2 text-medium-emphasis">
          {{ total.toLocaleString() }} سجل حظر
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
        :items="blocks"
        :loading="loading"
        :items-per-page="-1"
        hide-default-footer
        class="blocks-table"
        no-data-text="لا توجد سجلات حظر"
        loading-text="جاري التحميل..."
      >
        <template #item.blockerName="{ item }">
          <UserCell :name="item.blockerName" :avatar="item.blockerAvatar" />
        </template>
        <template #item.blockedUserName="{ item }">
          <UserCell :name="item.blockedUserName" :avatar="item.blockedUserAvatar" color="error" />
        </template>
        <template #item.createdAt="{ item }">
          <span class="text-medium-emphasis text-body-2">{{ formatDate(item.createdAt) }}</span>
        </template>
        <template #item.actions="{ item }">
          <div class="action-btns">
            <v-btn
              icon="mdi-lock-open"
              size="small"
              variant="tonal"
              color="success"
              title="فك الحظر"
              @click="confirmUnblock(item)"
            />
          </div>
        </template>
      </v-data-table>
      <div v-if="total > 0" class="pagination-bar">
        <v-pagination
          v-model="page"
          :length="Math.max(1, Math.ceil(total / pageSize))"
          :total-visible="7"
          density="comfortable"
          active-color="primary"
          @update:model-value="fetchBlocks"
        />
      </div>
    </v-card>

    <v-dialog v-model="deleteDialog" max-width="400" persistent>
      <v-card>
        <v-card-title>فك الحظر</v-card-title>
        <v-card-text>
          هل تريد فك حظر <strong>{{ selectedBlock?.blockedUserName }}</strong> من قائمة <strong>{{ selectedBlock?.blockerName }}</strong>؟
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="cancelDelete">إلغاء</v-btn>
          <v-btn color="success" :loading="deleteLoading" @click="executeUnblock">فك الحظر</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.blocks-table :deep(.v-data-table__td) {
  padding: 12px 16px;
}
</style>
