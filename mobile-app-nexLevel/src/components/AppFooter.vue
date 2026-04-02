<script setup>
import { ref, onMounted } from 'vue'
import { Twitter, Instagram, Facebook, Youtube, Linkedin, MessageCircle, Send, Video } from 'lucide-vue-next'

const socialLinks = ref([])
const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:5000/api'

const platformIcons = {
  twitter: Twitter,
  instagram: Instagram,
  facebook: Facebook,
  tiktok: Video,
  youtube: Youtube,
  linkedin: Linkedin,
  whatsapp: MessageCircle,
  telegram: Send
}

async function fetchSocialLinks() {
  try {
    const res = await fetch(`${API_BASE}/sitecontent/social_links`)
    const data = await res.json()
    const content = data?.content
    if (content) {
      try {
        socialLinks.value = JSON.parse(content)
      } catch {
        socialLinks.value = []
      }
    }
  } catch {
    socialLinks.value = []
  }
}

function openLink(url) {
  if (url?.startsWith('http')) window.open(url, '_blank')
}

onMounted(fetchSocialLinks)
</script>

<template>
  <footer class="app-footer">
    <div class="footer-inner">
      <div class="footer-brand">NexChat</div>
      <div v-if="socialLinks.length" class="social-row">
        <a
          v-for="link in socialLinks"
          :key="link.platform"
          class="social-btn"
          :href="link.url"
          target="_blank"
          rel="noopener noreferrer"
          :aria-label="link.platform"
          @click.prevent="openLink(link.url)"
        >
          <component :is="platformIcons[link.platform] || Send" :size="20" />
        </a>
      </div>
    </div>
  </footer>
</template>

<style scoped>
.app-footer {
  flex-shrink: 0;
  padding: var(--spacing) var(--spacing) calc(var(--spacing) + var(--safe-bottom));
  width: 100%;
}

.footer-inner {
  align-items: center;
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding-top: var(--spacing);
  border-top: 1px solid var(--border);
}

.footer-brand {
  color: var(--primary);
  font-size: 15px;
  font-weight: 700;
}

.social-row {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  justify-content: center;
}

.social-btn {
  align-items: center;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-full);
  color: var(--text-secondary);
  display: flex;
  height: 44px;
  justify-content: center;
  min-width: 44px;
  padding: 0;
  text-decoration: none;
  transition: background 0.2s, color 0.2s;
}

.social-btn:active {
  background: var(--bg-card-hover);
  color: var(--primary);
}
</style>
