<script setup>
import { ref, reactive, watch } from 'vue'
import api from '../services/api'

const messages = ref([])
const total = ref(0)
const loading = ref(false)

const filters = reactive({
  search: '',
  type: '',
  sessionId: '',
  userId: '',
  dateFrom: '',
  dateTo: '',
  page: 1,
  pageSize: 30,
})

const typeOptions = [
  { title: 'الكل', value: '' },
  { title: 'نصي', value: 'text' },
  { title: 'صورة', value: 'image' },
  { title: 'نظام', value: 'system' },
]

const totalPages = ref(1)

async function fetchMessages() {
  loading.value = true
  try {
    const params = {}
    if (filters.search)    params.search    = filters.search
    if (filters.type)      params.type      = filters.type
    if (filters.sessionId) params.sessionId = filters.sessionId
    if (filters.userId)    params.userId    = filters.userId
    if (filters.dateFrom)  params.dateFrom  = filters.dateFrom
    if (filters.dateTo)    params.dateTo    = filters.dateTo
    params.page     = filters.page
    params.pageSize = filters.pageSize

    const res = await api.get('/admin/messages', { params })
    messages.value = res.data.items
    total.value = res.data.total
    totalPages.value = Math.ceil(res.data.total / filters.pageSize) || 1
  } catch (e) {
    messages.value = []
    total.value = 0
  } finally {
    loading.value = false
  }
}

function applyFilters() {
  filters.page = 1
  fetchMessages()
}

function resetFilters() {
  filters.search = ''
  filters.type = ''
  filters.sessionId = ''
  filters.userId = ''
  filters.dateFrom = ''
  filters.dateTo = ''
  filters.page = 1
  fetchMessages()
}

watch(() => filters.page, fetchMessages)

fetchMessages()

function typeColor(type) {
  if (type === 'image') return 'cyan'
  if (type === 'system') return 'warning'
  return 'primary'
}

function typeLabel(type) {
  if (type === 'image') return 'صورة'
  if (type === 'system') return 'نظام'
  return 'نص'
}

function formatTime(dt) {
  return new Date(dt).toLocaleString('ar-SA', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit'
  })
}

const showFilters = ref(true)
</script>

<template>
  <div>
    <!-- Header -->
    <div class="d-flex align-center justify-space-between mb-6">
      <div>
        <div class="text-h5 font-weight-bold">الرسائل</div>
        <div class="text-body-2 text-medium-emphasis">
          إجمالي {{ total.toLocaleString() }} رسالة
        </div>
      </div>
      <v-btn
        :prepend-icon="showFilters ? 'mdi-filter-off' : 'mdi-filter'"
        variant="tonal"
        color="primary"
        rounded="lg"
        @click="showFilters = !showFilters"
      >
        {{ showFilters ? 'إخفاء الفلاتر' : 'إظهار الفلاتر' }}
      </v-btn>
    </div>

    <!-- Filter Panel -->
    <v-expand-transition>
      <v-card v-if="showFilters" class="filter-card pa-5 mb-5" rounded="xl" elevation="0">
        <v-row dense>
          <!-- Search -->
          <v-col cols="12" md="4">
            <v-text-field
              v-model="filters.search"
              label="بحث في المحتوى"
              prepend-inner-icon="mdi-magnify"
              variant="outlined"
              density="compact"
              rounded="lg"
              hide-details
              clearable
              @keyup.enter="applyFilters"
            />
          </v-col>

          <!-- Type -->
          <v-col cols="6" md="2">
            <v-select
              v-model="filters.type"
              :items="typeOptions"
              item-title="title"
              item-value="value"
              label="نوع الرسالة"
              variant="outlined"
              density="compact"
              rounded="lg"
              hide-details
            />
          </v-col>

          <!-- Session ID -->
          <v-col cols="6" md="3">
            <v-text-field
              v-model="filters.sessionId"
              label="معرّف الجلسة"
              prepend-inner-icon="mdi-chat"
              variant="outlined"
              density="compact"
              rounded="lg"
              hide-details
              clearable
            />
          </v-col>

          <!-- User ID -->
          <v-col cols="6" md="3">
            <v-text-field
              v-model="filters.userId"
              label="معرّف المستخدم"
              prepend-inner-icon="mdi-account"
              variant="outlined"
              density="compact"
              rounded="lg"
              hide-details
              clearable
            />
          </v-col>

          <!-- Date From -->
          <v-col cols="6" md="3">
            <v-text-field
              v-model="filters.dateFrom"
              label="من تاريخ"
              type="date"
              prepend-inner-icon="mdi-calendar-start"
              variant="outlined"
              density="compact"
              rounded="lg"
              hide-details
            />
          </v-col>

          <!-- Date To -->
          <v-col cols="6" md="3">
            <v-text-field
              v-model="filters.dateTo"
              label="إلى تاريخ"
              type="date"
              prepend-inner-icon="mdi-calendar-end"
              variant="outlined"
              density="compact"
              rounded="lg"
              hide-details
            />
          </v-col>

          <!-- Page Size -->
          <v-col cols="6" md="2">
            <v-select
              v-model="filters.pageSize"
              :items="[10, 20, 30, 50, 100]"
              label="لكل صفحة"
              variant="outlined"
              density="compact"
              rounded="lg"
              hide-details
            />
          </v-col>

          <!-- Buttons -->
          <v-col cols="12" md="4" class="d-flex gap-2 align-end">
            <v-btn
              color="primary"
              variant="flat"
              rounded="lg"
              prepend-icon="mdi-magnify"
              @click="applyFilters"
              :loading="loading"
            >
              بحث
            </v-btn>
            <v-btn
              variant="tonal"
              rounded="lg"
              prepend-icon="mdi-refresh"
              @click="resetFilters"
            >
              إعادة تعيين
            </v-btn>
          </v-col>
        </v-row>
      </v-card>
    </v-expand-transition>

    <!-- Messages Table -->
    <v-card class="messages-card" rounded="xl" elevation="0">
      <v-data-table-virtual
        v-if="false"
      />

      <!-- Custom table for RTL + styling -->
      <div v-if="loading" class="d-flex align-center justify-center pa-10">
        <v-progress-circular indeterminate color="primary" size="40" />
      </div>

      <div v-else-if="messages.length === 0" class="empty-state pa-10 text-center">
        <v-icon size="64" color="medium-emphasis" class="mb-3">mdi-message-off-outline</v-icon>
        <div class="text-h6 font-weight-bold text-medium-emphasis">لا توجد رسائل</div>
        <div class="text-body-2 text-medium-emphasis mt-1">جرّب تغيير الفلاتر</div>
      </div>

      <div v-else>
        <!-- Table Header -->
        <div class="msg-header px-5 py-3">
          <div class="msg-col col-user">المرسل</div>
          <div class="msg-col col-content">المحتوى</div>
          <div class="msg-col col-type">النوع</div>
          <div class="msg-col col-session">الجلسة</div>
          <div class="msg-col col-time">الوقت</div>
        </div>

        <v-divider style="border-color: rgba(255,255,255,0.06)" />

        <!-- Table Rows -->
        <div
          v-for="(msg, i) in messages"
          :key="msg.id"
          class="msg-row px-5 py-3"
          :class="{ 'row-alt': i % 2 === 1 }"
        >
          <!-- Sender -->
          <div class="msg-col col-user">
            <div class="d-flex align-center gap-2">
              <div class="mini-avatar">{{ msg.senderName?.[0]?.toUpperCase() }}</div>
              <span class="text-body-2 font-weight-medium">{{ msg.senderName }}</span>
            </div>
          </div>

          <!-- Content -->
          <div class="msg-col col-content">
            <template v-if="msg.type === 'image'">
              <a :href="msg.content" target="_blank" class="image-link">
                <v-icon size="16" class="me-1">mdi-image</v-icon>
                عرض الصورة
              </a>
            </template>
            <span v-else class="text-body-2 msg-content-text">{{ msg.content }}</span>
          </div>

          <!-- Type -->
          <div class="msg-col col-type">
            <v-chip
              :color="typeColor(msg.type)"
              variant="tonal"
              size="x-small"
              label
            >
              {{ typeLabel(msg.type) }}
            </v-chip>
          </div>

          <!-- Session -->
          <div class="msg-col col-session">
            <code class="session-code">{{ msg.sessionId?.slice(0, 8) }}…</code>
          </div>

          <!-- Time -->
          <div class="msg-col col-time">
            <span class="text-caption text-medium-emphasis">{{ formatTime(msg.sentAt) }}</span>
          </div>
        </div>
      </div>

      <!-- Pagination -->
      <v-divider v-if="messages.length > 0" style="border-color: rgba(255,255,255,0.06)" />
      <div v-if="messages.length > 0" class="d-flex align-center justify-space-between px-5 py-3">
        <div class="text-caption text-medium-emphasis">
          صفحة {{ filters.page }} من {{ totalPages }} — {{ total.toLocaleString() }} رسالة
        </div>
        <v-pagination
          v-model="filters.page"
          :length="totalPages"
          :total-visible="5"
          density="compact"
          active-color="primary"
          rounded="lg"
        />
      </div>
    </v-card>
  </div>
</template>

<style scoped>
.filter-card {
  background: rgba(255,255,255,0.04) !important;
  border: 1px solid rgba(255,255,255,0.08) !important;
}

.messages-card {
  background: rgba(255,255,255,0.03) !important;
  border: 1px solid rgba(255,255,255,0.08) !important;
  overflow: hidden;
}

.msg-header {
  display: flex;
  align-items: center;
  background: rgba(255,255,255,0.03);
  font-size: 12px;
  font-weight: 600;
  color: rgba(255,255,255,0.5);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  direction: rtl;
}

.msg-row {
  display: flex;
  align-items: center;
  direction: rtl;
  transition: background 0.15s;
}
.msg-row:hover { background: rgba(108,99,255,0.06); }
.row-alt { background: rgba(255,255,255,0.015); }
.row-alt:hover { background: rgba(108,99,255,0.06); }

.msg-col { padding: 0 8px; }
.col-user    { width: 160px; flex-shrink: 0; }
.col-content { flex: 1; min-width: 0; }
.col-type    { width: 80px; flex-shrink: 0; text-align: center; }
.col-session { width: 130px; flex-shrink: 0; }
.col-time    { width: 160px; flex-shrink: 0; text-align: left; }

.msg-content-text {
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  word-break: break-word;
}

.mini-avatar {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: linear-gradient(135deg, #6C63FF, #FF6584);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: 700;
  color: white;
  flex-shrink: 0;
}

.session-code {
  font-size: 11px;
  background: rgba(255,255,255,0.07);
  padding: 2px 6px;
  border-radius: 4px;
  color: #00D4FF;
  font-family: monospace;
}

.image-link {
  color: #00D4FF;
  text-decoration: none;
  font-size: 13px;
  display: flex;
  align-items: center;
}
.image-link:hover { text-decoration: underline; }

.empty-state { color: rgba(255,255,255,0.3); }

.gap-2 { gap: 8px; }
</style>
