<script setup>
import { ShieldCheck } from 'lucide-vue-next'

defineProps({
  compact: { type: Boolean, default: false }
})
</script>

<template>
  <div class="privacy-badge" :class="{ compact }">
    <div class="privacy-badge-icon">
      <ShieldCheck :size="compact ? 18 : 22" stroke-width="2" />
    </div>
    <div class="privacy-badge-content">
      <span class="privacy-badge-title">دردشة مشفرة</span>
      <span class="privacy-badge-desc">لا تُحفظ على أي سيرفر</span>
    </div>
  </div>
</template>

<style scoped>
.privacy-badge {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: var(--spacing);
  background: linear-gradient(135deg, rgba(34, 197, 94, 0.12) 0%, rgba(34, 197, 94, 0.06) 100%);
  border: 1px solid rgba(34, 197, 94, 0.25);
  border-radius: var(--radius);
  width: 100%;
  box-shadow: 0 0 20px rgba(34, 197, 94, 0.08);
}

.privacy-badge.compact {
  padding: 8px 12px;
  gap: 8px;
  max-width: none;
  width: 100%;
}

.privacy-badge-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  border-radius: 10px;
  background: rgba(34, 197, 94, 0.2);
  color: var(--success);
  flex-shrink: 0;
}

.privacy-badge.compact .privacy-badge-icon {
  width: 32px;
  height: 32px;
}

.privacy-badge-content {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.privacy-badge-title {
  font-size: 15px;
  font-weight: 700;
  color: var(--success);
  font-family: 'Cairo', sans-serif;
}

.privacy-badge-desc {
  font-size: 13px;
  color: var(--text-secondary);
  font-weight: 500;
}

.privacy-badge.compact .privacy-badge-content {
  flex-direction: row;
  align-items: center;
  gap: 6px;
}

.privacy-badge.compact .privacy-badge-title {
  font-size: 13px;
}

.privacy-badge.compact .privacy-badge-desc {
  font-size: 12px;
}
</style>
