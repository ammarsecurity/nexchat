<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'

const users = ref([])
const total = ref(0)
const page = ref(1)
const loading = ref(false)
const search = ref('')
const banDialog = ref(false)
const selectedUser = ref(null)
const banAction = ref(true)

const headers = [
  { title: 'المستخدم', key: 'name', sortable: false },
  { title: 'الكود', key: 'uniqueCode', sortable: false },
  { title: 'الجنس', key: 'gender', sortable: false },
  { title: 'الحالة', key: 'isOnline', sortable: false },
  { title: 'تاريخ الانضمام', key: 'createdAt', sortable: false },
  { title: 'إجراءات', key: 'actions', sortable: false, align: 'center' },
]

const genderLabel = { male: 'ذكر', female: 'أنثى', other: 'آخر' }
const genderColor = { male: 'primary', female: 'secondary', other: 'info' }

async function fetchUsers() {
  loading.value = true
  try {
    const res = await api.get('/admin/users', {
      params: { page: page.value, pageSize: 20, search: search.value || undefined }
    })
    users.value = res.data.items
    total.value = res.data.total
  } catch {
    users.value = []
  } finally {
    loading.value = false
  }
}

function confirmBan(user, ban) {
  selectedUser.value = user
  banAction.value = ban
  banDialog.value = true
}

async function executeBan() {
  await api.put(`/admin/users/${selectedUser.value.id}/ban`, banAction.value)
  banDialog.value = false
  fetchUsers()
}

function formatDate(date) {
  return new Date(date).toLocaleDateString('ar', { year: 'numeric', month: 'short', day: 'numeric' })
}

let searchTimeout
function onSearch() {
  clearTimeout(searchTimeout)
  searchTimeout = setTimeout(() => { page.value = 1; fetchUsers() }, 400)
}

onMounted(fetchUsers)
</script>

<template>
  <div>
    <div class="d-flex align-center justify-space-between mb-6">
      <div>
        <div class="text-h5 font-weight-bold">المستخدمين</div>
        <div class="text-body-2 text-medium-emphasis">إجمالي {{ total.toLocaleString() }} مستخدم</div>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-4">
      <v-text-field
        v-model="search"
        label="بحث بالاسم أو الكود..."
        prepend-inner-icon="mdi-magnify"
        variant="outlined"
        rounded="lg"
        density="compact"
        clearable
        class="mb-4"
        hide-details
        @update:model-value="onSearch"
      />

      <v-data-table
        :headers="headers"
        :items="users"
        :loading="loading"
        :items-per-page="20"
        hide-default-footer
        item-value="id"
        color="transparent"
      >
        <template #item.name="{ item }">
          <div class="d-flex align-center gap-3 py-2">
            <v-avatar size="36" :color="item.isBanned ? 'error' : 'primary'" variant="tonal">
              <span class="font-weight-bold">{{ item.name[0].toUpperCase() }}</span>
            </v-avatar>
            <div>
              <div class="font-weight-medium">{{ item.name }}</div>
              <div v-if="item.isBanned" class="text-caption text-error">محظور</div>
            </div>
          </div>
        </template>

        <template #item.uniqueCode="{ item }">
          <v-chip size="small" variant="tonal" color="primary" label>
            {{ item.uniqueCode }}
          </v-chip>
        </template>

        <template #item.gender="{ item }">
          <v-chip size="small" :color="genderColor[item.gender]" variant="tonal">
            {{ genderLabel[item.gender] }}
          </v-chip>
        </template>

        <template #item.isOnline="{ item }">
          <v-chip
            size="small"
            :color="item.isOnline ? 'success' : 'default'"
            variant="tonal"
            :prepend-icon="item.isOnline ? 'mdi-circle' : 'mdi-circle-outline'"
          >
            {{ item.isOnline ? 'متصل' : 'غير متصل' }}
          </v-chip>
        </template>

        <template #item.createdAt="{ item }">
          <span class="text-medium-emphasis text-body-2">{{ formatDate(item.createdAt) }}</span>
        </template>

        <template #item.actions="{ item }">
          <v-btn
            v-if="!item.isBanned"
            icon="mdi-account-cancel"
            size="small"
            variant="tonal"
            color="error"
            @click="confirmBan(item, true)"
          ></v-btn>
          <v-btn
            v-else
            icon="mdi-account-check"
            size="small"
            variant="tonal"
            color="success"
            @click="confirmBan(item, false)"
          ></v-btn>
        </template>

        <template #bottom>
          <div class="d-flex justify-center pt-4">
            <v-pagination
              v-model="page"
              :length="Math.ceil(total / 20)"
              @update:model-value="fetchUsers"
              active-color="primary"
              size="small"
            ></v-pagination>
          </div>
        </template>
      </v-data-table>
    </v-card>

    <!-- Ban Dialog -->
    <v-dialog v-model="banDialog" max-width="400">
      <v-card rounded="xl" elevation="0" class="pa-4">
        <v-card-title class="font-weight-bold">
          {{ banAction ? '🚫 حظر المستخدم' : '✅ رفع الحظر' }}
        </v-card-title>
        <v-card-text>
          هل أنت متأكد من {{ banAction ? 'حظر' : 'رفع حظر' }}
          <strong>{{ selectedUser?.name }}</strong>؟
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn @click="banDialog = false" variant="text">إلغاء</v-btn>
          <v-btn
            :color="banAction ? 'error' : 'success'"
            variant="tonal"
            @click="executeBan"
          >
            تأكيد
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>
