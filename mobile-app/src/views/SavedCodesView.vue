<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, BookmarkPlus, Trash2, PhoneCall, PhoneOff, AlertCircle, X } from 'lucide-vue-next'
import { useAuthStore } from '../stores/auth'
import { useI18n } from 'vue-i18n'
import { useLocaleStore } from '../stores/locale'
import LoaderOverlay from '../components/LoaderOverlay.vue'
import { matchingHub, startHub, ensureConnected } from '../services/signalr'
import api from '../services/api'

const router = useRouter()
const auth = useAuthStore()
const { t } = useI18n()
const localeStore = useLocaleStore()

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
const showAddModal = ref(false)

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
  await fetchSavedCodes()
})

onUnmounted(() => {
  clearConnectionTimeout()
  matchingHub.off('ConnectionRequestSent')
  matchingHub.off('ConnectionDeclined')
  matchingHub.off('CodeError')
  matchingHub.off('ConnectionCancelled')
})

async function fetchSavedCodes() {
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

function openAddModal() {
  addCodeError.value = ''
  showAddModal.value = true
}

function closeAddModal() {
  showAddModal.value = false
  addCodeError.value = ''
  newCode.value = ''
  newLabel.value = ''
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
    await fetchSavedCodes()
    closeAddModal()
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
        <ChevronRight :size="18" />
      </button>
      <span class="top-title">{{ t('home.savedCodes') }}</span>
      <button
        type="button"
        class="header-add-btn"
        :aria-label="t('home.addCode')"
        :title="t('home.addCode')"
        @click="openAddModal"
      >
        <BookmarkPlus :size="18" stroke-width="2" />
      </button>
    </header>

    <Teleport to="body">
      <Transition name="modal-fade">
        <div
          v-if="showAddModal"
          class="add-modal-overlay"
          role="presentation"
          @click.self="closeAddModal"
        >
          <div
            class="add-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="saved-code-add-modal-title"
            @click.stop
          >
            <div class="add-modal-header">
              <h2 id="saved-code-add-modal-title" class="add-modal-title">{{ t('savedCodes.addModalTitle') }}</h2>
              <button type="button" class="add-modal-close" :aria-label="t('common.cancel')" @click="closeAddModal">
                <X :size="20" stroke-width="2" />
              </button>
            </div>
            <p class="add-modal-desc">{{ t('savedCodes.addCodeDesc') }}</p>
            <div class="add-form">
              <input
                v-model="newCode"
                class="code-input"
                :placeholder="t('savedCodes.codePlaceholder')"
                maxlength="7"
                autocomplete="off"
                dir="ltr"
                @input="newCode = newCode.toUpperCase(); addCodeError = ''"
              />
              <input
                v-model="newLabel"
                class="label-input"
                :placeholder="t('savedCodes.labelPlaceholder')"
                maxlength="50"
                autocomplete="off"
                :dir="localeStore.htmlDir"
              />
              <button
                type="button"
                class="add-btn"
                :disabled="addCodeSubmitting || !newCode.trim()"
                @click="addSavedCode"
              >
                {{ addCodeSubmitting ? t('common.loading') : t('home.addCode') }}
              </button>
            </div>
            <div v-if="addCodeError" class="error-msg add-modal-error">
              <AlertCircle :size="14" />
              {{ addCodeError }}
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <div class="scroll-area">
      <!-- قائمة الأكواد المحفوظة -->
      <section class="list-section">
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
            class="code-item"
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
                <PhoneCall :size="16" stroke-width="2" />
              </button>
              <button
                class="delete-btn"
                :aria-label="t('common.delete')"
                @click="removeSavedCode(item.code)"
              >
                <Trash2 :size="14" stroke-width="2" />
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
  gap: 8px;
  padding: calc(var(--safe-top) + 8px) 12px 8px;
  flex-shrink: 0;
}

.back-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  min-width: 40px;
  flex-shrink: 0;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.back-btn:active { background: var(--bg-card-hover); }

.header-add-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  min-width: 40px;
  flex-shrink: 0;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--primary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.header-add-btn:active {
  background: var(--bg-card-hover);
}

/* مودال إضافة كود */
.modal-fade-enter-active,
.modal-fade-leave-active {
  transition: opacity 0.2s ease;
}
.modal-fade-enter-from,
.modal-fade-leave-to {
  opacity: 0;
}

.add-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 10050;
  background: rgba(0, 0, 0, 0.55);
  backdrop-filter: blur(5px);
  -webkit-backdrop-filter: blur(5px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: max(16px, env(safe-area-inset-left));
  padding-top: max(16px, env(safe-area-inset-top));
  padding-bottom: max(16px, env(safe-area-inset-bottom));
  box-sizing: border-box;
}

.add-modal {
  width: 100%;
  max-width: 400px;
  max-height: min(90vh, 90dvh);
  overflow-y: auto;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 16px;
  box-shadow: 0 20px 50px rgba(0, 0, 0, 0.4);
  -webkit-overflow-scrolling: touch;
}

.add-modal-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 8px;
}

.add-modal-title {
  margin: 0;
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  line-height: 1.3;
  flex: 1;
  min-width: 0;
}

.add-modal-close {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  flex-shrink: 0;
  padding: 0;
  border: none;
  border-radius: var(--radius-sm);
  background: var(--bg-elevated);
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.add-modal-close:active {
  opacity: 0.85;
}

.add-modal-desc {
  margin: 0 0 14px;
  font-size: 13px;
  line-height: 1.45;
  color: var(--text-secondary);
  font-family: 'Cairo', sans-serif;
}

.add-modal-error {
  margin-top: 10px;
}

.top-title {
  flex: 1;
  min-width: 0;
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
  text-align: center;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  line-height: 1.25;
}

.scroll-area {
  flex: 1;
  overflow-y: auto;
  padding: 12px;
  -webkit-overflow-scrolling: touch;
}

/* نموذج داخل المودال */
.add-form {
  display: flex;
  flex-direction: column;
  gap: 8px;
  align-items: stretch;
  width: 100%;
}

.code-input {
  width: 100%;
  min-width: 0;
  padding: 8px 10px;
  min-height: 40px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: 10px;
  color: var(--text-primary);
  font-size: 13px;
  font-family: 'Cairo', sans-serif;
  letter-spacing: 0.08em;
  text-align: center;
  outline: none;
  -webkit-appearance: none;
  appearance: none;
  box-sizing: border-box;
}

.label-input {
  width: 100%;
  min-width: 0;
  padding: 8px 10px;
  min-height: 40px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: 10px;
  color: var(--text-primary);
  font-size: 13px;
  font-family: 'Cairo', sans-serif;
  outline: none;
  -webkit-appearance: none;
  appearance: none;
  box-sizing: border-box;
}
.code-input::placeholder,
.label-input::placeholder { color: var(--text-muted); }

.add-btn {
  width: 100%;
  padding: 8px 14px;
  min-height: 40px;
  background: var(--primary);
  border: none;
  border-radius: 10px;
  color: white;
  font-size: 13px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: opacity 0.2s;
  box-sizing: border-box;
}
.add-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.add-btn:active:not(:disabled) { opacity: 0.9; }

.error-msg {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: var(--danger);
}

.list-section { margin-bottom: 16px; }

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
  padding: 20px 16px;
  background: var(--bg-card);
  border: 1px dashed var(--border);
  border-radius: 12px;
  color: var(--text-muted);
  text-align: center;
}
.empty-icon { opacity: 0.4; margin-bottom: 8px; }
.empty-state p { margin: 0 0 2px; font-weight: 500; font-size: 14px; }
.empty-hint { font-size: 12px; opacity: 0.8; }

.codes-list { display: flex; flex-direction: column; gap: 8px; }

.code-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 8px 10px;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--bg-card);
}

.code-item-main {
  flex: 1;
  min-width: 0;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}
.code-item-main:active { opacity: 0.9; }

.code-value {
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.06em;
  color: var(--primary);
  display: block;
}

.code-label {
  font-size: 11px;
  color: var(--text-secondary);
  display: block;
  margin-top: 1px;
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
  width: 34px;
  height: 34px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
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

/* شريط العنوان — شاشات ضيقة */
@media (max-width: 420px) {
  .top-bar {
    padding: calc(var(--safe-top) + 6px) 8px 6px;
    gap: 6px;
  }
  .top-title {
    font-size: 14px;
  }
  .top-bar .back-btn {
    width: 32px !important;
    height: 32px !important;
    min-width: 32px !important;
    min-height: 32px !important;
    border-radius: 8px;
  }
  .top-bar .back-btn :deep(svg) {
    width: 16px !important;
    height: 16px !important;
  }
  .top-bar .header-add-btn {
    width: 32px !important;
    height: 32px !important;
    min-width: 32px !important;
    min-height: 32px !important;
    border-radius: 8px;
  }
  .top-bar .header-add-btn :deep(svg) {
    width: 16px !important;
    height: 16px !important;
  }
}

@media (max-width: 320px) {
  .top-bar {
    padding: calc(var(--safe-top) + 4px) 6px 4px;
    gap: 4px;
  }
  .top-title {
    font-size: 13px;
  }
  .top-bar .back-btn {
    width: 30px !important;
    height: 30px !important;
    min-width: 30px !important;
    min-height: 30px !important;
  }
  .top-bar .back-btn :deep(svg) {
    width: 15px !important;
    height: 15px !important;
  }
  .top-bar .header-add-btn {
    width: 30px !important;
    height: 30px !important;
    min-width: 30px !important;
    min-height: 30px !important;
  }
  .top-bar .header-add-btn :deep(svg) {
    width: 15px !important;
    height: 15px !important;
  }
}

/* شاشات أوسع: صف واحد داخل المودال */
@media (min-width: 480px) {
  .scroll-area {
    padding: var(--spacing);
  }
  .add-modal .add-form {
    flex-direction: row;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
  }
  .add-modal .code-input {
    flex: 0 0 7.25rem;
    width: 7.25rem;
    max-width: 8rem;
    font-size: 14px;
    padding: 10px 12px;
    min-height: 44px;
  }
  .add-modal .label-input {
    flex: 1 1 160px;
    width: auto;
    min-width: 140px;
    font-size: 14px;
    padding: 10px 12px;
    min-height: 44px;
  }
  .add-modal .add-btn {
    width: auto;
    flex: 0 0 auto;
    padding: 10px 16px;
    min-height: 44px;
    font-size: 14px;
  }
  .top-title {
    font-size: 16px;
  }
  .code-value {
    font-size: 14px;
  }
  .code-label {
    font-size: 12px;
  }
  .connect-btn,
  .delete-btn {
    width: 36px;
    height: 36px;
  }
}

@media (max-width: 360px) {
  .scroll-area {
    padding: 10px;
  }
  .empty-state {
    padding: 16px 12px;
  }
  .empty-icon :deep(svg) {
    width: 32px;
    height: 32px;
  }
  .empty-state p {
    font-size: 13px;
  }
  .empty-hint {
    font-size: 11px;
  }
}
</style>
