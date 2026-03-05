<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, BookmarkPlus, Trash2, PhoneCall, PhoneOff, AlertCircle } from 'lucide-vue-next'
import { useAuthStore } from '../stores/auth'
import { useI18n } from 'vue-i18n'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { matchingHub, startHub, ensureConnected } from '../services/signalr'
import api from '../services/api'

const router = useRouter()
const auth = useAuthStore()
const { t } = useI18n()

const savedCodes = ref([])
const savedCodesLoading = ref(false)
const loading = ref(false)
const waitingForAccept = ref(false)
const codeError = ref('')
const addCodeError = ref('')
let connectionTimeoutId = null
const addCodeSubmitting = ref(false)
const newCode = ref('')
const newLabel = ref('')

const isFeatured = computed(() => auth.user?.isFeatured ?? false)

function clearConnectionTimeout() {
  if (connectionTimeoutId) {
    clearTimeout(connectionTimeoutId)
    connectionTimeoutId = null
  }
}

function startConnectionTimeout() {
  clearConnectionTimeout()
  connectionTimeoutId = setTimeout(async () => {
    connectionTimeoutId = null
    waitingForAccept.value = false
    loading.value = false
    codeError.value = t('home.timeoutError')
    try {
      await ensureConnected(matchingHub)
      await matchingHub.invoke('CancelConnectionRequest')
    } catch {}
  }, 60000)
}

onMounted(async () => {
  await startHub(matchingHub)
  matchingHub.on('ConnectionRequestSent', () => {
    waitingForAccept.value = true
    startConnectionTimeout()
  })
  matchingHub.on('ConnectionDeclined', () => {
    clearConnectionTimeout()
    waitingForAccept.value = false
    loading.value = false
    codeError.value = t('home.requestDeclined')
  })
  matchingHub.on('CodeError', (msg) => {
    clearConnectionTimeout()
    waitingForAccept.value = false
    loading.value = false
    codeError.value = msg || t('home.connectionError')
  })
  matchingHub.on('ConnectionCancelled', () => {
    clearConnectionTimeout()
    waitingForAccept.value = false
    loading.value = false
  })
  if (isFeatured.value) await fetchSavedCodes()
  else router.replace('/home')
})

onUnmounted(() => {
  clearConnectionTimeout()
  matchingHub.off('ConnectionRequestSent')
  matchingHub.off('ConnectionDeclined')
  matchingHub.off('CodeError')
  matchingHub.off('ConnectionCancelled')
})

async function fetchSavedCodes() {
  if (!auth.user?.isFeatured) return
  savedCodesLoading.value = true
  try {
    const { data } = await api.get('/user/saved-codes')
    savedCodes.value = data ?? []
  } catch {
    savedCodes.value = []
  } finally {
    savedCodesLoading.value = false
  }
}

async function addSavedCode() {
  const code = newCode.value.trim().toUpperCase()
  if (!code || !code.startsWith('NX-') || code.length !== 7) {
    addCodeError.value = t('home.codeFormatError')
    return
  }
  addCodeError.value = ''
  addCodeSubmitting.value = true
  try {
    await api.post('/user/saved-codes', { code, label: newLabel.value.trim() || null })
    newCode.value = ''
    newLabel.value = ''
    await fetchSavedCodes()
  } catch (e) {
    addCodeError.value = e.response?.data?.message ?? t('common.error')
  } finally {
    addCodeSubmitting.value = false
  }
}

async function removeSavedCode(code) {
  try {
    await api.delete(`/user/saved-codes/${encodeURIComponent(code)}`)
    await fetchSavedCodes()
  } catch {}
}

async function connectBySavedCode(code) {
  codeError.value = ''
  loading.value = true
  waitingForAccept.value = false
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('ConnectByCode', code)
  } catch {
    loading.value = false
    codeError.value = t('home.connectionError')
  }
}

async function cancelConnectionRequest() {
  clearConnectionTimeout()
  waitingForAccept.value = false
  loading.value = false
  try {
    await ensureConnected(matchingHub)
    await matchingHub.invoke('CancelConnectionRequest')
  } catch {}
}

function goBack() {
  router.replace('/home')
}
</script>

<template>
  <div class="saved-codes-page page auth-pattern">
    <LoaderOverlay :show="loading" :text="waitingForAccept ? t('home.waitingForAccept') : t('home.connecting')" />
    <Transition name="fade">
      <div v-if="waitingForAccept" class="cancel-wait-wrap">
        <button class="cancel-wait-btn" @click="cancelConnectionRequest">
          <PhoneOff :size="18" />
          <span>{{ t('home.cancelRequest') }}</span>
        </button>
      </div>
    </Transition>

    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('home.savedCodes') }}</span>
      <div style="width: 40px"></div>
    </header>

    <div class="scroll-area">
      <!-- نموذج إضافة كود - مرتب ومنظم -->
      <section class="add-section glass-card">
        <h3 class="section-title">
          <BookmarkPlus :size="20" />
          {{ t('home.addCode') }}
        </h3>
        <p class="section-desc">{{ t('savedCodes.addCodeDesc') }}</p>
        <div class="add-form">
          <input
            v-model="newCode"
            class="code-input"
            :placeholder="t('home.enterUserCode')"
            maxlength="7"
            @input="newCode = newCode.toUpperCase(); addCodeError = ''"
          />
          <input
            v-model="newLabel"
            class="label-input"
            :placeholder="t('home.codeLabelPlaceholder')"
            maxlength="50"
          />
          <div v-if="addCodeError" class="error-msg">
            <AlertCircle :size="16" />
            {{ addCodeError }}
          </div>
          <button
            class="add-btn"
            :disabled="addCodeSubmitting || !newCode.trim()"
            @click="addSavedCode"
          >
            {{ addCodeSubmitting ? t('common.loading') : t('home.addCode') }}
          </button>
        </div>
      </section>

      <!-- قائمة الأكواد المحفوظة -->
      <section class="list-section">
        <h3 class="section-title">{{ t('savedCodes.yourCodes') }}</h3>
        <div v-if="savedCodesLoading" class="loading-msg">{{ t('common.loading') }}</div>
        <div v-else-if="!savedCodes.length" class="empty-state">
          <BookmarkPlus :size="40" class="empty-icon" />
          <p>{{ t('home.noSavedCodes') }}</p>
          <span class="empty-hint">{{ t('savedCodes.addFirstHint') }}</span>
        </div>
        <div v-else class="codes-list">
          <div v-if="codeError" class="error-msg mb-3">
            <AlertCircle :size="16" />
            {{ codeError }}
          </div>
          <div
            v-for="item in savedCodes"
            :key="item.code"
            class="code-item glass-card"
          >
            <div class="code-item-main" @click="connectBySavedCode(item.code)">
              <span class="code-value">{{ item.code }}</span>
              <span v-if="item.label" class="code-label">{{ item.label }}</span>
            </div>
            <div class="code-item-actions">
              <button
                class="connect-btn"
                :aria-label="t('home.connect')"
                @click="connectBySavedCode(item.code)"
              >
                <PhoneCall :size="18" stroke-width="2" />
              </button>
              <button
                class="delete-btn"
                :aria-label="t('common.delete')"
                @click="removeSavedCode(item.code)"
              >
                <Trash2 :size="16" stroke-width="2" />
              </button>
            </div>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.saved-codes-page {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  padding-bottom: var(--safe-bottom);
}

.top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: calc(var(--safe-top) + 12px) var(--spacing) 12px;
  flex-shrink: 0;
}

.back-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  min-width: 40px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.back-btn:active { background: var(--bg-card-hover); }

.top-title {
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
}

.scroll-area {
  flex: 1;
  overflow-y: auto;
  padding: var(--spacing);
  -webkit-overflow-scrolling: touch;
}

.add-section {
  padding: 20px;
  margin-bottom: 24px;
  border: 1px solid var(--border);
  border-radius: 16px;
}

.section-title {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
  margin: 0 0 8px;
}

.section-desc {
  font-size: 13px;
  color: var(--text-muted);
  margin: 0 0 16px;
  line-height: 1.4;
}

.add-form {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.code-input,
.label-input {
  width: 100%;
  padding: 14px 16px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: 12px;
  color: var(--text-primary);
  font-size: 16px;
  font-family: 'Cairo', sans-serif;
  outline: none;
  -webkit-appearance: none;
  appearance: none;
}
.code-input { letter-spacing: 2px; text-align: center; }
.code-input::placeholder,
.label-input::placeholder { color: var(--text-muted); }

.error-msg {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: var(--danger);
}

.add-btn {
  padding: 14px 20px;
  background: linear-gradient(135deg, rgba(255, 215, 0, 0.25), rgba(255, 165, 0, 0.2));
  border: 1px solid rgba(255, 215, 0, 0.5);
  border-radius: 12px;
  color: #E6B800;
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: opacity 0.2s;
}
.add-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.add-btn:active:not(:disabled) { opacity: 0.9; }

.list-section { margin-bottom: 24px; }
.list-section .section-title { margin-bottom: 12px; }

.loading-msg {
  font-size: 14px;
  color: var(--text-muted);
  padding: 24px;
  text-align: center;
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 32px 24px;
  background: var(--bg-card);
  border: 1px dashed var(--border);
  border-radius: 16px;
  color: var(--text-muted);
  text-align: center;
}
.empty-icon { opacity: 0.4; margin-bottom: 12px; }
.empty-state p { margin: 0 0 4px; font-weight: 500; }
.empty-hint { font-size: 13px; opacity: 0.8; }

.codes-list { display: flex; flex-direction: column; gap: 10px; }

.code-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 14px 16px;
  border: 1px solid var(--border);
  border-radius: 14px;
}

.code-item-main {
  flex: 1;
  min-width: 0;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.code-item-main:active { opacity: 0.9; }

.code-value {
  font-size: 16px;
  font-weight: 700;
  letter-spacing: 1px;
  color: var(--primary);
  display: block;
}

.code-label {
  font-size: 13px;
  color: var(--text-secondary);
  display: block;
  margin-top: 2px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.code-item-actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}

.connect-btn,
.delete-btn {
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 10px;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.connect-btn {
  background: rgba(108, 99, 255, 0.2);
  border: 1px solid rgba(108, 99, 255, 0.3);
  color: var(--primary);
}
.connect-btn:active { opacity: 0.8; }

.delete-btn {
  background: rgba(255, 101, 132, 0.15);
  border: 1px solid rgba(255, 101, 132, 0.25);
  color: var(--danger);
}
.delete-btn:active { opacity: 0.8; }

.cancel-wait-wrap {
  position: fixed;
  bottom: calc(48px + var(--safe-bottom));
  left: 50%;
  transform: translateX(-50%);
  z-index: 10001;
}
.cancel-wait-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 12px 24px;
  background: rgba(0, 0, 0, 0.7);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 24px;
  color: white;
  font-size: 14px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}
.cancel-wait-btn:active { opacity: 0.9; }
.mb-3 { margin-bottom: 12px; }
</style>
