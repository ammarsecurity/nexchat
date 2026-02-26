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
    <div class="content">
      <!-- Logo -->
      <div class="logo-mini">
        <img :src="logoImg" alt="NexChat" class="logo-img" />
      </div>

      <div class="card glass-card slide-up-enter-active">
        <h2 class="title">مرحباً بعودتك</h2>
        <p class="subtitle text-secondary">سجّل دخولك للمتابعة</p>

        <form @submit.prevent="handleLogin" class="form">
          <div class="field">
            <label>الاسم</label>
            <input
              v-model="name"
              class="input-field"
              placeholder="أدخل اسمك"
              autocomplete="username"
              maxlength="50"
            />
          </div>

          <div class="field">
            <label>كلمة المرور</label>
            <div class="pass-wrap">
              <input
                v-model="password"
                :type="showPass ? 'text' : 'password'"
                class="input-field"
                placeholder="••••••••"
                autocomplete="current-password"
              />
              <button type="button" class="show-pass" @click="showPass = !showPass">
                <EyeOff v-if="showPass" :size="20" />
                <Eye v-else :size="20" />
              </button>
            </div>
          </div>

          <div v-if="error" class="error-msg">{{ error }}</div>

          <button type="submit" class="btn-gradient" :disabled="loading || !name || !password">
            <span v-if="!loading">دخول</span>
            <span v-else class="spinner"></span>
          </button>
        </form>
      </div>

      <div class="register-link">
        <span class="text-secondary">ليس لديك حساب؟</span>
        <RouterLink to="/register" class="link">إنشاء حساب</RouterLink>
      </div>
      <div class="privacy-link">
        <RouterLink to="/privacy" class="link text-sm">سياسة الخصوصية</RouterLink>
      </div>
    </div>
  </div>
</template>

<style scoped>
.login {
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

.logo-mini {
  display: flex;
  justify-content: center;
  margin-bottom: 8px;
}
.logo-mini .logo-img {
  height: 57px;
  width: auto;
  object-fit: contain;
}

.card {
  padding: 28px 24px;
}

.title {
  font-size: 22px;
  font-weight: 700;
  margin-bottom: 6px;
}

.subtitle {
  font-size: 14px;
  margin-bottom: 24px;
}

.form {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.field {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

label {
  color: var(--text-secondary);
  font-size: 13px;
  font-weight: 500;
}

.pass-wrap {
  position: relative;
}
.pass-wrap .input-field { padding-right: 44px; }
.show-pass {
  background: none;
  border: none;
  color: var(--text-muted);
  cursor: pointer;
  font-size: 16px;
  padding: 0;
  position: absolute;
  right: 14px;
  top: 50%;
  transform: translateY(-50%);
}
.show-pass:hover,
.show-pass:active {
  color: var(--text-secondary);
}

.error-msg {
  background: rgba(255, 101, 132, 0.12);
  border: 1px solid rgba(255, 101, 132, 0.3);
  border-radius: 8px;
  color: #FF6584;
  font-size: 13px;
  padding: 10px 12px;
}

.register-link {
  display: flex;
  gap: 6px;
  justify-content: center;
  font-size: 14px;
}
.privacy-link { margin-top: 8px; text-align: center; }

.link {
  color: var(--primary);
  font-weight: 600;
  text-decoration: none;
}

.spinner {
  display: inline-block;
  width: 18px;
  height: 18px;
  border: 2px solid rgba(255,255,255,0.3);
  border-top-color: white;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
