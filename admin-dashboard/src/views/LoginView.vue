<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import api from '../services/api'

const router = useRouter()
const name = ref('')
const password = ref('')
const loading = ref(false)
const error = ref('')
const showPass = ref(false)

async function handleLogin() {
  loading.value = true
  error.value = ''
  try {
    const res = await api.post('/auth/login', { name: name.value, password: password.value })
    const payload = JSON.parse(atob(res.data.token.split('.')[1]))
    if (payload.role !== 'admin') {
      error.value = 'ليس لديك صلاحيات الأدمن'
      return
    }
    localStorage.setItem('nexchat_admin_token', res.data.token)
    router.replace('/dashboard')
  } catch (e) {
    error.value = e.response?.data?.message || 'بيانات دخول غير صحيحة'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <v-container class="login-page fill-height" fluid>
    <div class="bg-orb orb-1"></div>
    <div class="bg-orb orb-2"></div>
    <div class="bg-orb orb-3"></div>

    <v-row justify="center" align="center" class="fill-height">
      <v-col cols="12" sm="8" md="5" lg="4">
        <div class="text-center mb-8">
          <div class="logo-wrap">
            <img src="/logo-light.png" alt="نيكس شات" class="logo-img" />
          </div>
          <div class="brand-title mt-4">نيكس شات</div>
          <div class="brand-caption mt-1">لوحة تحكم المشرفين</div>
        </div>

        <v-card class="login-card pa-6 pa-sm-8" rounded="xl" variant="flat" elevation="0">
          <v-card-title class="login-title text-h6 font-weight-bold mb-6 pa-0">
            تسجيل الدخول
          </v-card-title>

          <v-form @submit.prevent="handleLogin">
            <v-text-field
              v-model="name"
              label="اسم المستخدم"
              variant="outlined"
              rounded="lg"
              prepend-inner-icon="mdi-account"
              class="mb-4"
              hide-details
              flat
            />

            <v-text-field
              v-model="password"
              label="كلمة المرور"
              :type="showPass ? 'text' : 'password'"
              variant="outlined"
              rounded="lg"
              prepend-inner-icon="mdi-lock"
              :append-inner-icon="showPass ? 'mdi-eye-off' : 'mdi-eye'"
              @click:append-inner="showPass = !showPass"
              class="mb-4"
              hide-details
              flat
            />

            <v-alert v-if="error" type="error" variant="tonal" rounded="lg" class="mb-4" density="compact">
              {{ error }}
            </v-alert>

            <v-btn
              type="submit"
              size="large"
              block
              rounded="lg"
              :loading="loading"
              color="primary"
              variant="flat"
              class="login-btn font-weight-bold"
              elevation="0"
            >
              دخول
            </v-btn>
          </v-form>
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>

<style scoped>
.login-page {
  background: var(--bg);
  position: relative;
  overflow: hidden;
}

.bg-orb {
  border-radius: 50%;
  filter: blur(80px);
  position: absolute;
  pointer-events: none;
}
.orb-1 {
  background: rgba(46, 134, 251, 0.22);
  width: 420px;
  height: 420px;
  top: -120px;
  right: -100px;
}
.orb-2 {
  background: rgba(34, 211, 238, 0.16);
  width: 320px;
  height: 320px;
  bottom: -100px;
  left: -80px;
}
.orb-3 {
  background: rgba(139, 92, 246, 0.1);
  width: 240px;
  height: 240px;
  top: 40%;
  left: 50%;
}

.logo-wrap { display: inline-block; }
.logo-img {
  height: 80px;
  width: auto;
  object-fit: contain;
}

.brand-title {
  font-size: 1.75rem;
  font-weight: 900;
  letter-spacing: -0.02em;
  color: var(--text);
}

.brand-caption {
  color: var(--text-secondary);
  font-weight: 600;
  font-size: 0.95rem;
}

.login-card {
  background: transparent !important;
  border: none !important;
  box-shadow: none !important;
}

.login-card :deep(.v-field) {
  box-shadow: none !important;
}

.login-card :deep(.v-field__outline) {
  --v-field-border-opacity: 1;
}

.login-btn {
  min-height: 48px;
  box-shadow: none !important;
}

.login-title {
  letter-spacing: -0.02em;
  color: var(--text);
}
</style>
