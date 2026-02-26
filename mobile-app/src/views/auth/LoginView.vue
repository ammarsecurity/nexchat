<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../../stores/auth'

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
    <div class="bg-orb bg-orb-1"></div>
    <div class="bg-orb bg-orb-2"></div>

    <div class="content">
      <!-- Logo -->
      <div class="logo-mini">
        <div class="logo-icon">N</div>
        <span class="gradient-text font-bold" style="font-size:22px">NexChat</span>
      </div>

      <div class="card glass-card slide-up-enter-active">
        <h2 class="title">مرحباً بعودتك 👋</h2>
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
                {{ showPass ? '🙈' : '👁' }}
              </button>
            </div>
          </div>

          <div v-if="error" class="error-msg">⚠️ {{ error }}</div>

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
    </div>
  </div>
</template>

<style scoped>
.login {
  align-items: center;
  background: var(--bg-primary);
  justify-content: center;
  padding: 24px;
  position: relative;
  overflow: hidden;
}

.bg-orb {
  border-radius: 50%;
  filter: blur(80px);
  position: absolute;
  pointer-events: none;
}
.bg-orb-1 {
  background: rgba(108, 99, 255, 0.2);
  height: 250px;
  width: 250px;
  top: -80px;
  right: -60px;
}
.bg-orb-2 {
  background: rgba(255, 101, 132, 0.15);
  height: 200px;
  width: 200px;
  bottom: 80px;
  left: -60px;
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
  align-items: center;
  gap: 10px;
  justify-content: center;
}

.logo-icon {
  align-items: center;
  background: var(--gradient);
  border-radius: 12px;
  color: white;
  display: flex;
  font-size: 22px;
  font-weight: 900;
  height: 40px;
  justify-content: center;
  width: 40px;
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
  cursor: pointer;
  font-size: 16px;
  padding: 0;
  position: absolute;
  right: 14px;
  top: 50%;
  transform: translateY(-50%);
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

.link {
  background: var(--gradient);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
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
