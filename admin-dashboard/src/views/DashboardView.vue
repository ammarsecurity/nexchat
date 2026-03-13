<script setup>
import { ref, onMounted } from 'vue'
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS, CategoryScale, LinearScale,
  PointElement, LineElement, Title, Tooltip, Legend, Filler
} from 'chart.js'
import api from '../services/api'

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, Filler)

const stats = ref(null)
const loading = ref(true)
const chartLoading = ref(true)

const chartData = ref({
  labels: [],
  datasets: [
    {
      label: 'جلسات',
      data: [],
      borderColor: '#6C63FF',
      backgroundColor: 'rgba(108,99,255,0.1)',
      fill: true,
      tension: 0.4,
    },
    {
      label: 'مستخدمين جدد',
      data: [],
      borderColor: '#FF6584',
      backgroundColor: 'rgba(255,101,132,0.1)',
      fill: true,
      tension: 0.4,
    }
  ]
})

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: {
      labels: { color: '#B0B0C3', font: { size: 12 } }
    }
  },
  scales: {
    x: {
      ticks: { color: '#B0B0C3' },
      grid: { color: 'rgba(255,255,255,0.05)' }
    },
    y: {
      ticks: { color: '#B0B0C3' },
      grid: { color: 'rgba(255,255,255,0.05)' }
    }
  }
}

const statCards = [
  { key: 'totalUsers', label: 'إجمالي المستخدمين', icon: 'mdi-account-group', color: '#6C63FF', suffix: '' },
  { key: 'onlineUsers', label: 'متصل الآن', icon: 'mdi-circle', color: '#4ade80', suffix: '' },
  { key: 'activeSessions', label: 'جلسات نشطة', icon: 'mdi-chat-processing', color: '#00D4FF', suffix: '' },
  { key: 'totalSessionsToday', label: 'جلسات اليوم', icon: 'mdi-calendar-today', color: '#FF6584', suffix: '' },
  { key: 'totalMessagesToday', label: 'رسائل اليوم', icon: 'mdi-message', color: '#FFB74D', suffix: '' },
  { key: 'pendingReports', label: 'بلاغات معلقة', icon: 'mdi-flag', color: '#FF5252', suffix: '' },
  { key: 'totalConversations', label: 'المحادثات', icon: 'mdi-forum', color: '#9C27B0', suffix: '' },
  { key: 'totalConversationMessagesToday', label: 'رسائل المحادثات اليوم', icon: 'mdi-message-reply-text', color: '#E040FB', suffix: '' },
  { key: 'totalContacts', label: 'جهات الاتصال', icon: 'mdi-account-multiple', color: '#00BCD4', suffix: '' },
  { key: 'totalBlocks', label: 'المحظورون', icon: 'mdi-block-helper', color: '#FF5722', suffix: '' },
]

onMounted(async () => {
  const [statsRes, chartRes] = await Promise.allSettled([
    api.get('/admin/stats'),
    api.get('/admin/stats/chart')
  ])

  if (statsRes.status === 'fulfilled') {
    stats.value = statsRes.value.data
  } else {
    stats.value = {
      totalUsers: 0, onlineUsers: 0, activeSessions: 0, totalSessionsToday: 0,
      totalMessagesToday: 0, pendingReports: 0, totalConversations: 0,
      totalConversationMessagesToday: 0, totalContacts: 0, totalBlocks: 0
    }
  }
  loading.value = false

  if (chartRes.status === 'fulfilled') {
    const points = chartRes.value.data
    chartData.value = {
      labels: points.map(p => p.date),
      datasets: [
        {
          label: 'جلسات',
          data: points.map(p => p.sessions),
          borderColor: '#6C63FF',
          backgroundColor: 'rgba(108,99,255,0.1)',
          fill: true,
          tension: 0.4,
        },
        {
          label: 'مستخدمين جدد',
          data: points.map(p => p.newUsers),
          borderColor: '#FF6584',
          backgroundColor: 'rgba(255,101,132,0.1)',
          fill: true,
          tension: 0.4,
        },
        {
          label: 'محادثات',
          data: points.map(p => p.conversations ?? 0),
          borderColor: '#9C27B0',
          backgroundColor: 'rgba(156,39,176,0.1)',
          fill: true,
          tension: 0.4,
        },
        {
          label: 'جهات اتصال جديدة',
          data: points.map(p => p.newContacts ?? 0),
          borderColor: '#00BCD4',
          backgroundColor: 'rgba(0,188,212,0.1)',
          fill: true,
          tension: 0.4,
        }
      ]
    }
  }
  chartLoading.value = false
})
</script>

<template>
  <div class="dashboard-view">
    <div class="mb-4 mb-sm-6">
      <div class="text-h5 font-weight-bold dashboard-title">مرحباً بك 👋</div>
      <div class="text-body-2 text-medium-emphasis">هنا ملخص نشاط NexChat اليوم</div>
    </div>

    <!-- Stats Grid -->
    <v-row class="mb-4 mb-sm-6" dense>
      <v-col
        v-for="card in statCards"
        :key="card.key"
        cols="6"
        sm="6"
        md="4"
        class="pa-2 pa-sm-3"
      >
        <v-card class="stat-card pa-3 pa-sm-5" rounded="xl" elevation="0">
          <div class="d-flex align-center justify-space-between mb-2 mb-sm-4">
            <div class="flex-grow-1 min-width-0">
              <div class="text-body-2 text-medium-emphasis mb-1 stat-label">{{ card.label }}</div>
              <div class="text-h5 font-weight-black stat-value">
                <v-skeleton-loader v-if="loading" type="text" width="60px" class="d-inline-block" />
                <template v-else>{{ stats?.[card.key]?.toLocaleString() ?? '-' }}</template>
              </div>
            </div>
            <div
              class="icon-bubble flex-shrink-0"
              :style="{ background: `${card.color}20`, color: card.color }"
            >
              <v-icon :icon="card.icon" size="24" class="stat-icon" />
            </div>
          </div>
          <div class="trend-bar" :style="{ background: card.color }"></div>
        </v-card>
      </v-col>
    </v-row>

    <!-- Chart -->
    <v-card class="pa-4 pa-sm-6 chart-card" rounded="xl" elevation="0">
      <div class="d-flex flex-column flex-sm-row align-start align-sm-center justify-space-between mb-4 gap-2">
        <div>
          <div class="text-h6 font-weight-bold">نشاط الأسبوع</div>
          <div class="text-body-2 text-medium-emphasis">الجلسات والمستخدمين الجدد والمحادثات وجهات الاتصال</div>
        </div>
        <v-chip color="primary" variant="tonal" size="small" class="align-self-start align-self-sm-center">آخر 7 أيام</v-chip>
      </div>
      <div class="chart-container">
        <div v-if="chartLoading" class="d-flex align-center justify-center chart-loading">
          <v-progress-circular indeterminate color="primary" />
        </div>
        <Line v-else :data="chartData" :options="chartOptions" />
      </div>
    </v-card>
  </div>
</template>

<style scoped>
.dashboard-view {
  width: 100%;
  overflow-x: hidden;
}

.stat-card {
  background: rgba(255,255,255,0.04) !important;
  border: 1px solid rgba(255,255,255,0.08) !important;
  position: relative;
  overflow: hidden;
}

.icon-bubble {
  align-items: center;
  border-radius: 12px;
  display: flex;
  height: 44px;
  justify-content: center;
  width: 44px;
}

.trend-bar {
  height: 3px;
  border-radius: 3px;
  opacity: 0.6;
  width: 100%;
}

.chart-container {
  height: 220px;
  min-height: 180px;
}

.chart-loading {
  height: 220px;
  min-height: 180px;
}

@media (min-width: 600px) {
  .icon-bubble {
    height: 56px;
    width: 56px;
    border-radius: 14px;
  }

  .stat-icon {
    font-size: 28px !important;
  }

  .chart-container,
  .chart-loading {
    height: 280px;
  }
}
</style>
