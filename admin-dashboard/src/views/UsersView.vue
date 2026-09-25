<script setup>
import { ref, onMounted } from 'vue'
import api from '../services/api'
import { notify } from '../utils/notify'
import { fullMediaUrl, hasAvatarImage, userInitial } from '../utils/media'
import { formatIraqDate, formatIraqDateTime, formatIraqTime } from '../utils/iraqTime'

const users = ref([])
const total = ref(0)
const page = ref(1)
const loading = ref(false)
const search = ref('')
const banDialog = ref(false)
const selectedUser = ref(null)
const banAction = ref(true)
const featuredLoading = ref(null)
const selectedIds = ref([])
const deleteDialog = ref(false)
const deleteTarget = ref(null)
const deleteLoading = ref(false)

const passwordDialog = ref(false)
const passwordUser = ref(null)
const newPassword = ref('')
const confirmPassword = ref('')
const showPassword = ref(false)
const passwordLoading = ref(false)

const headers = [
  { title: 'المستخدم', key: 'name', sortable: false, minWidth: '220px' },
  { title: 'الكود', key: 'uniqueCode', sortable: false },
  { title: 'الجنس', key: 'gender', sortable: false },
  { title: 'العمر', key: 'age', sortable: false },
  { title: 'الهاتف', key: 'phoneNumber', sortable: false },
  { title: 'الحالة', key: 'isOnline', sortable: false },
  { title: 'الانضمام', key: 'createdAt', sortable: false },
  { title: 'إجراءات', key: 'actions', sortable: false, align: 'center', minWidth: '200px' },
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

function confirmDelete(user) {
  deleteTarget.value = user
  deleteDialog.value = true
}

function confirmBulkDelete() {
  deleteTarget.value = 'bulk'
  deleteDialog.value = true
}

async function executeDelete() {
  deleteLoading.value = true
  try {
    if (deleteTarget.value === 'bulk') {
      await api.delete('/admin/users', { data: { ids: selectedIds.value } })
      selectedIds.value = []
    } else {
      await api.delete(`/admin/users/${deleteTarget.value.id}`)
    }
    deleteDialog.value = false
    deleteTarget.value = null
    fetchUsers()
  } catch (e) {
    notify.error(e.response?.data?.message || 'حدث خطأ')
  } finally {
    deleteLoading.value = false
  }
}

function cancelDelete() {
  deleteDialog.value = false
  deleteTarget.value = null
}

async function toggleFeatured(user) {
  featuredLoading.value = user.id
  try {
    await api.put(`/admin/users/${user.id}/featured`, { featured: !user.isFeatured })
    fetchUsers()
  } catch (e) {
    if (e.response?.data?.message) notify.error(e.response.data.message)
  } finally {
    featuredLoading.value = null
  }
}

function openPasswordDialog(user) {
  passwordUser.value = user
  newPassword.value = ''
  confirmPassword.value = ''
  showPassword.value = false
  passwordDialog.value = true
}

function closePasswordDialog() {
  passwordDialog.value = false
  passwordUser.value = null
  newPassword.value = ''
  confirmPassword.value = ''
}

async function executePasswordChange() {
  const pwd = newPassword.value.trim()
  if (pwd.length < 6) {
    notify.error('كلمة المرور يجب أن تكون 6 أحرف على الأقل')
    return
  }
  if (pwd !== confirmPassword.value.trim()) {
    notify.error('كلمتا المرور غير متطابقتين')
    return
  }

  passwordLoading.value = true
  try {
    await api.put(`/admin/users/${passwordUser.value.id}/password`, { password: pwd })
    notify.success('تم تحديث كلمة المرور بنجاح')
    closePasswordDialog()
  } catch (e) {
    notify.error(e.response?.data?.message || 'فشل تحديث كلمة المرور')
  } finally {
    passwordLoading.value = false
  }
}

function formatDate(dt) {
  return formatIraqDate(dt)
}

function getAge(birthDate) {
  if (!birthDate) return null
  const bd = new Date(birthDate)
  const today = new Date()
  let age = today.getFullYear() - bd.getFullYear()
  const m = today.getMonth() - bd.getMonth()
  if (m < 0 || (m === 0 && today.getDate() < bd.getDate())) age--
  return age >= 0 ? age : null
}

function formatPhone(phone) {
  if (!phone || !phone.trim()) return '—'
  return '+' + phone
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
    <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between mb-4 mb-sm-6 gap-2">
      <div>
        <div class="text-h5 font-weight-bold">المستخدمين</div>
        <div class="text-body-2 text-medium-emphasis">إجمالي {{ total.toLocaleString() }} مستخدم</div>
      </div>
      <div v-if="selectedIds.length" class="page-actions">
        <v-btn
          color="error"
          variant="tonal"
          prepend-icon="mdi-delete"
          size="small"
          :loading="deleteLoading"
          @click="confirmBulkDelete"
        >
          حذف المحدد ({{ selectedIds.length }})
        </v-btn>
      </div>
    </div>

    <v-card rounded="xl" elevation="0" class="pa-3 pa-sm-4 table-card">
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
        v-model="selectedIds"
        :headers="headers"
        :items="users"
        :loading="loading"
        :items-per-page="-1"
        hide-default-footer
        item-value="id"
        show-select
        class="users-table"
      >
        <template #item.name="{ item }">
          <div class="user-cell">
            <v-avatar
              size="42"
              :color="hasAvatarImage(item.avatar) ? undefined : (item.isBanned ? 'error' : item.isFeatured ? 'warning' : 'primary')"
              :variant="hasAvatarImage(item.avatar) ? undefined : 'tonal'"
              class="user-avatar"
            >
              <v-img
                v-if="hasAvatarImage(item.avatar)"
                :src="fullMediaUrl(item.avatar)"
                cover
                alt=""
              >
                <template #error>
                  <div class="avatar-fallback">{{ userInitial(item.name) }}</div>
                </template>
              </v-img>
              <span v-else class="font-weight-bold">{{ userInitial(item.name) }}</span>
            </v-avatar>
            <div class="user-meta">
              <div class="user-name-row">
                <span class="user-name">{{ item.name }}</span>
                <v-icon v-if="item.isFeatured" size="16" color="warning" title="مميز">mdi-crown</v-icon>
              </div>
              <div class="user-sub">
                <span class="user-code">{{ item.uniqueCode }}</span>
                <span v-if="item.phoneNumber" class="user-dot">·</span>
                <span v-if="item.phoneNumber" class="user-phone">{{ formatPhone(item.phoneNumber) }}</span>
              </div>
              <div class="user-badges">
                <v-chip
                  size="x-small"
                  :color="item.isOnline ? 'success' : 'default'"
                  variant="tonal"
                >
                  {{ item.isOnline ? 'متصل' : 'غير متصل' }}
                </v-chip>
                <v-chip v-if="item.isBanned" size="x-small" color="error" variant="tonal">محظور</v-chip>
                <v-chip v-if="item.isFeatured" size="x-small" color="warning" variant="tonal">مميز</v-chip>
              </div>
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
            {{ genderLabel[item.gender] || item.gender || '—' }}
          </v-chip>
        </template>

        <template #item.age="{ item }">
          <span class="text-body-2">{{ getAge(item.birthDate) != null ? getAge(item.birthDate) + ' سنة' : '—' }}</span>
        </template>

        <template #item.phoneNumber="{ item }">
          <span class="text-body-2 font-mono">{{ formatPhone(item.phoneNumber) }}</span>
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
          <div class="action-btns">
            <v-btn
              icon="mdi-lock-reset"
              size="small"
              variant="tonal"
              color="primary"
              title="تغيير كلمة المرور"
              @click="openPasswordDialog(item)"
            />
            <v-btn
              icon="mdi-crown"
              size="small"
              variant="tonal"
              :color="item.isFeatured ? 'warning' : undefined"
              :loading="featuredLoading === item.id"
              title="تمييز"
              @click="toggleFeatured(item)"
            />
            <v-btn
              v-if="!item.isFeatured && !item.isBanned"
              icon="mdi-account-cancel"
              size="small"
              variant="tonal"
              color="error"
              title="حظر"
              @click="confirmBan(item, true)"
            />
            <v-btn
              v-else-if="!item.isFeatured && item.isBanned"
              icon="mdi-account-check"
              size="small"
              variant="tonal"
              color="success"
              title="إلغاء الحظر"
              @click="confirmBan(item, false)"
            />
            <v-btn
              icon="mdi-delete"
              size="small"
              variant="tonal"
              color="error"
              title="حذف"
              @click="confirmDelete(item)"
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
          @update:model-value="fetchUsers"
        />
      </div>
    </v-card>

    <!-- Password Dialog -->
    <v-dialog v-model="passwordDialog" max-width="440" persistent>
      <v-card rounded="xl" elevation="0" class="pa-4">
        <v-card-title class="font-weight-bold pa-0 mb-1">
          تغيير كلمة المرور
        </v-card-title>
        <div class="text-body-2 text-medium-emphasis mb-4">
          للمستخدم <strong>{{ passwordUser?.name }}</strong>
          <span v-if="passwordUser?.uniqueCode"> · {{ passwordUser.uniqueCode }}</span>
        </div>

        <v-text-field
          v-model="newPassword"
          label="كلمة المرور الجديدة"
          :type="showPassword ? 'text' : 'password'"
          variant="outlined"
          rounded="lg"
          prepend-inner-icon="mdi-lock"
          :append-inner-icon="showPassword ? 'mdi-eye-off' : 'mdi-eye'"
          class="mb-3"
          hide-details="auto"
          @click:append-inner="showPassword = !showPassword"
        />
        <v-text-field
          v-model="confirmPassword"
          label="تأكيد كلمة المرور"
          :type="showPassword ? 'text' : 'password'"
          variant="outlined"
          rounded="lg"
          prepend-inner-icon="mdi-lock-check"
          class="mb-2"
          hide-details="auto"
        />

        <v-card-actions class="px-0 pt-4">
          <v-spacer />
          <v-btn variant="text" @click="closePasswordDialog">إلغاء</v-btn>
          <v-btn
            color="primary"
            variant="flat"
            :loading="passwordLoading"
            @click="executePasswordChange"
          >
            حفظ
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Delete Dialog -->
    <v-dialog v-model="deleteDialog" max-width="420" persistent>
      <v-card rounded="xl" elevation="0" class="pa-4">
        <v-card-title class="font-weight-bold text-error">
          حذف الحساب{{ deleteTarget === 'bulk' ? 'ات' : '' }}
        </v-card-title>
        <v-card-text>
          <template v-if="deleteTarget === 'bulk'">
            هل أنت متأكد من حذف {{ selectedIds.length }} حساب؟ لا يمكن التراجع.
          </template>
          <template v-else>
            هل أنت متأكد من حذف <strong>{{ deleteTarget?.name }}</strong> نهائياً؟ لا يمكن التراجع.
          </template>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn @click="cancelDelete" variant="text">إلغاء</v-btn>
          <v-btn color="error" variant="tonal" :loading="deleteLoading" @click="executeDelete">
            حذف
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Ban Dialog -->
    <v-dialog v-model="banDialog" max-width="400">
      <v-card rounded="xl" elevation="0" class="pa-4">
        <v-card-title class="font-weight-bold">
          {{ banAction ? 'حظر المستخدم' : 'رفع الحظر' }}
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

<style scoped>
.user-cell {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 6px 0;
  min-width: 200px;
}

.user-avatar {
  flex-shrink: 0;
  overflow: hidden;
}

.avatar-fallback {
  width: 100%;
  height: 100%;
  display: grid;
  place-items: center;
  background: rgba(46, 134, 251, 0.12);
  color: #2E86FB;
  font-weight: 700;
}

.user-meta {
  min-width: 0;
  flex: 1;
}

.user-name-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

.user-name {
  font-weight: 700;
  font-size: 0.95rem;
  color: #0B1220;
  line-height: 1.3;
  word-break: break-word;
}

.user-sub {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 2px;
  font-size: 0.78rem;
  color: #5B6577;
  font-weight: 600;
}

.user-code {
  color: #2E86FB;
}

.user-dot {
  opacity: 0.5;
}

.user-phone {
  font-family: ui-monospace, monospace;
  direction: ltr;
  unicode-bidi: isolate;
}

.user-badges {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 6px;
}

.users-table :deep(.v-data-table__td) {
  vertical-align: middle;
}
</style>
