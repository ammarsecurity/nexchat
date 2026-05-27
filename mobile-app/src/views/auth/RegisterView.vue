<script setup>
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { User, Users, UserCircle, Eye, EyeOff, AlertCircle, Calendar } from 'lucide-vue-next'
import { useAuthStore } from '../../stores/auth'
import { useI18n } from 'vue-i18n'
import { useThemeStore } from '../../stores/theme'
import { publicUrl } from '../../utils/publicUrl'
import LoaderOverlay from '../../components/LoaderOverlay.vue'

const router = useRouter()
const auth = useAuthStore()
const theme = useThemeStore()
const { t } = useI18n()
const logoImg = computed(() => publicUrl(theme.isLight ? 'logo-light.png' : 'logo.png'))

const name = ref('')
const password = ref('')
const birthDay = ref('')
const birthMonth = ref('')
const birthYear = ref('')
const gender = ref('')
const loading = ref(false)
const error = ref('')
const showPass = ref(false)
const acceptedLegal = ref(false)

const birthDate = computed(() => {
  if (!birthDay.value || !birthMonth.value || !birthYear.value) return ''
  const d = String(birthDay.value).padStart(2, '0')
  const m = String(birthMonth.value).padStart(2, '0')
  return `${birthYear.value}-${m}-${d}`
})

const months = computed(() => Array.from({ length: 12 }, (_, i) => i + 1))
const years = computed(() => {
  const currentYear = new Date().getFullYear()
  const maxYear = currentYear - 18
  const minYear = currentYear - 120
  return Array.from({ length: maxYear - minYear + 1 }, (_, i) => maxYear - i)
})

const daysInMonth = computed(() => {
  const m = parseInt(birthMonth.value, 10)
  const y = parseInt(birthYear.value, 10)
  if (!m) return 31
  const isLeap = y && (y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0))
  const days = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  return days[m - 1] ?? 31
})

const validDays = computed(() => Array.from({ length: daysInMonth.value }, (_, i) => i + 1))

watch([birthMonth, birthYear], () => {
  const d = parseInt(birthDay.value, 10)
  if (d > daysInMonth.value) birthDay.value = String(daysInMonth.value)
})

const genders = computed(() => [
  { value: 'male', label: t('register.male'), Icon: User },
  { value: 'female', label: t('register.female'), Icon: Users },
  { value: 'other', label: t('register.other'), Icon: UserCircle }
])

const canSubmit = computed(() =>
  name.value.trim() &&
  password.value.length >= 4 &&
  birthDate.value &&
  gender.value &&
  acceptedLegal.value &&
  !loading.value
)

async function handleRegister() {
  if (!canSubmit.value) return
  loading.value = true
  error.value = ''
  try {
    await auth.register(name.value.trim(), password.value, gender.value, birthDate.value)
    if (auth.needsProfileContact) router.replace('/complete-profile')
    else router.replace('/home')
  } catch (e) {
    error.value = e.userMessage ?? e.response?.data?.message ?? t('common.error')
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="register page">
    <LoaderOverlay :show="loading" :text="t('register.loading')" />

    <div class="register-scroll">
      <div class="register-content">
      <div class="logo-wrap">
        <img :src="logoImg" alt="NexChat" class="logo-img" />
      </div>

      <h1 class="register-title">{{ t('register.title') }}</h1>
      <p class="register-sub">{{ t('register.subtitle') }}</p>

      <form class="register-form" @submit.prevent="handleRegister">
        <!-- 1. الحساب -->
        <section class="form-section">
          <h2 class="section-label">{{ t('register.sectionAccount') }}</h2>

          <div class="input-wrap">
            <input
              v-model="name"
              class="input-native"
              :placeholder="t('register.namePlaceholder')"
              maxlength="50"
              autocomplete="username"
            />
          </div>

          <div class="input-wrap">
            <input
              v-model="password"
              :type="showPass ? 'text' : 'password'"
              class="input-native"
              :placeholder="t('register.passwordPlaceholder')"
              autocomplete="new-password"
            />
            <button
              type="button"
              class="input-toggle"
              :aria-label="t('login.showPassword')"
              @click="showPass = !showPass"
            >
              <EyeOff v-if="showPass" :size="20" />
              <Eye v-else :size="20" />
            </button>
          </div>
        </section>

        <!-- 2. عنك -->
        <section class="form-section">
          <h2 class="section-label">
            <Calendar :size="15" stroke-width="2" class="section-label-icon" />
            {{ t('register.sectionAbout') }}
          </h2>

          <p class="field-hint">{{ t('register.birthDateHint') }}</p>
          <div class="date-row">
            <select v-model="birthDay" class="date-select" :aria-label="t('register.day')">
              <option value="" disabled>{{ t('register.day') }}</option>
              <option v-for="d in validDays" :key="d" :value="d">{{ d }}</option>
            </select>
            <select v-model="birthMonth" class="date-select date-select--month" :aria-label="t('register.month')">
              <option value="" disabled>{{ t('register.month') }}</option>
              <option v-for="m in months" :key="m" :value="m">{{ m }}</option>
            </select>
            <select v-model="birthYear" class="date-select" :aria-label="t('register.year')">
              <option value="" disabled>{{ t('register.year') }}</option>
              <option v-for="y in years" :key="y" :value="y">{{ y }}</option>
            </select>
          </div>

          <p class="field-label">{{ t('register.gender') }}</p>
          <div class="gender-segment">
            <button
              v-for="g in genders"
              :key="g.value"
              type="button"
              class="gender-option"
              :class="{ active: gender === g.value }"
              @click="gender = g.value"
            >
              <component :is="g.Icon" :size="20" stroke-width="2" />
              <span>{{ g.label }}</span>
            </button>
          </div>
        </section>

        <div v-if="error" class="error-toast">
          <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
          <span>{{ error }}</span>
        </div>

        <label class="legal-row" for="register-accept-legal">
          <input
            id="register-accept-legal"
            v-model="acceptedLegal"
            type="checkbox"
            class="legal-checkbox"
            :aria-label="t('register.acceptLegalAria')"
          />
          <span class="legal-text">
            {{ t('register.agreePrefix') }}
            <RouterLink to="/privacy" class="inline-legal-link" @click.stop>{{ t('register.privacyPolicy') }}</RouterLink>
            {{ t('register.agreeMid') }}
            <RouterLink to="/terms" class="inline-legal-link" @click.stop>{{ t('register.termsOfService') }}</RouterLink>
          </span>
        </label>

        <button type="submit" class="register-btn" :disabled="!canSubmit">
          <span v-if="!loading">{{ t('register.submit') }}</span>
          <span v-else class="spinner" />
        </button>
      </form>

      <div class="register-links">
        <span class="text-secondary">{{ t('register.hasAccount') }}</span>
        <RouterLink to="/login" class="link">{{ t('register.login') }}</RouterLink>
      </div>

      <div class="legal-links">
        <RouterLink to="/privacy" class="privacy-link">{{ t('register.privacyPolicy') }}</RouterLink>
        <span class="legal-sep" aria-hidden="true">·</span>
        <RouterLink to="/terms" class="privacy-link">{{ t('register.termsOfService') }}</RouterLink>
      </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.register {
  background: var(--bg-primary);
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.register-scroll {
  flex: 1;
  min-height: 0;
  width: 100%;
  overflow-y: auto;
  overflow-x: hidden;
  -webkit-overflow-scrolling: touch;
  padding:
    calc(var(--safe-top) + 16px)
    max(var(--spacing), env(safe-area-inset-right, 0px))
    calc(32px + var(--safe-bottom))
    max(var(--spacing), env(safe-area-inset-left, 0px));
  display: flex;
  justify-content: center;
}

.register-content {
  width: 100%;
  max-width: 360px;
}

.logo-wrap {
  display: flex;
  justify-content: center;
  margin-bottom: 20px;
}

.logo-img {
  height: 52px;
  width: auto;
  object-fit: contain;
}

.register-title {
  margin: 0 0 6px;
  font-size: 24px;
  font-weight: 800;
  text-align: center;
  color: var(--text-primary);
}

.register-sub {
  margin: 0 0 24px;
  font-size: 15px;
  line-height: 1.5;
  color: var(--text-secondary);
  text-align: center;
}

.register-form {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.form-section {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.section-label {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 0 0 2px;
  font-size: 13px;
  font-weight: 700;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.section-label-icon {
  color: var(--primary);
  flex-shrink: 0;
}

.input-wrap {
  position: relative;
}

.input-native {
  width: 100%;
  min-height: 52px;
  padding: 0 48px 0 16px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  color: var(--text-primary);
  font-size: 16px;
  font-family: 'Cairo', sans-serif;
  outline: none;
  -webkit-appearance: none;
  appearance: none;
  box-shadow: var(--shadow-sm);
}

.input-native::placeholder {
  color: var(--text-muted);
}

.input-native:focus {
  border-color: var(--primary);
}

.input-toggle {
  position: absolute;
  inset-inline-end: 12px;
  top: 50%;
  transform: translateY(-50%);
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: none;
  border: none;
  color: var(--primary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.input-toggle:active {
  opacity: 0.8;
}

.field-hint {
  margin: 0;
  font-size: 12px;
  color: var(--text-muted);
  line-height: 1.45;
}

.field-label {
  margin: 4px 0 0;
  font-size: 13px;
  font-weight: 600;
  color: var(--text-secondary);
}

.date-row {
  display: grid;
  grid-template-columns: 1fr 1.2fr 1.15fr;
  gap: 8px;
}

.date-select {
  min-height: 48px;
  padding: 0 10px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 14px;
  color: var(--text-primary);
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  text-align: center;
  cursor: pointer;
  outline: none;
  box-shadow: var(--shadow-sm);
  -webkit-appearance: none;
  appearance: none;
}

.date-select:focus {
  border-color: var(--primary);
}

.date-select option {
  background: var(--bg-card);
  color: var(--text-primary);
}

.gender-segment {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
  padding: 4px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: 14px;
}

.gender-option {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  min-height: 72px;
  padding: 10px 6px;
  border: none;
  border-radius: 10px;
  background: transparent;
  color: var(--text-secondary);
  font-family: 'Cairo', sans-serif;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.15s, color 0.15s, box-shadow 0.15s;
  -webkit-tap-highlight-color: transparent;
}

.gender-option.active {
  background: var(--bg-card);
  color: var(--primary);
  box-shadow: var(--shadow-sm);
}

.gender-option:active {
  transform: scale(0.98);
}

.legal-row {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  cursor: pointer;
  padding: 4px 0;
}

.legal-checkbox {
  width: 22px;
  height: 22px;
  min-width: 22px;
  margin-top: 2px;
  accent-color: var(--primary);
  cursor: pointer;
  flex-shrink: 0;
}

.legal-text {
  font-size: 13px;
  line-height: 1.55;
  color: var(--text-secondary);
}

.inline-legal-link {
  color: var(--primary);
  font-weight: 600;
  text-decoration: underline;
  text-underline-offset: 2px;
}

.register-btn {
  min-height: 52px;
  padding: 0 24px;
  background: var(--primary);
  border: none;
  border-radius: 999px;
  color: #fff;
  font-size: 17px;
  font-weight: 700;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  box-shadow: 0 4px 14px rgba(37, 99, 235, 0.28);
  -webkit-tap-highlight-color: transparent;
}

.register-btn:active:not(:disabled) {
  transform: scale(0.99);
}

.register-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
  box-shadow: none;
}

.register-links {
  display: flex;
  gap: 6px;
  justify-content: center;
  margin-top: 24px;
  font-size: 14px;
}

.legal-links {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  align-items: center;
  gap: 4px 10px;
  margin-top: 16px;
  font-size: 13px;
}

.legal-links .privacy-link {
  color: var(--primary);
  font-weight: 500;
  text-decoration: none;
}

.legal-sep {
  opacity: 0.45;
  user-select: none;
}

.link {
  color: var(--primary);
  font-weight: 600;
  text-decoration: none;
}

.spinner {
  display: inline-block;
  width: 20px;
  height: 20px;
  border: 2px solid rgba(255, 255, 255, 0.35);
  border-top-color: #fff;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

@media (max-width: 360px) {
  .gender-option {
    min-height: 64px;
    font-size: 11px;
  }

  .date-row {
    grid-template-columns: 1fr 1fr 1.1fr;
    gap: 6px;
  }
}
</style>
