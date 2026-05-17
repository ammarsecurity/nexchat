<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, UserPlus, Phone, Globe, AlertCircle, MoreVertical, UserMinus, Ban, Loader2, Search } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import { countries } from '../data/countries'
import { validatePhone, getPhoneErrorMessage } from '../utils/phoneValidation'
import { createPrivateConversationOrRequest, goToMessageRequestsOutgoingNotice } from '../utils/conversationOrMessageRequest'
import { useMessageRequestsStore } from '../stores/messageRequests'
import { useUserAvatarOverridesStore } from '../stores/userAvatarOverrides'

const msgReqStore = useMessageRequestsStore()
const avatarOverrides = useUserAvatarOverridesStore()

const router = useRouter()
const { t } = useI18n()

const contacts = ref([])
const searchQuery = ref('')
const showAddModal = ref(false)
const addCountry = ref(null)
const addPhone = ref('')
const addLoading = ref(false)
const addError = ref('')
const needPhone = ref(false)
const contextContact = ref(null)
const showContextMenu = ref(false)
/** جهة الاتصال التي تُفتح محادثتها حالياً (لودر على البطاقة) */
const openingContactId = ref(null)

const countryCode = computed(() => {
  const c = countries.find(x => x.code === addCountry.value)
  return c?.dialCode ?? ''
})

const filteredContacts = computed(() => {
  const q = searchQuery.value.trim()
  if (!q) return contacts.value
  const lower = q.toLowerCase()
  return contacts.value.filter((c) => {
    const name = (c.name ?? c.Name ?? '').toLowerCase()
    const phone = String(c.phoneNumber ?? c.PhoneNumber ?? '')
    return name.includes(lower) || phone.includes(q)
  })
})

function contactPhone(c) {
  const phone = c.phoneNumber ?? c.PhoneNumber
  if (!phone || typeof phone !== 'string') return t('profile.phoneNotSet')
  const trimmed = phone.trim()
  if (!trimmed) return t('profile.phoneNotSet')
  return trimmed.startsWith('+') ? trimmed : `+${trimmed.replace(/\D/g, '')}`
}

function contactAvatar(c) {
  return avatarOverrides.avatarFor(c.contactUserId) ?? c.avatar
}

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
  if (openingContactId.value) return
  openingContactId.value = contact.contactUserId
  try {
    const r = await createPrivateConversationOrRequest(contact.contactUserId)
    if (r.kind === 'conversation') {
      router.push(`/conversation/${r.conversationId}`)
    } else {
      await msgReqStore.fetchPendingCount()
      goToMessageRequestsOutgoingNotice(router)
    }
  } catch (e) {
    window.alert(e.userMessage ?? e.response?.data?.message ?? t('common.error'))
  } finally {
    openingContactId.value = null
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

    <div v-if="contacts.length" class="search-wrap">
      <div class="search-input-wrap">
        <Search :size="16" class="search-icon" />
        <input
          v-model="searchQuery"
          type="search"
          class="search-input"
          :placeholder="t('contacts.searchPlaceholder')"
          inputmode="search"
          autocomplete="off"
        />
      </div>
    </div>

    <div class="scroll-area">
      <div v-if="!contacts.length && !needPhone" class="empty-state">
        <UserPlus :size="48" class="empty-icon" />
        <p>{{ t('contacts.empty') }}</p>
        <p class="empty-hint">{{ t('contacts.addFirst') }}</p>
        <button class="btn-gradient" @click="openAddModal">{{ t('contacts.addContact') }}</button>
      </div>
      <div v-else-if="!filteredContacts.length" class="empty-state">
        <p>{{ t('contacts.noSearchResults') }}</p>
      </div>
      <div v-else class="contacts-list">
        <div
          v-for="c in filteredContacts"
          :key="c.id"
          class="contact-item glass-card"
          :class="{ 'is-opening': openingContactId === c.contactUserId }"
          @click="startConversation(c)"
          @contextmenu.prevent="openContextMenu(c, $event)"
        >
          <div
            v-if="openingContactId === c.contactUserId"
            class="item-opening-overlay"
            aria-hidden="true"
          >
            <Loader2 class="item-opening-spinner" :size="22" />
          </div>
          <div class="item-avatar" :style="{ background: contactAvatar(c) && !isImageAvatar(contactAvatar(c)) ? 'var(--primary)' : 'var(--bg-elevated)' }">
            <img v-if="contactAvatar(c) && isImageAvatar(contactAvatar(c))" :src="ensureAbsoluteUrl(contactAvatar(c))" class="avatar-img" referrerpolicy="no-referrer" />
            <span v-else>{{ c.name?.[0]?.toUpperCase() || '?' }}</span>
          </div>
          <div class="item-content">
            <span class="item-name">{{ c.name }}</span>
            <span class="item-meta" dir="ltr">{{ contactPhone(c) }}</span>
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
                  <UserMinus :size="18" />
                  <span>{{ t('contacts.removeFriend') }}</span>
                </button>
                <button class="context-sheet-btn danger" @click="blockContact(contextContact)">
                  <Ban :size="18" />
                  <span>{{ t('contacts.block') }}</span>
                </button>
              </div>
              <button class="context-sheet-cancel" @click="showContextMenu = false">{{ t('common.cancel') }}</button>
            </div>
        </div>
      </Transition>
      <Transition name="sheet">
        <div v-if="showAddModal" class="add-phone-overlay" @click.self="showAddModal = false">
          <div class="add-phone-sheet" @click.stop>
            <div class="context-sheet-handle" aria-hidden="true"></div>
            <h3 class="add-sheet-title">{{ t('contacts.addByPhone') }}</h3>
            <div class="add-sheet-body">
          <div class="field">
            <label class="field-label" for="add-country-select">
              <Globe :size="16" />
              {{ t('completeProfile.country') }}
            </label>
            <select
              id="add-country-select"
              v-model="addCountry"
              class="input-field select-field"
              :aria-label="t('completeProfile.country')"
            >
              <option v-for="c in countries" :key="c.code" :value="c.code">
                {{ c.name }} (+{{ c.dialCode }})
              </option>
            </select>
          </div>
          <div class="field">
            <label class="field-label" for="add-phone-input">
              <Phone :size="16" />
              {{ t('completeProfile.phone') }}
            </label>
            <div class="phone-input-wrap">
              <span class="dial-prefix" dir="ltr">+{{ countryCode || '964' }}</span>
              <input
                id="add-phone-input"
                v-model="addPhone"
                type="tel"
                class="input-field phone-input"
                :placeholder="t('contacts.phonePlaceholder')"
                inputmode="numeric"
                maxlength="15"
                autocomplete="tel"
                enterkeyhint="done"
              />
            </div>
          </div>
              <div v-if="addError" class="error-toast">
                <AlertCircle :size="16" stroke-width="2" />
                <span>{{ addError }}</span>
              </div>
            </div>
            <div class="add-sheet-footer">
              <button
                type="button"
                class="btn-gradient add-submit-btn"
                :disabled="addLoading"
                @click="addContact"
              >
                {{ addLoading ? t('common.loading') : t('contacts.addContact') }}
              </button>
              <button type="button" class="add-cancel-btn" @click="showAddModal = false">
                {{ t('common.cancel') }}
              </button>
            </div>
          </div>
        </div>
      </Transition>
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

.search-wrap {
  flex-shrink: 0;
  padding: 0 var(--spacing) 10px;
}

.search-input-wrap {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 14px;
  min-height: 40px;
  border-radius: 20px;
  background: var(--bg-card);
  border: 1px solid var(--border);
}

.search-icon {
  color: var(--text-muted);
  flex-shrink: 0;
}

.search-input {
  flex: 1;
  min-width: 0;
  padding: 10px 0;
  border: none;
  background: transparent;
  color: var(--text-primary);
  font-size: 14px;
  font-family: 'Cairo', sans-serif;
}

.search-input:focus {
  outline: none;
}

.search-input::placeholder {
  color: var(--text-muted);
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
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  cursor: pointer;
  border-radius: 12px;
}

.contact-item.is-opening {
  pointer-events: none;
}

.item-opening-overlay {
  position: absolute;
  inset: 0;
  z-index: 2;
  border-radius: 12px;
  background: rgba(0, 0, 0, 0.08);
  display: flex;
  align-items: center;
  justify-content: center;
  backdrop-filter: blur(1px);
}

.item-opening-spinner {
  animation: contact-open-spin 0.65s linear infinite;
  color: var(--primary);
}

@keyframes contact-open-spin {
  to {
    transform: rotate(360deg);
  }
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
.item-meta {
  font-size: 13px;
  color: var(--text-secondary);
  unicode-bidi: plaintext;
}
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
  padding: 8px var(--spacing) calc(var(--spacing) + var(--safe-bottom));
  background: var(--bg-card);
  border-radius: 20px 20px 0 0;
  box-shadow: 0 -4px 24px rgba(0,0,0,0.15);
}

.context-sheet-handle {
  width: 36px;
  height: 4px;
  margin: 0 auto 10px;
  background: var(--text-tertiary);
  border-radius: 2px;
  opacity: 0.5;
}

.context-sheet-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 4px 0 10px;
  border-bottom: 1px solid var(--border);
  margin-bottom: 8px;
}

.context-sheet-avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 16px;
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
  font-size: 15px;
  font-weight: 600;
  line-height: 1.25;
  color: var(--text-primary);
}

.context-sheet-actions {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.context-sheet-btn {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  padding: 10px 14px;
  min-height: 44px;
  border: none;
  border-radius: 12px;
  background: var(--bg-elevated);
  color: var(--text-primary);
  font-size: 15px;
  line-height: 1.25;
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
  margin-top: 8px;
  padding: 10px 14px;
  min-height: 44px;
  border: none;
  border-radius: 12px;
  background: var(--bg-elevated);
  color: var(--text-secondary);
  font-size: 15px;
  line-height: 1.25;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}

.context-sheet-cancel:active {
  background: var(--bg-card-hover);
}

.sheet-enter-active, .sheet-leave-active { transition: opacity 0.25s ease; }
.sheet-enter-active .context-sheet,
.sheet-leave-active .context-sheet,
.sheet-enter-active .add-phone-sheet,
.sheet-leave-active .add-phone-sheet {
  transition: transform 0.28s cubic-bezier(0.32, 0.72, 0, 1);
}
.sheet-enter-from, .sheet-leave-to { opacity: 0; }
.sheet-enter-from .context-sheet,
.sheet-leave-to .context-sheet,
.sheet-enter-from .add-phone-sheet,
.sheet-leave-to .add-phone-sheet {
  transform: translateY(100%);
}

.add-phone-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.45);
  z-index: 1000;
  display: flex;
  align-items: flex-end;
  justify-content: center;
}

.add-phone-sheet {
  width: 100%;
  max-width: 480px;
  max-height: min(88vh, 520px);
  display: flex;
  flex-direction: column;
  background: var(--bg-card);
  border-radius: 20px 20px 0 0;
  box-shadow: 0 -8px 32px rgba(0, 0, 0, 0.2);
  font-family: 'Cairo', sans-serif;
  padding: 8px var(--spacing) calc(var(--spacing) + var(--safe-bottom));
}

.add-sheet-title {
  margin: 0 0 12px;
  padding: 0 4px;
  font-size: 17px;
  font-weight: 700;
  text-align: center;
  color: var(--text-primary);
}

.add-sheet-body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  padding: 0 2px 8px;
}

.add-sheet-footer {
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding-top: 12px;
  border-top: 1px solid var(--border);
}

.add-submit-btn {
  width: 100%;
  min-height: var(--touch-min, 48px);
}

.add-cancel-btn {
  width: 100%;
  min-height: 44px;
  padding: 10px 14px;
  border: none;
  border-radius: 12px;
  background: var(--bg-elevated);
  color: var(--text-secondary);
  font-family: 'Cairo', sans-serif;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
}

.add-cancel-btn:active {
  background: var(--bg-card-hover);
}

.field { margin-bottom: 14px; }
.field:last-of-type { margin-bottom: 0; }

.field-label {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
  font-size: 13px;
  font-weight: 600;
  color: var(--text-secondary);
}

.select-field {
  appearance: none;
  -webkit-appearance: none;
  cursor: pointer;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 24 24' fill='none' stroke='%23A0A0B8' stroke-width='2'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: left 14px center;
  padding-left: 44px;
  padding-right: 16px;
  text-overflow: ellipsis;
}

[dir='rtl'] .select-field {
  background-position: right 14px center;
  padding-left: 16px;
  padding-right: 44px;
}

.phone-input-wrap {
  display: flex;
  align-items: stretch;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm, 12px);
  background: var(--bg-elevated);
  overflow: hidden;
}

.dial-prefix {
  display: flex;
  align-items: center;
  padding: 0 14px;
  background: rgba(108, 99, 255, 0.1);
  color: var(--primary);
  font-size: 15px;
  font-weight: 600;
  flex-shrink: 0;
}

.phone-input {
  flex: 1;
  min-width: 0;
  border: none !important;
  border-radius: 0 !important;
  background: transparent;
}

.error-toast {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  margin-top: 12px;
  padding: 10px 12px;
  background: rgba(244, 67, 54, 0.12);
  border-radius: 10px;
  font-size: 13px;
  line-height: 1.4;
  color: #f44336;
}

.error-toast svg {
  flex-shrink: 0;
  margin-top: 1px;
}
</style>
