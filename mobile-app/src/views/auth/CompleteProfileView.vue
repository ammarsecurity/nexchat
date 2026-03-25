<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { Globe, Phone, AlertCircle, ChevronRight } from 'lucide-vue-next'
import { useAuthStore } from '../../stores/auth'
import { useI18n } from 'vue-i18n'
import { useThemeStore } from '../../stores/theme'
import { publicUrl } from '../../utils/publicUrl'
import LoaderOverlay from '../../components/LoaderOverlay.vue'
import { countries } from '../../data/countries'
import api from '../../services/api'
import { validatePhone, getPhoneErrorMessage } from '../../utils/phoneValidation'

const router = useRouter()
const auth = useAuthStore()
const theme = useThemeStore()
const { t } = useI18n()
const logoImg = computed(() => publicUrl(theme.isLight ? 'logo-light.png' : 'logo.png'))

const selectedCountry = ref(null)
const phoneNumber = ref('')
const loading = ref(false)
const error = ref('')

onMounted(async () => {
  try {
    const res = await api.get('/user/me')
    const c = res.data?.country
    const p = res.data?.phoneNumber
    if (c) selectedCountry.value = c
    if (p) {
      const country = countries.find(x => x.code === c)
      const dial = country?.dialCode ?? ''
      phoneNumber.value = p.startsWith(dial) ? p.slice(dial.length) : p
    }
  } catch {}
})

const countryCode = computed(() => {
  const c = countries.find(x => x.code === selectedCountry.value)
  return c?.dialCode ?? ''
})

const phoneValidationResult = computed(() => {
  if (!countryCode.value || !phoneNumber.value.trim()) return null
  return validatePhone(countryCode.value, phoneNumber.value, t)
})

const phoneError = computed(() => {
  const r = phoneValidationResult.value
  if (!r || r.valid) return ''
  return getPhoneErrorMessage(r, t)
})

const canSubmit = computed(() => {
  if (!selectedCountry.value || !phoneNumber.value.trim()) return false
  const result = phoneValidationResult.value
  return result?.valid ?? false
})

async function handleSubmit() {
  const result = phoneValidationResult.value
  if (!result?.valid) {
    error.value = phoneError.value || t('phoneValidation.required')
    return
  }
  loading.value = true
  error.value = ''
  try {
    await api.put('/user/profile-contact', {
      country: selectedCountry.value,
      countryCode: countryCode.value,
      phoneNumber: result.normalized
    })
    auth.setNeedsProfileContact(false)
    router.replace('/home')
  } catch (e) {
    error.value = e.response?.data?.message ?? t('common.error')
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="complete-profile page auth-pattern">
    <LoaderOverlay :show="loading" :text="t('completeProfile.saving')" />
    <div class="page-inner">
      <header class="top-bar">
        <button class="back-btn" @click="router.back()" :aria-label="t('common.cancel')">
          <ChevronRight :size="22" />
        </button>
        <span class="top-title">{{ t('completeProfile.title') }}</span>
        <div class="top-bar-spacer"></div>
      </header>
      <div class="content">
        <img :src="logoImg" alt="NexChat" class="logo-img" />

        <div class="card glass-card">
          <p class="subtitle text-secondary">{{ t('completeProfile.subtitle') }}</p>

        <form @submit.prevent="handleSubmit" class="form">
          <!-- Country -->
          <div class="field">
            <label class="field-label">
              <Globe :size="16" class="label-icon" />
              {{ t('completeProfile.country') }}
            </label>
            <select
              v-model="selectedCountry"
              class="input-field select-field"
              :aria-label="t('completeProfile.country')"
              required
            >
              <option value="" disabled>{{ t('completeProfile.selectCountry') }}</option>
              <option v-for="c in countries" :key="c.code" :value="c.code">
                {{ c.name }} ({{ c.dialCode }})
              </option>
            </select>
          </div>

          <!-- Phone -->
          <div class="field">
            <label class="field-label">
              <Phone :size="16" class="label-icon" />
              {{ t('completeProfile.phone') }}
            </label>
            <div class="phone-input-wrap" :class="{ 'input-error': phoneError }">
              <span class="dial-prefix">+{{ countryCode || '...' }}</span>
              <input
                v-model="phoneNumber"
                type="tel"
                class="input-field phone-input"
                :placeholder="t('completeProfile.phonePlaceholder')"
                inputmode="numeric"
                maxlength="15"
                autocomplete="tel"
              />
            </div>
            <span v-if="phoneError" class="field-error">{{ phoneError }}</span>
            <span v-else class="field-hint">{{ t('completeProfile.phoneHint') }}</span>
          </div>

          <div v-if="error" class="error-toast">
            <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
            <span>{{ error }}</span>
          </div>

          <button
            type="submit"
            class="btn-gradient"
            :disabled="loading || !canSubmit"
          >
            <span v-if="!loading">{{ t('completeProfile.submit') }}</span>
            <span v-else class="spinner"></span>
          </button>
        </form>
      </div>
    </div>
    </div>
  </div>
</template>

<style scoped>
.complete-profile {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  min-height: 100%;
  overflow-y: auto;
  position: relative;
}

.page-inner {
  width: 100%;
  max-width: var(--app-max-width);
  width: 100%;
  margin: 0 auto;
  padding: 0 var(--spacing);
  padding-bottom: calc(24px + var(--safe-bottom));
  display: flex;
  flex-direction: column;
  align-items: center;
}

.top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  padding: calc(var(--safe-top) + 8px) 0 16px;
  flex-shrink: 0;
  gap: 12px;
}

.back-btn {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  height: 44px;
  justify-content: center;
  min-width: 44px;
  flex-shrink: 0;
}
.back-btn:active { background: var(--bg-card-hover); }

.top-title {
  font-size: 17px;
  font-weight: 600;
  flex: 1;
  text-align: center;
  min-width: 0;
}

.top-bar-spacer {
  width: 44px;
  flex-shrink: 0;
}

.content {
  display: flex;
  flex-direction: column;
  gap: 24px;
  width: 100%;
  position: relative;
  z-index: 10;
}

.logo-img {
  height: 56px;
  width: auto;
  object-fit: contain;
  margin-bottom: 4px;
}

.card { padding: 24px 20px; width: 100%; }
.subtitle { font-size: 14px; margin-bottom: 20px; }

.form { display: flex; flex-direction: column; gap: 16px; }
.field { display: flex; flex-direction: column; gap: 8px; }
label { color: var(--text-secondary); font-size: 13px; font-weight: 500; }
.field-label { display: flex; align-items: center; gap: 6px; }
.label-icon { color: var(--primary); flex-shrink: 0; }
.field-hint { font-size: 12px; color: var(--text-muted); margin-top: 2px; }
.field-error { font-size: 12px; color: #f44336; margin-top: 4px; display: block; }
.phone-input-wrap.input-error { border-color: #f44336 !important; box-shadow: 0 0 0 1px rgba(244,67,54,0.3); }

.select-field {
  appearance: none;
  -webkit-appearance: none;
  cursor: pointer;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 24 24' fill='none' stroke='%23A0A0B8' stroke-width='2'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: left 14px center;
  padding-left: 44px;
}

.phone-input-wrap {
  display: flex;
  align-items: stretch;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--bg-elevated);
  overflow: hidden;
}

.dial-prefix {
  display: flex;
  align-items: center;
  padding: 0 14px;
  background: rgba(108, 99, 255, 0.1);
  color: var(--primary);
  font-size: 15px;
  font-weight: 600;
  min-width: 60px;
  flex-shrink: 0;
}

.phone-input {
  border: none !important;
  border-radius: 0 !important;
  flex: 1;
  min-width: 0;
}

.btn-gradient:disabled {
  opacity: 0.5;
  cursor: not-allowed;
  pointer-events: none;
}

.spinner {
  display: inline-block; width: 18px; height: 18px;
  border: 2px solid rgba(255,255,255,0.3);
  border-top-color: white;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
