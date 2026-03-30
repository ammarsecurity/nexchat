<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { Eye, EyeOff, AlertCircle } from 'lucide-vue-next'
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
const loading = ref(false)
const error = ref('')
const showPass = ref(false)

async function handleLogin() {
  if (!name.value.trim() || !password.value) return
  loading.value = true
  error.value = ''
  try {
    await auth.login(name.value.trim(), password.value)
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
  <div class="login page auth-pattern">
    <LoaderOverlay :show="loading" :text="t('login.loading')" />
    <div class="login-content">
      <div class="logo-wrap">
        <img :src="logoImg" alt="NexChat" class="logo-img" />
      </div>

      <h1 class="login-title">{{ t('login.title') }}</h1>
      <p class="login-sub">{{ t('login.subtitle') }}</p>

      <form @submit.prevent="handleLogin" class="login-form">
        <div class="input-wrap">
          <input
            v-model="name"
            class="input-native"
            :placeholder="t('login.name')"
            autocomplete="username"
            maxlength="50"
          />
        </div>

        <div class="input-wrap">
          <input
            v-model="password"
            :type="showPass ? 'text' : 'password'"
            class="input-native"
            :placeholder="t('login.password')"
            autocomplete="current-password"
          />
          <button type="button" class="input-toggle" @click="showPass = !showPass" :aria-label="t('login.showPassword')">
            <EyeOff v-if="showPass" :size="20" />
            <Eye v-else :size="20" />
          </button>
        </div>

        <div v-if="error" class="error-toast">
          <span class="error-toast-icon"><AlertCircle :size="18" stroke-width="2" /></span>
          <span>{{ error }}</span>
        </div>

        <button type="submit" class="login-btn" :disabled="loading || !name || !password">
          <span v-if="!loading">{{ t('login.submit') }}</span>
          <span v-else class="spinner"></span>
        </button>
      </form>

      <div class="login-links">
        <span class="text-secondary">{{ t('login.noAccount') }}</span>
        <RouterLink to="/register" class="link">{{ t('login.createAccount') }}</RouterLink>
      </div>
      <div class="legal-links">
        <RouterLink to="/privacy" class="privacy-link">{{ t('login.privacyPolicy') }}</RouterLink>
        <span class="legal-sep" aria-hidden="true">·</span>
        <RouterLink to="/terms" class="privacy-link">{{ t('login.termsOfService') }}</RouterLink>
      </div>
    </div>
  </div>
</template>

<style scoped>
.login {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 100%;
  overflow-y: auto;
  padding: calc(var(--safe-top) + 24px) var(--spacing) calc(24px + var(--safe-bottom));
  -webkit-overflow-scrolling: touch;
}

.login-content {
  width: 100%;
  max-width: 360px;
}

.logo-wrap {
  display: flex;
  justify-content: center;
  margin-bottom: 24px;
}
.logo-img { height: 52px; width: auto; object-fit: contain; }

.login-title {
  font-size: 24px;
  font-weight: 700;
  margin-bottom: 6px;
  text-align: center;
}

.login-sub {
  font-size: 15px;
  color: var(--text-secondary);
  margin-bottom: 28px;
  text-align: center;
}

.login-form {
  display: flex;
  flex-direction: column;
  gap: 16px;
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
}
.input-native::placeholder { color: var(--text-muted); }
.input-native:focus { border-color: var(--primary); }

.input-toggle {
  position: absolute;
  right: 12px;
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
.input-toggle:active { opacity: 0.8; }

.login-btn {
  min-height: 52px;
  padding: 0 24px;
  background: var(--primary);
  border: none;
  border-radius: 14px;
  color: white;
  font-size: 17px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.login-btn:active:not(:disabled) { opacity: 0.9; }
.login-btn:disabled { opacity: 0.5; cursor: not-allowed; }

.login-links {
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
  border: 2px solid rgba(255,255,255,0.3);
  border-top-color: white;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
