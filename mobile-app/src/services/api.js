import axios from 'axios'
import { useApiLoadingStore } from '../stores/apiLoading'

const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:5000/api',
  timeout: 10000
})

api.interceptors.request.use(config => {
  const token = localStorage.getItem('nexchat_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
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
    if (err.response?.status === 401) {
      window.dispatchEvent(new CustomEvent('nexchat:unauthorized'))
    }
    const msg = err.response?.data?.message ?? err.message ?? 'حدث خطأ، حاول مجدداً'
    err.userMessage = msg
    return Promise.reject(err)
  }
)

export default api
