import axios from 'axios'
import { useApiLoadingStore } from '../stores/apiLoading'

/** رفع صور/فيديو/صوت — قد يستغرق وقتاً على الشبكات البطيئة */
export const MEDIA_UPLOAD_TIMEOUT_MS = 180000
/** نشر ستوري (إشعارات للجمهور على السيرفر) */
export const STORY_PUBLISH_TIMEOUT_MS = 90000

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:5000/api',
  timeout: 30000
})

function isMediaUploadUrl(url = '') {
  return /\/media\/upload/i.test(url)
}

api.interceptors.request.use(config => {
  const token = localStorage.getItem('nexchat_token')
  if (token) config.headers.Authorization = `Bearer ${token}`

  if (isMediaUploadUrl(config.url)) {
    config.timeout = Math.max(config.timeout ?? 0, MEDIA_UPLOAD_TIMEOUT_MS)
    config.maxBodyLength = Infinity
    config.maxContentLength = Infinity
  }

  if (!config.skipGlobalLoader) {
    try { useApiLoadingStore().startRequest() } catch {}
  }
  return config
})

api.interceptors.response.use(
  res => {
    if (!res.config.skipGlobalLoader) {
      try { useApiLoadingStore().endRequest() } catch {}
    }
    return res
  },
  err => {
    if (!err.config?.skipGlobalLoader) {
      try { useApiLoadingStore().endRequest() } catch {}
    }
    if (err.response?.status === 401 && !err.config?.skipUnauthorizedEvent) {
      window.dispatchEvent(new CustomEvent('nexchat:unauthorized'))
    }
    const msg = err.response?.data?.message ?? err.message ?? 'حدث خطأ، حاول مجدداً'
    err.userMessage = msg
    return Promise.reject(err)
  }
)

export default api
