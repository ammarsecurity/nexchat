<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, UserPlus, Phone, Globe, AlertCircle, MoreVertical, UserMinus, Ban } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { countries } from '../data/countries'
import { validatePhone, getPhoneErrorMessage } from '../utils/phoneValidation'

const router = useRouter()
const { t } = useI18n()

const contacts = ref([])
const showAddModal = ref(false)
const addCountry = ref(null)
const addPhone = ref('')
const addLoading = ref(false)
const addError = ref('')
const needPhone = ref(false)
const contextContact = ref(null)
const showContextMenu = ref(false)

const countryCode = computed(() => {
  const c = countries.find(x => x.code === addCountry.value)
  return c?.dialCode ?? ''
})

const filteredContacts = computed(() => contacts.value)

async function fetchContacts() {
  needPhone.value = false
  try {
    const { data } = await api.get('/contacts', { skipGlobalLoader: true })
    contacts.value = data ?? []
  } catch (e) {
    if (e.response?.status === 400 && e.response?.data?.message?.includes('رقم الهاتف')) {
      needPhone.value = true
    }
    contacts.value = []
  }
}

async function addContact() {
  const code = countryCode.value || '964'
  const result = validatePhone(code, addPhone.value, t)
  if (!result.valid) {
    addError.value = getPhoneErrorMessage(result, t)
    return
  }
  addLoading.value = true
  addError.value = ''
  try {
    await api.post('/contacts', {
      countryCode: code,
      phoneNumber: result.normalized
    })
    showAddModal.value = false
    addPhone.value = ''
    addCountry.value = null
    await fetchContacts()
  } catch (e) {
    addError.value = e.response?.data?.message ?? e.userMessage ?? t('common.error')
  } finally {
    addLoading.value = false
  }
}

async function removeContact(contactUserId) {
  showContextMenu.value = false
  try {
    await api.delete(`/contacts/${contactUserId}`)
    contacts.value = contacts.value.filter(c => c.contactUserId !== contactUserId)
  } catch {}
}

async function blockContact(contact) {
  showContextMenu.value = false
  try {
    await api.post(`/blocks/${contact.contactUserId}`)
    contacts.value = contacts.value.filter(c => c.contactUserId !== contact.contactUserId)
  } catch {}
}

function openContextMenu(contact, e) {
  e?.stopPropagation()
  contextContact.value = contact
  showContextMenu.value = true
}

async function startConversation(contact) {
  try {
    const { data } = await api.post('/conversations', { contactUserId: contact.contactUserId })
    router.push(`/conversation/${data.id}`)
  } catch (e) {
    console.error(e)
  }
}

function openAddModal() {
  addError.value = ''
  addPhone.value = ''
  addCountry.value = 'IQ'
  showAddModal.value = true
}

const isImageAvatar = (v) => v && (v.startsWith('http') || v.startsWith('/'))

onMounted(fetchContacts)

function goBack() {
  if (window.history.length > 2) {
    router.back()
  } else {
    router.replace('/conversations')
  }
}
</script>

<template>
  <div class="contacts page auth-pattern">
    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('contacts.title') }}</span>
      <button class="add-btn" @click="openAddModal" :aria-label="t('contacts.addContact')">
        <UserPlus :size="22" />
      </button>
    </header>

    <div v-if="needPhone" class="need-phone-banner">
      <AlertCircle :size="20" />
      <span>{{ t('contacts.needPhone') }}</span>
      <button class="link-btn" @click="router.push('/complete-profile')">{{ t('completeProfile.completeNow') }}</button>
    </div>

    <div class="scroll-area">
      <div v-if="!contacts.length && !needPhone" class="empty-state">
        <UserPlus :size="48" class="empty-icon" />
        <p>{{ t('contacts.empty') }}</p>
        <p class="empty-hint">{{ t('contacts.addFirst') }}</p>
        <button class="btn-gradient" @click="openAddModal">{{ t('contacts.addContact') }}</button>
      </div>
      <div v-else class="contacts-list">
        <div
          v-for="c in filteredContacts"
          :key="c.id"
          class="contact-item glass-card"
          @click="startConversation(c)"
          @contextmenu.prevent="openContextMenu(c, $event)"
        >
          <div class="item-avatar" :style="{ background: c.avatar && !isImageAvatar(c.avatar) ? 'var(--primary)' : 'var(--bg-elevated)' }">
            <img v-if="c.avatar && isImageAvatar(c.avatar)" :src="ensureAbsoluteUrl(c.avatar)" class="avatar-img" referrerpolicy="no-referrer" />
            <span v-else>{{ c.name?.[0]?.toUpperCase() || '?' }}</span>
          </div>
          <div class="item-content">
            <span class="item-name">{{ c.name }}</span>
            <span class="item-meta">{{ c.uniqueCode }}</span>
          </div>
          <button
            class="context-btn"
            @click.stop="openContextMenu(c, $event)"
            :aria-label="t('common.cancel')"
          >
            <MoreVertical :size="18" />
          </button>
          <ChevronRight :size="20" class="item-arrow" />
        </div>
      </div>
    </div>

    <Teleport to="body">
      <Transition name="sheet">
        <div v-if="showContextMenu && contextContact" class="context-overlay" @click="showContextMenu = false">
          <div class="context-sheet" @click.stop>
              <div class="context-sheet-handle"></div>
              <div class="context-sheet-header">
                <div class="context-sheet-avatar" :style="{ background: contextContact.avatar && !isImageAvatar(contextContact.avatar) ? 'var(--primary)' : 'var(--bg-elevated)' }">
                  <img v-if="contextContact.avatar && isImageAvatar(contextContact.avatar)" :src="ensureAbsoluteUrl(contextContact.avatar)" class="avatar-img" referrerpolicy="no-referrer" />
                  <span v-else>{{ contextContact.name?.[0]?.toUpperCase() || '?' }}</span>
                </div>
                <span class="context-sheet-name">{{ contextContact.name }}</span>
              </div>
              <div class="context-sheet-actions">
                <button class="context-sheet-btn" @click="removeContact(contextContact.contactUserId)">
                  <UserMinus :size="20" />
                  <span>{{ t('contacts.removeFriend') }}</span>
                </button>
                <button class="context-sheet-btn danger" @click="blockContact(contextContact)">
                  <Ban :size="20" />
                  <span>{{ t('contacts.block') }}</span>
                </button>
              </div>
              <button class="context-sheet-cancel" @click="showContextMenu = false">{{ t('common.cancel') }}</button>
            </div>
        </div>
      </Transition>
      <div v-if="showAddModal" class="modal-overlay" @click.self="showAddModal = false">
        <div class="modal-card glass-card">
          <h3 class="modal-title">{{ t('contacts.addByPhone') }}</h3>
          <div class="field">
            <label class="field-label">
              <Globe :size="16" />
              {{ t('completeProfile.country') }}
            </label>
            <select v-model="addCountry" class="input-field">
              <option v-for="c in countries" :key="c.code" :value="c.code">{{ c.name }} (+{{ c.dialCode }})</option>
            </select>
          </div>
          <div class="field">
            <label class="field-label">
              <Phone :size="16" />
              {{ t('completeProfile.phone') }}
            </label>
            <div class="phone-input-wrap">
              <span class="dial-prefix">+{{ countryCode || '964' }}</span>
              <input
                v-model="addPhone"
                type="tel"
                class="input-field phone-input"
                :placeholder="t('contacts.phonePlaceholder')"
                inputmode="numeric"
                maxlength="15"
              />
            </div>
          </div>
          <div v-if="addError" class="error-toast">{{ addError }}</div>
          <div class="modal-actions">
            <button class="btn-outline" @click="showAddModal = false">{{ t('common.cancel') }}</button>
            <button class="btn-gradient" :disabled="addLoading" @click="addContact">
              {{ addLoading ? t('common.loading') : t('contacts.addContact') }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.contacts {
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

.back-btn, .add-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  background: var(--bg-card);
  border: none;
  border-radius: 12px;
  color: var(--text-primary);
  cursor: pointer;
}

.add-btn { color: var(--primary); }

.need-phone-banner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding: 12px var(--spacing);
  background: rgba(255, 193, 7, 0.15);
  color: var(--text-primary);
  font-size: 14px;
}

.link-btn {
  background: none;
  border: none;
  color: var(--primary);
  text-decoration: underline;
  cursor: pointer;
}

.scroll-area {
  flex: 1;
  overflow-y: auto;
  padding: var(--spacing);
}

.empty-state {
  text-align: center;
  padding: 48px 24px;
}

.empty-state .empty-icon {
  opacity: 0.5;
  margin-bottom: 16px;
}

.empty-hint {
  font-size: 14px;
  color: var(--text-secondary);
  margin-bottom: 24px;
}

.contacts-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.contact-item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  cursor: pointer;
  border-radius: 12px;
}

.item-avatar {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 18px;
  color: white;
  flex-shrink: 0;
}

.avatar-img {
  width: 100%;
  height: 100%;
  border-radius: 50%;
  object-fit: cover;
}

.item-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.item-name { font-weight: 600; }
.item-meta { font-size: 13px; color: var(--text-secondary); }
.item-arrow { color: var(--text-tertiary); flex-shrink: 0; }

.context-btn {
  background: none;
  border: none;
  color: var(--text-tertiary);
  padding: 4px;
  cursor: pointer;
  flex-shrink: 0;
}

.context-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.4);
  z-index: 1000;
  display: flex;
  align-items: flex-end;
  justify-content: center;
}

.context-sheet {
  width: 100%;
  max-width: 400px;
  padding: 12px var(--spacing) calc(var(--spacing) + var(--safe-bottom));
  background: var(--bg-card);
  border-radius: 20px 20px 0 0;
  box-shadow: 0 -4px 24px rgba(0,0,0,0.15);
}

.context-sheet-handle {
  width: 36px;
  height: 4px;
  margin: 0 auto 16px;
  background: var(--text-tertiary);
  border-radius: 2px;
  opacity: 0.5;
}

.context-sheet-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 0 20px;
  border-bottom: 1px solid var(--border);
  margin-bottom: 12px;
}

.context-sheet-avatar {
  width: 48px;
  height: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 18px;
  color: white;
  flex-shrink: 0;
}

.context-sheet-avatar .avatar-img {
  width: 100%;
  height: 100%;
  border-radius: 50%;
  object-fit: cover;
}

.context-sheet-name {
  font-size: 17px;
  font-weight: 600;
  color: var(--text-primary);
}

.context-sheet-actions {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.context-sheet-btn {
  display: flex;
  align-items: center;
  gap: 14px;
  width: 100%;
  padding: 14px 16px;
  border: none;
  border-radius: 12px;
  background: var(--bg-elevated);
  color: var(--text-primary);
  font-size: 15px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  text-align: start;
  transition: background 0.2s;
}

.context-sheet-btn:active {
  background: var(--bg-card-hover);
}

.context-sheet-btn.danger {
  background: rgba(244, 67, 54, 0.12);
  color: #f44336;
}

.context-sheet-btn.danger:active {
  background: rgba(244, 67, 54, 0.2);
}

.context-sheet-cancel {
  width: 100%;
  margin-top: 12px;
  padding: 14px;
  border: none;
  border-radius: 12px;
  background: var(--bg-elevated);
  color: var(--text-secondary);
  font-size: 15px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}

.context-sheet-cancel:active {
  background: var(--bg-card-hover);
}

.sheet-enter-active, .sheet-leave-active { transition: opacity 0.25s ease; }
.sheet-enter-active .context-sheet, .sheet-leave-active .context-sheet { transition: transform 0.25s ease; }
.sheet-enter-from, .sheet-leave-to { opacity: 0; }
.sheet-enter-from .context-sheet, .sheet-leave-to .context-sheet { transform: translateY(100%); }

.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: var(--spacing);
}

.modal-card {
  width: 100%;
  max-width: 360px;
  padding: 24px;
  font-family: 'Cairo', sans-serif;
}

.modal-title {
  margin: 0 0 20px;
  font-size: 18px;
  font-weight: 600;
}

.field { margin-bottom: 16px; }
.field-label {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 6px;
  font-size: 14px;
}

.phone-input-wrap {
  display: flex;
  align-items: center;
  border: 1px solid var(--border);
  border-radius: 12px;
  overflow: hidden;
}

.dial-prefix {
  padding: 12px 12px;
  background: var(--bg-elevated);
  font-size: 14px;
}

.phone-input {
  flex: 1;
  border: none;
  padding: 12px;
}

.error-toast {
  padding: 10px;
  background: rgba(244,67,54,0.15);
  border-radius: 8px;
  font-size: 13px;
  margin-bottom: 16px;
}

.modal-actions {
  display: flex;
  gap: 10px;
  margin-top: 20px;
}

.btn-outline {
  flex: 1;
  padding: 10px 14px;
  background: transparent;
  border: 1px solid var(--border);
  border-radius: 10px;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
}

.btn-gradient {
  flex: 1;
  padding: 10px 14px;
  background: linear-gradient(135deg, var(--primary), var(--primary-dark, var(--primary)));
  border: none;
  border-radius: 10px;
  color: white;
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
}

.btn-gradient:disabled { opacity: 0.6; cursor: not-allowed; }
</style>
