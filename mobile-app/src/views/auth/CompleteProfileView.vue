<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { Globe, Phone, AlertCircle, ChevronLeft, ChevronRight, UserRound } from 'lucide-vue-next'
import { useAuthStore } from '../../stores/auth'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../../stores/locale'
import { useThemeStore } from '../../stores/theme'
import { publicUrl } from '../../utils/publicUrl'
import LoaderOverlay from '../../components/LoaderOverlay.vue'
import { countries } from '../../data/countries'
import api from '../../services/api'
import { validatePhone, getPhoneErrorMessage } from '../../utils/phoneValidation'
import { navigateDefaultForSession } from '../../utils/appRouting'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()
const theme = useThemeStore()
const localeStore = useLocaleStore()
const { t } = useI18n()
const logoImg = computed(() => publicUrl(theme.isLight ? 'logo-light.png' : 'logo.png'))
const BackIcon = computed(() => (localeStore.isRtl ? ChevronRight : ChevronLeft))
const showBackButton = computed(() => route.query.from === 'settings')

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

function goBack() {
  router.push('/settings')
}

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
    if (showBackButton.value) {
      router.replace('/settings')
      return
    }
    await navigateDefaultForSession(router, true)
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

    <div class="cp-scroll">
      <div class="cp-content">
        <header v-if="showBackButton" class="cp-nav">
          <button type="button" class="cp-back" :aria-label="t('common.back')" @click="goBack">
            <component :is="BackIcon" :size="22" stroke-width="2" />
          </button>
          <h1 class="cp-nav-title">{{ t('completeProfile.title') }}</h1>
          <div class="cp-nav-spacer" aria-hidden="true" />
        </header>

        <div class="cp-hero">
          <img :src="logoImg" alt="NexChat" class="cp-logo" />
          <div class="cp-hero-icon" aria-hidden="true">
            <UserRound :size="28" stroke-width="2" />
          </div>
          <h1 v-if="!showBackButton" class="cp-title">{{ t('completeProfile.title') }}</h1>
          <p class="cp-subtitle">{{ t('completeProfile.subtitle') }}</p>
        </div>

        <div class="cp-card glass-card">
          <form class="cp-form" @submit.prevent="handleSubmit">
            <div class="cp-field">
              <label class="cp-label" for="cp-country">
                <Globe :size="16" stroke-width="2" class="cp-label-icon" />
                {{ t('completeProfile.country') }}
              </label>
              <div class="cp-select-wrap">
                <select
                  id="cp-country"
                  v-model="selectedCountry"
                  class="cp-select"
                  :aria-label="t('completeProfile.country')"
                  required
                >
                  <option value="" disabled>{{ t('completeProfile.selectCountry') }}</option>
                  <option v-for="c in countries" :key="c.code" :value="c.code">
                    {{ c.name }} ({{ c.dialCode }})
                  </option>
                </select>
              </div>
            </div>

            <div class="cp-field">
              <label class="cp-label" for="cp-phone">
                <Phone :size="16" stroke-width="2" class="cp-label-icon" />
                {{ t('completeProfile.phone') }}
              </label>
              <div class="cp-phone-wrap" :class="{ 'cp-phone-wrap--error': phoneError }">
                <span class="cp-dial">+{{ countryCode || '…' }}</span>
                <input
                  id="cp-phone"
                  v-model="phoneNumber"
                  type="tel"
                  class="cp-phone-input"
                  :placeholder="t('completeProfile.phonePlaceholder')"
                  inputmode="numeric"
                  maxlength="15"
                  autocomplete="tel-national"
                />
              </div>
              <p v-if="phoneError" class="cp-hint cp-hint--error">{{ phoneError }}</p>
              <p v-else class="cp-hint">{{ t('completeProfile.phoneHint') }}</p>
            </div>

            <div v-if="error" class="error-toast">
              <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
              <span>{{ error }}</span>
            </div>

            <button type="submit" class="cp-submit" :disabled="loading || !canSubmit">
              <span v-if="!loading">{{ t('completeProfile.submit') }}</span>
              <span v-else class="spinner" />
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
  overflow: hidden;
}

.cp-scroll {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  -webkit-overflow-scrolling: touch;
  padding:
    calc(var(--safe-top) + 8px)
    max(var(--spacing), env(safe-area-inset-right, 0px))
    calc(28px + var(--safe-bottom))
    max(var(--spacing), env(safe-area-inset-left, 0px));
}

.cp-content {
  width: 100%;
  max-width: 400px;
  margin: 0 auto;
}

.cp-nav {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 8px;
}

.cp-back {
  width: 44px;
  height: 44px;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--border);
  border-radius: 14px;
  background: var(--bg-card);
  color: var(--text-primary);
  box-shadow: var(--shadow-sm);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.cp-back:active {
  transform: scale(0.97);
  background: var(--bg-card-hover);
}

.cp-nav-title {
  flex: 1;
  margin: 0;
  font-size: 17px;
  font-weight: 700;
  text-align: center;
  color: var(--text-primary);
}

.cp-nav-spacer {
  width: 44px;
  flex-shrink: 0;
}

.cp-hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  margin-bottom: 22px;
}

.cp-logo {
  height: 48px;
  width: auto;
  object-fit: contain;
  margin-bottom: 14px;
}

.cp-hero-icon {
  width: 56px;
  height: 56px;
  border-radius: 18px;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 14px;
  background: var(--primary-soft);
  color: var(--primary);
  border: 1px solid var(--primary-muted);
}

.cp-title {
  margin: 0 0 8px;
  font-size: 24px;
  font-weight: 800;
  color: var(--text-primary);
  line-height: 1.25;
}

.cp-subtitle {
  margin: 0;
  max-width: 300px;
  font-size: 15px;
  line-height: 1.55;
  color: var(--text-secondary);
}

.cp-card {
  padding: 22px 18px;
  border-radius: var(--radius-lg);
}

.cp-form {
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.cp-field {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.cp-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  font-weight: 600;
  color: var(--text-secondary);
}

.cp-label-icon {
  color: var(--primary);
  flex-shrink: 0;
}

.cp-select-wrap {
  position: relative;
}

.cp-select {
  width: 100%;
  min-height: 50px;
  padding: 0 44px 0 14px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--bg-elevated);
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  font-size: 15px;
  appearance: none;
  -webkit-appearance: none;
  cursor: pointer;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.cp-select:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px var(--primary-soft);
}

.cp-select-wrap::after {
  content: '';
  position: absolute;
  left: 14px;
  top: 50%;
  width: 10px;
  height: 10px;
  border-right: 2px solid var(--text-muted);
  border-bottom: 2px solid var(--text-muted);
  transform: translateY(-65%) rotate(45deg);
  pointer-events: none;
}

.cp-phone-wrap {
  display: flex;
  align-items: stretch;
  min-height: 50px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--bg-elevated);
  overflow: hidden;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.cp-phone-wrap:focus-within {
  border-color: var(--primary);
  box-shadow: 0 0 0 3px var(--primary-soft);
}

.cp-phone-wrap--error {
  border-color: var(--danger);
  box-shadow: 0 0 0 3px rgba(248, 113, 113, 0.15);
}

.cp-dial {
  display: flex;
  align-items: center;
  padding: 0 14px;
  background: var(--primary-soft);
  color: var(--primary);
  font-size: 15px;
  font-weight: 700;
  min-width: 68px;
  flex-shrink: 0;
  border-inline-end: 1px solid var(--border);
}

.cp-phone-input {
  flex: 1;
  min-width: 0;
  border: none;
  background: transparent;
  padding: 0 14px;
  font-family: 'Cairo', sans-serif;
  font-size: 16px;
  color: var(--text-primary);
}

.cp-phone-input:focus {
  outline: none;
}

.cp-phone-input::placeholder {
  color: var(--text-muted);
}

.cp-hint {
  margin: 0;
  font-size: 12px;
  line-height: 1.45;
  color: var(--text-muted);
}

.cp-hint--error {
  color: var(--danger);
}

.cp-submit {
  width: 100%;
  min-height: 52px;
  margin-top: 4px;
  border: none;
  border-radius: 14px;
  background: linear-gradient(145deg, #7C75FF 0%, var(--primary) 50%, #5B54E8 100%);
  color: #fff;
  font-family: 'Cairo', sans-serif;
  font-size: 16px;
  font-weight: 700;
  cursor: pointer;
  box-shadow: 0 4px 16px rgba(96, 165, 250, 0.35);
  transition: transform 0.15s, opacity 0.2s;
}

.cp-submit:active:not(:disabled) {
  transform: scale(0.98);
}

.cp-submit:disabled {
  opacity: 0.5;
  cursor: not-allowed;
  box-shadow: none;
}

.spinner {
  display: inline-block;
  width: 18px;
  height: 18px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top-color: #fff;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}
</style>
