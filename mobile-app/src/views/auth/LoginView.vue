<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { Eye, EyeOff } from 'lucide-vue-next'
import { useAuthStore } from '../../stores/auth'
import logoImg from '../../assets/logo.png'

const router = useRouter()
const auth = useAuthStore()

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
    router.replace('/home')
  } catch (e) {
    error.value = e.response?.data?.message || 'حدث خطأ، حاول مجدداً'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login page">
    <div class="login-content">
      <div class="logo-wrap">
        <img :src="logoImg" alt="NexChat" class="logo-img" />
      </div>

      <h1 class="login-title">مرحباً بعودتك</h1>
      <p class="login-sub">سجّل دخولك للمتابعة</p>

      <form @submit.prevent="handleLogin" class="login-form">
        <div class="input-wrap">
          <input
            v-model="name"
            class="input-native"
            placeholder="الاسم"
            autocomplete="username"
            maxlength="50"
          />
        </div>

        <div class="input-wrap">
          <input
            v-model="password"
            :type="showPass ? 'text' : 'password'"
            class="input-native"
            placeholder="كلمة المرور"
            autocomplete="current-password"
          />
          <button type="button" class="input-toggle" @click="showPass = !showPass" aria-label="إظهار كلمة المرور">
            <EyeOff v-if="showPass" :size="20" />
            <Eye v-else :size="20" />
          </button>
        </div>

        <p v-if="error" class="login-err">{{ error }}</p>

        <button type="submit" class="login-btn" :disabled="loading || !name || !password">
          <span v-if="!loading">دخول</span>
          <span v-else class="spinner"></span>
        </button>
      </form>

      <div class="login-links">
        <span class="text-secondary">ليس لديك حساب؟</span>
        <RouterLink to="/register" class="link">إنشاء حساب</RouterLink>
      </div>
      <RouterLink to="/privacy" class="privacy-link">سياسة الخصوصية</RouterLink>
    </div>
  </div>
</template>

<style scoped>
.login {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  min-height: 100%;
  overflow-y: auto;
  padding: calc(var(--safe-top) + 24px) var(--spacing) calc(24px + var(--safe-bottom));
  -webkit-overflow-scrolling: touch;
}

.login-content {
  width: 100%;
  max-width: 360px;
  margin: 0 auto;
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
  color: var(--text-muted);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.input-toggle:active { color: var(--text-secondary); }

.login-err {
  font-size: 13px;
  color: var(--danger);
  margin: 0;
  padding: 10px 14px;
  background: rgba(255, 101, 132, 0.1);
  border-radius: 10px;
}

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

.privacy-link {
  display: block;
  text-align: center;
  margin-top: 16px;
  font-size: 13px;
  color: var(--primary);
  font-weight: 500;
  text-decoration: none;
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
