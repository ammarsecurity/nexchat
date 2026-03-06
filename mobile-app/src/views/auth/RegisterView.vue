<script setup>
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { User, Users, UserCircle, Eye, EyeOff, AlertCircle, Calendar } from 'lucide-vue-next'
import { useAuthStore } from '../../stores/auth'
import { useI18n } from 'vue-i18n'
import { useThemeStore } from '../../stores/theme'
import LoaderOverlay from '../../components/LoaderOverlay.vue'

const router = useRouter()
const auth = useAuthStore()
const theme = useThemeStore()
const { t } = useI18n()
const logoImg = computed(() => theme.isLight ? '/logo-light.png' : '/logo.png')

const name = ref('')
const password = ref('')
const birthDay = ref('')
const birthMonth = ref('')
const birthYear = ref('')
const gender = ref('')
const loading = ref(false)
const error = ref('')
const showPass = ref(false)

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
  { value: 'male', label: t('register.male'), Icon: User, color: '#6C63FF' },
  { value: 'female', label: t('register.female'), Icon: Users, color: '#FF6584' },
  { value: 'other', label: t('register.other'), Icon: UserCircle, color: '#00D4FF' }
])

async function handleRegister() {
  if (!name.value.trim() || !password.value || !birthDate.value || !gender.value) return
  loading.value = true
  error.value = ''
  try {
    await auth.register(name.value.trim(), password.value, gender.value, birthDate.value)
    router.replace('/home')
  } catch (e) {
    error.value = e.userMessage ?? e.response?.data?.message ?? t('common.error')
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="register page auth-pattern">
    <LoaderOverlay :show="loading" :text="t('register.loading')" />
    <div class="content">
      <img :src="logoImg" alt="NexChat" class="logo-img" />

      <div class="card glass-card">
        <h2 class="title">{{ t('register.title') }}</h2>
        <p class="subtitle text-secondary">{{ t('register.subtitle') }}</p>

        <form @submit.prevent="handleRegister" class="form">
          <!-- Name -->
          <div class="field">
            <label>{{ t('register.name') }}</label>
            <input
              v-model="name"
              class="input-field"
              :placeholder="t('register.namePlaceholder')"
              maxlength="50"
              autocomplete="username"
            />
          </div>

          <!-- Date of Birth -->
          <div class="field">
            <label class="field-label">
              <Calendar :size="16" class="label-icon" />
              {{ t('register.birthDate') }}
            </label>
            <div class="date-boxes">
              <select v-model="birthDay" class="date-box" :aria-label="t('register.day')">
                <option value="" disabled>{{ t('register.day') }}</option>
                <option v-for="d in validDays" :key="d" :value="d">{{ d }}</option>
              </select>
              <select v-model="birthMonth" class="date-box" :aria-label="t('register.month')">
                <option value="" disabled>{{ t('register.month') }}</option>
                <option v-for="m in months" :key="m" :value="m">{{ m }}</option>
              </select>
              <select v-model="birthYear" class="date-box" :aria-label="t('register.year')">
                <option value="" disabled>{{ t('register.year') }}</option>
                <option v-for="y in years" :key="y" :value="y">{{ y }}</option>
              </select>
            </div>
            <span class="field-hint">{{ t('register.birthDateHint') }}</span>
          </div>

          <!-- Password -->
          <div class="field">
            <label>{{ t('register.password') }}</label>
            <div class="pass-wrap">
              <input
                v-model="password"
                :type="showPass ? 'text' : 'password'"
                class="input-field"
                :placeholder="t('register.passwordPlaceholder')"
                autocomplete="new-password"
              />
              <button type="button" class="show-pass" @click="showPass = !showPass">
                <EyeOff v-if="showPass" :size="20" />
                <Eye v-else :size="20" />
              </button>
            </div>
          </div>

          <!-- Gender -->
          <div class="field">
            <label>{{ t('register.gender') }}</label>
            <div class="gender-grid">
              <button
                v-for="g in genders"
                :key="g.value"
                type="button"
                class="gender-btn"
                :class="{ active: gender === g.value }"
                :style="gender === g.value ? { borderColor: g.color, background: `${g.color}20` } : {}"
                @click="gender = g.value"
              >
                <component :is="g.Icon" :size="24" />
                <span class="gender-label">{{ g.label }}</span>
              </button>
            </div>
          </div>

          <div v-if="error" class="error-toast">
            <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
            <span>{{ error }}</span>
          </div>

          <button
            type="submit"
            class="btn-gradient"
            :disabled="loading || !name || !password || !birthDate || !gender || password.length < 4"
          >
            <span v-if="!loading">{{ t('register.submit') }}</span>
            <span v-else class="spinner"></span>
          </button>
        </form>
      </div>

      <div class="login-link">
        <span class="text-secondary">{{ t('register.hasAccount') }}</span>
        <RouterLink to="/login" class="link">{{ t('register.login') }}</RouterLink>
      </div>
      <div class="privacy-link">
        <RouterLink to="/privacy" class="link text-sm">{{ t('register.privacyPolicy') }}</RouterLink>
      </div>
    </div>
  </div>
</template>

<style scoped>
.register {
  align-items: center;
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  justify-content: flex-start;
  min-height: 100%;
  overflow-y: auto;
  padding: 24px;
  padding-bottom: calc(24px + var(--safe-bottom));
  position: relative;
}

.content {
  display: flex;
  flex-direction: column;
  gap: 24px;
  width: 100%;
  max-width: 380px;
  position: relative;
  z-index: 10;
}

.logo-img {
  height: 64px;
  width: auto;
  object-fit: contain;
  margin-bottom: 8px;
}

.card { padding: 28px 24px; }
.title { font-size: 22px; font-weight: 700; margin-bottom: 6px; }
.subtitle { font-size: 14px; margin-bottom: 24px; }

.form { display: flex; flex-direction: column; gap: 16px; }
.field { display: flex; flex-direction: column; gap: 8px; }
label { color: var(--text-secondary); font-size: 13px; font-weight: 500; }
.field-label { display: flex; align-items: center; gap: 6px; }
.label-icon { color: var(--primary); flex-shrink: 0; }
.field-hint { font-size: 12px; color: var(--text-muted); margin-top: 2px; }

.date-boxes {
  display: grid;
  grid-template-columns: 1fr 1.5fr 1fr;
  gap: 10px;
}

.date-box {
  appearance: none;
  -webkit-appearance: none;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  color: var(--text-primary);
  cursor: pointer;
  font-family: 'Cairo', sans-serif;
  font-size: 15px;
  font-weight: 500;
  min-height: 48px;
  padding: 0 12px;
  text-align: center;
  transition: border-color 0.2s, background 0.2s;
}
.date-box:focus {
  outline: none;
  border-color: var(--primary);
}
.date-box option {
  background: var(--bg-card);
  color: var(--text-primary);
}

.pass-wrap { position: relative; }
.pass-wrap .input-field { padding-right: 44px; }
.show-pass {
  background: none;
  border: none;
  color: var(--primary);
  cursor: pointer;
  font-size: 16px;
  padding: 0;
  position: absolute;
  right: 14px;
  top: 50%;
  transform: translateY(-50%);
  -webkit-tap-highlight-color: transparent;
}
.show-pass:active { opacity: 0.8; }

.gender-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
}

.gender-btn {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  flex-direction: column;
  font-family: 'Cairo';
  gap: 6px;
  padding: 14px 8px;
  transition: all 0.2s;
}
.gender-btn:active { opacity: 0.9; }
.gender-btn.active .gender-label { color: white; }
.gender-label { font-size: 13px; font-weight: 500; }

.login-link { display: flex; gap: 6px; justify-content: center; font-size: 14px; }
.privacy-link { margin-top: 8px; text-align: center; }
.link {
  color: var(--primary);
  font-weight: 600;
  text-decoration: none;
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
