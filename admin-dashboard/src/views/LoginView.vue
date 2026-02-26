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
    // Verify admin claim
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

    <v-row justify="center" align="center" class="fill-height">
      <v-col cols="12" sm="8" md="5" lg="4">
        <div class="text-center mb-8">
          <div class="logo-wrap">
            <div class="logo-icon">N</div>
          </div>
          <div class="text-h5 font-weight-bold mt-3">
            <span class="gradient-text">NexChat</span> Admin
          </div>
          <div class="text-body-2 text-medium-emphasis mt-1">لوحة تحكم المشرفين</div>
        </div>

        <v-card class="pa-8" rounded="xl" elevation="0">
          <v-card-title class="text-h6 font-weight-bold mb-6 pa-0">تسجيل الدخول 🔐</v-card-title>

          <v-form @submit.prevent="handleLogin">
            <v-text-field
              v-model="name"
              label="اسم المستخدم"
              variant="outlined"
              rounded="lg"
              prepend-inner-icon="mdi-account"
              class="mb-4"
              hide-details
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
            />

            <v-alert v-if="error" type="error" variant="tonal" rounded="lg" class="mb-4" density="compact">
              {{ error }}
            </v-alert>

            <v-btn
              type="submit"
              size="large"
              block
              rounded="xl"
              :loading="loading"
              class="gradient-btn text-white font-weight-bold"
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
.orb-1 { background: rgba(108,99,255,0.2); width:400px; height:400px; top:-100px; right:-100px; }
.orb-2 { background: rgba(255,101,132,0.15); width:300px; height:300px; bottom:-80px; left:-80px; }

.logo-wrap { display: inline-block; }
.logo-icon {
  align-items: center;
  background: var(--gradient);
  border-radius: 20px;
  color: white;
  display: inline-flex;
  font-size: 36px;
  font-weight: 900;
  height: 72px;
  justify-content: center;
  width: 72px;
  box-shadow: 0 0 40px rgba(108,99,255,0.4);
}

.gradient-btn {
  background: var(--gradient) !important;
}
</style>
