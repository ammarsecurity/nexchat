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
]

onMounted(async () => {
  const [statsRes, chartRes] = await Promise.allSettled([
    api.get('/admin/stats'),
    api.get('/admin/stats/chart')
  ])

  if (statsRes.status === 'fulfilled') {
    stats.value = statsRes.value.data
  } else {
    stats.value = { totalUsers: 0, onlineUsers: 0, activeSessions: 0, totalSessionsToday: 0, totalMessagesToday: 0, pendingReports: 0 }
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
        }
      ]
    }
  }
  chartLoading.value = false
})
</script>

<template>
  <div>
    <div class="mb-6">
      <div class="text-h5 font-weight-bold">مرحباً بك 👋</div>
      <div class="text-body-2 text-medium-emphasis">هنا ملخص نشاط NexChat اليوم</div>
    </div>

    <!-- Stats Grid -->
    <v-row class="mb-6">
      <v-col
        v-for="card in statCards"
        :key="card.key"
        cols="12" sm="6" md="4"
      >
        <v-card class="stat-card pa-5" rounded="xl" elevation="0">
          <div class="d-flex align-center justify-space-between mb-4">
            <div>
              <div class="text-body-2 text-medium-emphasis mb-1">{{ card.label }}</div>
              <div class="text-h4 font-weight-black">
                <v-skeleton-loader v-if="loading" type="text" width="80px" />
                <template v-else>{{ stats?.[card.key]?.toLocaleString() ?? '-' }}</template>
              </div>
            </div>
            <div
              class="icon-bubble"
              :style="{ background: `${card.color}20`, color: card.color }"
            >
              <v-icon :icon="card.icon" size="28" />
            </div>
          </div>
          <div class="trend-bar" :style="{ background: card.color }"></div>
        </v-card>
      </v-col>
    </v-row>

    <!-- Chart -->
    <v-card class="pa-6" rounded="xl" elevation="0">
      <div class="d-flex align-center justify-space-between mb-4">
        <div>
          <div class="text-h6 font-weight-bold">نشاط الأسبوع</div>
          <div class="text-body-2 text-medium-emphasis">الجلسات والمستخدمين الجدد</div>
        </div>
        <v-chip color="primary" variant="tonal" size="small">آخر 7 أيام</v-chip>
      </div>
      <div style="height: 280px">
        <div v-if="chartLoading" class="d-flex align-center justify-center fill-height" style="height:280px">
          <v-progress-circular indeterminate color="primary" />
        </div>
        <Line v-else :data="chartData" :options="chartOptions" />
      </div>
    </v-card>
  </div>
</template>

<style scoped>
.stat-card {
  background: rgba(255,255,255,0.04) !important;
  border: 1px solid rgba(255,255,255,0.08) !important;
  position: relative;
  overflow: hidden;
}

.icon-bubble {
  align-items: center;
  border-radius: 14px;
  display: flex;
  height: 56px;
  justify-content: center;
  width: 56px;
}

.trend-bar {
  height: 3px;
  border-radius: 3px;
  opacity: 0.6;
  width: 100%;
}
</style>
