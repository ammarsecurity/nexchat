<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { User, Users, UserCircle, Eye, EyeOff, AlertCircle } from 'lucide-vue-next'
import { useAuthStore } from '../../stores/auth'
import { useThemeStore } from '../../stores/theme'
import LoaderOverlay from '../../components/LoaderOverlay.vue'

const router = useRouter()
const auth = useAuthStore()
const theme = useThemeStore()
const logoImg = computed(() => theme.isLight ? '/logo-light.png' : '/logo.png')

const name = ref('')
const password = ref('')
const gender = ref('')
const loading = ref(false)
const error = ref('')
const showPass = ref(false)

const genders = [
  { value: 'male', label: 'ذكر', Icon: User, color: '#6C63FF' },
  { value: 'female', label: 'أنثى', Icon: Users, color: '#FF6584' },
  { value: 'other', label: 'آخر', Icon: UserCircle, color: '#00D4FF' }
]

async function handleRegister() {
  if (!name.value.trim() || !password.value || !gender.value) return
  loading.value = true
  error.value = ''
  try {
    await auth.register(name.value.trim(), password.value, gender.value)
    router.replace('/home')
  } catch (e) {
    error.value = e.userMessage ?? e.response?.data?.message ?? 'حدث خطأ، حاول مجدداً'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="register page auth-pattern">
    <LoaderOverlay :show="loading" text="جاري إنشاء الحساب..." />
    <div class="content">
      <img :src="logoImg" alt="NexChat" class="logo-img" />

      <div class="card glass-card">
        <h2 class="title">إنشاء حساب جديد</h2>
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
                <EyeOff v-if="showPass" :size="20" />
                <Eye v-else :size="20" />
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
            :disabled="loading || !name || !password || !gender || password.length < 4"
          >
            <span v-if="!loading">ابدأ الآن</span>
            <span v-else class="spinner"></span>
          </button>
        </form>
      </div>

      <div class="login-link">
        <span class="text-secondary">لديك حساب؟</span>
        <RouterLink to="/login" class="link">تسجيل الدخول</RouterLink>
      </div>
      <div class="privacy-link">
        <RouterLink to="/privacy" class="link text-sm">سياسة الخصوصية</RouterLink>
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
