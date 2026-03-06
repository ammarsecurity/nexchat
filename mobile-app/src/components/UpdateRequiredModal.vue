<script setup>
import { Download } from 'lucide-vue-next'
import { Capacitor } from '@capacitor/core'

const props = defineProps({
  downloadUrl: { type: String, required: true }
})

function openDownload() {
  if (!props.downloadUrl) return
  if (Capacitor.isNativePlatform()) {
    window.open(props.downloadUrl, '_system')
  } else {
    window.open(props.downloadUrl, '_blank')
  }
}
</script>

<template>
  <div class="update-overlay">
    <div class="update-modal glass-card">
      <div class="update-icon-wrap">
        <Download :size="40" stroke-width="2" />
      </div>
      <h2 class="update-title">تحديث مطلوب</h2>
      <p class="update-desc">يتوفر إصدار أحدث من التطبيق. يرجى التحديث للمتابعة.</p>
      <button
        class="update-btn"
        @click="openDownload"
      >
        <Download :size="20" stroke-width="2" />
        تحميل التحديث
      </button>
    </div>
  </div>
</template>

<style scoped>
.update-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.85);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
  padding: 24px;
  backdrop-filter: blur(8px);
}

.update-modal {
  width: 100%;
  max-width: 320px;
  padding: 28px 24px;
  text-align: center;
}

.update-icon-wrap {
  width: 72px;
  height: 72px;
  margin: 0 auto 20px;
  border-radius: 50%;
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.25) 0%, rgba(108, 99, 255, 0.1) 100%);
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary);
}

.update-title {
  font-size: 1.35rem;
  font-weight: 700;
  color: var(--text-primary);
  margin: 0 0 8px;
  font-family: 'Cairo', sans-serif;
}

.update-desc {
  font-size: 0.95rem;
  color: var(--text-secondary);
  margin: 0 0 24px;
  line-height: 1.5;
}

.update-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
  min-height: 48px;
  padding: 0 24px;
  background: linear-gradient(145deg, #7C75FF 0%, var(--primary) 50%, #5B54E8 100%);
  border: none;
  border-radius: 12px;
  color: white;
  font-size: 1rem;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: transform 0.15s, opacity 0.2s;
  box-shadow: 0 4px 16px rgba(108, 99, 255, 0.4);
}
.update-btn:active {
  transform: scale(0.98);
  opacity: 0.95;
}
</style>
