<script setup>
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const router = useRouter()
const auth = useAuthStore()

onMounted(() => {
  setTimeout(() => {
    router.replace(auth.isLoggedIn ? '/home' : '/login')
  }, 2200)
})
</script>

<template>
  <div class="splash page">
    <!-- Animated background orbs -->
    <div class="orb orb-1"></div>
    <div class="orb orb-2"></div>
    <div class="orb orb-3"></div>

    <div class="content">
      <div class="logo-wrap">
        <div class="logo-icon">
          <span class="logo-letter">N</span>
        </div>
        <div class="logo-glow"></div>
      </div>

      <div class="app-name">
        <span class="gradient-text">Nex</span><span>Chat</span>
      </div>
      <p class="tagline">تواصل مع العالم</p>

      <div class="loader">
        <div class="loader-bar"></div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.splash {
  background: var(--bg-primary);
  align-items: center;
  justify-content: center;
  position: relative;
  overflow: hidden;
}

.orb {
  border-radius: 50%;
  filter: blur(60px);
  position: absolute;
  animation: float 6s ease-in-out infinite;
}
.orb-1 {
  background: rgba(108, 99, 255, 0.3);
  height: 300px;
  width: 300px;
  top: -80px;
  right: -80px;
  animation-delay: 0s;
}
.orb-2 {
  background: rgba(255, 101, 132, 0.25);
  height: 250px;
  width: 250px;
  bottom: -60px;
  left: -60px;
  animation-delay: 2s;
}
.orb-3 {
  background: rgba(0, 212, 255, 0.15);
  height: 180px;
  width: 180px;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  animation-delay: 1s;
}

@keyframes float {
  0%, 100% { transform: translateY(0) scale(1); }
  50% { transform: translateY(-20px) scale(1.05); }
}
.orb-3 {
  animation: float3 6s ease-in-out infinite;
  animation-delay: 1s;
}
@keyframes float3 {
  0%, 100% { transform: translate(-50%, -50%) scale(1); }
  50% { transform: translate(-50%, -60%) scale(1.1); }
}

.content {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 16px;
  position: relative;
  z-index: 10;
}

.logo-wrap {
  position: relative;
  margin-bottom: 8px;
}

.logo-icon {
  align-items: center;
  background: var(--gradient);
  border-radius: 28px;
  display: flex;
  height: 96px;
  justify-content: center;
  width: 96px;
  animation: pulse-logo 2s ease-in-out infinite;
}

.logo-letter {
  color: white;
  font-size: 52px;
  font-weight: 900;
  letter-spacing: -2px;
}

.logo-glow {
  background: rgba(108, 99, 255, 0.4);
  border-radius: 50%;
  filter: blur(30px);
  height: 120px;
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  width: 120px;
  animation: glow-pulse 2s ease-in-out infinite;
}

@keyframes pulse-logo {
  0%, 100% { transform: scale(1); }
  50% { transform: scale(1.04); }
}
@keyframes glow-pulse {
  0%, 100% { opacity: 0.5; transform: translate(-50%, -50%) scale(1); }
  50% { opacity: 0.8; transform: translate(-50%, -50%) scale(1.2); }
}

.app-name {
  font-size: 38px;
  font-weight: 800;
  letter-spacing: -1px;
  animation: fade-in 0.8s ease forwards;
  animation-delay: 0.3s;
  opacity: 0;
}

.tagline {
  color: var(--text-secondary);
  font-size: 15px;
  animation: fade-in 0.8s ease forwards;
  animation-delay: 0.6s;
  opacity: 0;
}

.loader {
  background: rgba(255,255,255,0.1);
  border-radius: 4px;
  height: 3px;
  margin-top: 32px;
  overflow: hidden;
  width: 120px;
  animation: fade-in 0.5s ease forwards;
  animation-delay: 0.8s;
  opacity: 0;
}

.loader-bar {
  background: var(--gradient);
  border-radius: 4px;
  height: 100%;
  animation: load 1.8s ease forwards;
  animation-delay: 0.9s;
  width: 0%;
}

@keyframes load {
  to { width: 100%; }
}

@keyframes fade-in {
  to { opacity: 1; }
}
</style>
