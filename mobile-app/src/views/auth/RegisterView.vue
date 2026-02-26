<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../../stores/auth'

const router = useRouter()
const auth = useAuthStore()

const name = ref('')
const password = ref('')
const gender = ref('')
const loading = ref(false)
const error = ref('')
const showPass = ref(false)

const genders = [
  { value: 'male', label: 'ذكر', icon: '👨', color: '#6C63FF' },
  { value: 'female', label: 'أنثى', icon: '👩', color: '#FF6584' },
  { value: 'other', label: 'آخر', icon: '🧑', color: '#00D4FF' }
]

async function handleRegister() {
  if (!name.value.trim() || !password.value || !gender.value) return
  loading.value = true
  error.value = ''
  try {
    await auth.register(name.value.trim(), password.value, gender.value)
    router.replace('/home')
  } catch (e) {
    error.value = e.response?.data?.message || 'حدث خطأ، حاول مجدداً'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="register page">
    <div class="bg-orb bg-orb-1"></div>
    <div class="bg-orb bg-orb-2"></div>

    <div class="content">
      <div class="logo-mini">
        <div class="logo-icon">N</div>
        <span class="gradient-text font-bold" style="font-size:22px">NexChat</span>
      </div>

      <div class="card glass-card">
        <h2 class="title">إنشاء حساب جديد ✨</h2>
        <p class="subtitle text-secondary">سريع وسهل، ثلاثة حقول فقط!</p>

        <form @submit.prevent="handleRegister" class="form">
          <!-- Name -->
          <div class="field">
            <label>الاسم</label>
            <input
              v-model="name"
              class="input-field"
              placeholder="اسمك في التطبيق"
              maxlength="50"
              autocomplete="username"
            />
          </div>

          <!-- Password -->
          <div class="field">
            <label>كلمة المرور</label>
            <div class="pass-wrap">
              <input
                v-model="password"
                :type="showPass ? 'text' : 'password'"
                class="input-field"
                placeholder="4 أحرف على الأقل"
                autocomplete="new-password"
              />
              <button type="button" class="show-pass" @click="showPass = !showPass">
                {{ showPass ? '🙈' : '👁' }}
              </button>
            </div>
          </div>

          <!-- Gender -->
          <div class="field">
            <label>الجنس</label>
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
                <span class="gender-icon">{{ g.icon }}</span>
                <span class="gender-label">{{ g.label }}</span>
              </button>
            </div>
          </div>

          <div v-if="error" class="error-msg">⚠️ {{ error }}</div>

          <button
            type="submit"
            class="btn-gradient"
            :disabled="loading || !name || !password || !gender || password.length < 4"
          >
            <span v-if="!loading">ابدأ الآن 🚀</span>
            <span v-else class="spinner"></span>
          </button>
        </form>
      </div>

      <div class="login-link">
        <span class="text-secondary">لديك حساب؟</span>
        <RouterLink to="/login" class="link">تسجيل الدخول</RouterLink>
      </div>
    </div>
  </div>
</template>

<style scoped>
.register {
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
  background: rgba(255, 101, 132, 0.2);
  height: 250px;
  width: 250px;
  top: -80px;
  left: -60px;
}
.bg-orb-2 {
  background: rgba(108, 99, 255, 0.15);
  height: 200px;
  width: 200px;
  bottom: 80px;
  right: -60px;
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

.card { padding: 28px 24px; }
.title { font-size: 22px; font-weight: 700; margin-bottom: 6px; }
.subtitle { font-size: 14px; margin-bottom: 24px; }

.form { display: flex; flex-direction: column; gap: 16px; }
.field { display: flex; flex-direction: column; gap: 8px; }
label { color: var(--text-secondary); font-size: 13px; font-weight: 500; }

.pass-wrap { position: relative; }
.pass-wrap .input-field { padding-right: 44px; }
.show-pass {
  background: none; border: none; cursor: pointer;
  font-size: 16px; padding: 0; position: absolute;
  right: 14px; top: 50%; transform: translateY(-50%);
}

.gender-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
}

.gender-btn {
  align-items: center;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid var(--border);
  border-radius: 12px;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 14px 8px;
  transition: all 0.2s;
}
.gender-btn:hover { background: rgba(255,255,255,0.08); }
.gender-btn.active { transform: scale(1.03); }

.gender-icon { font-size: 26px; }
.gender-label { color: white; font-size: 13px; font-weight: 500; }

.error-msg {
  background: rgba(255, 101, 132, 0.12);
  border: 1px solid rgba(255, 101, 132, 0.3);
  border-radius: 8px;
  color: #FF6584;
  font-size: 13px;
  padding: 10px 12px;
}

.login-link { display: flex; gap: 6px; justify-content: center; font-size: 14px; }
.link {
  background: var(--gradient);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
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
