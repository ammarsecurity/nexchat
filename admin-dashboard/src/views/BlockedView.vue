<script setup>
import { ref, watch, onMounted } from 'vue'
import api from '../services/api'

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
  { title: 'الحاظر', key: 'blockerName', sortable: false },
  { title: 'المحظور', key: 'blockedUserName', sortable: false },
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
    alert(e.response?.data?.message || 'حدث خطأ')
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
        :items="blocks"
        :loading="loading"
        :items-per-page="pageSize"
        hide-default-footer
        class="blocks-table"
        no-data-text="لا توجد سجلات حظر"
        loading-text="جاري التحميل..."
      >
        <template #item.blockerName="{ item }">
          <span class="font-weight-medium">{{ item.blockerName }}</span>
        </template>
        <template #item.blockedUserName="{ item }">
          <span class="font-weight-medium">{{ item.blockedUserName }}</span>
        </template>
        <template #item.createdAt="{ item }">
          {{ formatDate(item.createdAt) }}
        </template>
        <template #item.actions="{ item }">
          <v-btn
            color="success"
            variant="tonal"
            size="small"
            icon="mdi-lock-open"
            @click="confirmUnblock(item)"
            title="فك الحظر"
          />
        </template>

        <template #bottom>
          <div v-if="total > pageSize" class="d-flex justify-center pt-4">
            <v-pagination
              v-model="page"
              :length="Math.ceil(total / pageSize)"
              @update:model-value="fetchBlocks"
              active-color="primary"
              size="small"
            />
          </div>
        </template>
      </v-data-table>
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
