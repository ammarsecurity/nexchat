<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { ChevronRight, Users, Image, UserPlus, Search } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import CachedAvatar from '../components/CachedAvatar.vue'
import LoaderOverlay from '../components/LoaderOverlay.vue'

const router = useRouter()
const { t } = useI18n()

const groupName = ref('')
const groupImageUrl = ref(null)
const uploadingImage = ref(false)
const groupImageInput = ref(null)
const contacts = ref([])
const memberSearchQuery = ref('')
const selectedIds = ref(new Set())
const creating = ref(false)
const error = ref('')
const needPhone = ref(false)

const isImageUrl = (v) => v && (v.startsWith('http') || v.startsWith('/'))

const filteredContacts = computed(() => {
  const q = memberSearchQuery.value.trim().toLowerCase()
  if (!q) return contacts.value
  return contacts.value.filter((c) => {
    const name = (c.name ?? '').toLowerCase()
    const phone = String(c.phone ?? c.Phone ?? c.phoneNumber ?? c.PhoneNumber ?? '').toLowerCase()
    const code = String(c.uniqueCode ?? c.UniqueCode ?? '').toLowerCase()
    return name.includes(q) || phone.includes(q) || code.includes(q)
  })
})

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

function toggleContact(contactUserId) {
  const id = String(contactUserId)
  if (selectedIds.value.has(id)) {
    const next = new Set(selectedIds.value)
    next.delete(id)
    selectedIds.value = next
  } else {
    selectedIds.value = new Set([...selectedIds.value, id])
  }
}

function isSelected(contactUserId) {
  return selectedIds.value.has(String(contactUserId))
}

async function onGroupImageChange(e) {
  const file = e.target?.files?.[0]
  if (!file) return
  if (!file.type.startsWith('image/')) {
    error.value = t('settings.maxSize')
    return
  }
  uploadingImage.value = true
  error.value = ''
  try {
    const formData = new FormData()
    formData.append('file', file)
    const { data } = await api.post('/media/upload', formData, { timeout: 60000 })
    const url = data?.url
    if (url) groupImageUrl.value = url
  } catch (err) {
    error.value = err?.response?.data?.message ?? err?.userMessage ?? t('common.error')
  } finally {
    uploadingImage.value = false
    if (groupImageInput.value) groupImageInput.value.value = ''
  }
}

async function createGroup() {
  const name = groupName.value?.trim()
  if (!name) {
    error.value = t('groups.groupNameRequired')
    return
  }
  const memberUserIds = [...selectedIds.value].map((id) => id)
  if (memberUserIds.length === 0) {
    error.value = t('groups.selectAtLeastOne')
    return
  }
  creating.value = true
  error.value = ''
  try {
    const { data } = await api.post('/conversations/group', {
      name,
      imageUrl: groupImageUrl.value || null,
      memberUserIds
    })
    router.replace(`/conversation/${data.id}`)
  } catch (err) {
    error.value = err?.response?.data?.message ?? err?.userMessage ?? t('common.error')
  } finally {
    creating.value = false
  }
}

function goBack() {
  router.replace('/conversations')
}

onMounted(fetchContacts)
</script>

<template>
  <div class="create-group page auth-pattern">
    <LoaderOverlay :show="creating" :text="t('groups.creating')" />

    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('groups.createTitle') }}</span>
    </header>

    <div v-if="needPhone" class="need-phone-banner">
      <span>{{ t('conversations.needPhone') }}</span>
      <button class="link-btn" @click="router.push('/complete-profile')">{{ t('completeProfile.completeNow') }}</button>
    </div>

    <div class="scroll-area" :class="{ 'scroll-area--fill': contacts.length > 0 }">
      <div class="form-section">
        <label class="label">{{ t('groups.groupName') }}</label>
        <input
          v-model="groupName"
          type="text"
          class="input input--group-name"
          :placeholder="t('groups.groupNamePlaceholder')"
          maxlength="100"
        />
      </div>

      <div class="form-section">
        <label class="label">{{ t('groups.groupPhoto') }}</label>
        <div class="group-photo-wrap">
          <button
            type="button"
            class="group-photo-btn"
            :disabled="uploadingImage"
            @click="groupImageInput?.click()"
          >
            <template v-if="groupImageUrl && isImageUrl(groupImageUrl)">
              <img :src="ensureAbsoluteUrl(groupImageUrl)" class="group-photo-img" referrerpolicy="no-referrer" />
            </template>
            <template v-else>
              <Image :size="40" class="photo-placeholder-icon" />
              <span class="photo-placeholder-text">{{ uploadingImage ? t('settings.uploading') : t('settings.chooseImage') }}</span>
            </template>
          </button>
          <input
            ref="groupImageInput"
            type="file"
            accept="image/jpeg,image/png,image/gif,image/webp"
            class="hidden-input"
            @change="onGroupImageChange"
          />
        </div>
      </div>

      <div class="form-section" :class="{ 'form-section--contacts': contacts.length > 0 }">
        <label class="label">{{ t('groups.selectMembers') }}</label>
        <div v-if="!contacts.length" class="empty-contacts">
          <div class="empty-contacts-icon-wrap">
            <Users :size="40" class="empty-icon" />
          </div>
          <p class="empty-contacts-text">{{ t('contacts.empty') }}</p>
          <p class="empty-contacts-hint">{{ t('contacts.addFirst') }}</p>
          <button type="button" class="btn-add-contact" @click="router.push('/contacts')">
            <UserPlus :size="20" />
            <span>{{ t('contacts.addContact') }}</span>
          </button>
        </div>
        <div v-else class="contacts-block">
          <div class="members-search-wrap">
            <Search :size="16" class="members-search-icon" />
            <input
              v-model="memberSearchQuery"
              type="search"
              class="members-search-input"
              :placeholder="t('groups.searchMembersPlaceholder')"
              enterkeyhint="search"
              autocomplete="off"
            />
          </div>
          <div class="contacts-list">
            <template v-if="filteredContacts.length">
              <div
                v-for="c in filteredContacts"
                :key="c.id ?? c.contactUserId"
                class="contact-row"
                :class="{ selected: isSelected(c.contactUserId) }"
                @click="toggleContact(c.contactUserId)"
              >
                <div class="item-avatar" :style="{ background: c.avatar && !isImageUrl(c.avatar) ? 'var(--primary)' : 'var(--bg-elevated)' }">
                  <CachedAvatar v-if="c.avatar && isImageUrl(c.avatar)" :url="c.avatar" img-class="avatar-img" />
                  <span v-else>{{ (c.name ?? '')?.[0]?.toUpperCase() || '?' }}</span>
                </div>
                <span class="contact-name">{{ c.name ?? '—' }}</span>
                <div class="check-wrap">
                  <span v-if="isSelected(c.contactUserId)" class="check-dot" />
                </div>
              </div>
            </template>
            <p v-else class="contacts-filter-empty">{{ t('groups.noMembersMatch') }}</p>
          </div>
        </div>
      </div>

      <p v-if="error" class="error-text">{{ error }}</p>

      <div class="actions">
        <button
          type="button"
          class="btn-gradient"
          :disabled="creating || !groupName?.trim() || selectedIds.size === 0"
          @click="createGroup"
        >
          {{ t('groups.create') }}
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.create-group {
  background: var(--bg-primary);
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  overflow: hidden;
  padding-bottom: var(--safe-bottom);
  font-family: 'Cairo', sans-serif;
}

.top-bar {
  display: flex;
  align-items: center;
  gap: 12px;
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

.top-title {
  flex: 1;
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
  text-align: center;
}

.need-phone-banner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding: 12px var(--spacing);
  background: rgba(255, 193, 7, 0.15);
  font-size: 14px;
  color: var(--text-primary);
}

.need-phone-banner .link-btn {
  background: none;
  border: none;
  color: var(--primary);
  text-decoration: underline;
  cursor: pointer;
  font-family: 'Cairo', sans-serif;
}


.scroll-area {
  flex: 1;
  min-height: 0;
  padding: 16px var(--spacing);
  -webkit-overflow-scrolling: touch;
}

.scroll-area:not(.scroll-area--fill) {
  overflow-y: auto;
}

/* عند وجود جهات اتصال: تمرير داخلي للقائمة فقط ويبقى زر الإنشاء أسفل الشاشة */
.scroll-area.scroll-area--fill {
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.scroll-area.scroll-area--fill > .form-section:not(.form-section--contacts) {
  flex-shrink: 0;
}

.form-section {
  margin-bottom: 24px;
}

.form-section--contacts {
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  flex-direction: column;
  margin-bottom: 12px;
}

.form-section--contacts .label {
  flex-shrink: 0;
}

.label {
  display: block;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-secondary);
  margin-bottom: 8px;
  font-family: 'Cairo', sans-serif;
}

.input {
  width: 100%;
  padding: 14px 16px;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--bg-card);
  color: var(--text-primary);
  font-size: 16px;
  font-family: 'Cairo', sans-serif;
  outline: none;
  box-sizing: border-box;
}

.input--group-name {
  padding: 10px 14px;
  font-size: 14px;
  border-radius: 10px;
  min-height: 44px;
}

.form-section:first-of-type .label {
  font-size: 13px;
  margin-bottom: 6px;
}

.group-photo-wrap {
  display: flex;
  justify-content: center;
}

.group-photo-btn {
  width: 96px;
  height: 96px;
  border-radius: 50%;
  border: 2px dashed var(--border);
  background: var(--bg-card);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-direction: column;
  gap: 4px;
  cursor: pointer;
  overflow: hidden;
  -webkit-tap-highlight-color: transparent;
}

.group-photo-btn:disabled {
  opacity: 0.7;
  cursor: not-allowed;
}

.group-photo-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.photo-placeholder-icon {
  color: var(--text-muted);
}

.photo-placeholder-text {
  font-size: 12px;
  color: var(--text-muted);
  font-family: 'Cairo', sans-serif;
}

.hidden-input {
  position: absolute;
  width: 0;
  height: 0;
  opacity: 0;
  pointer-events: none;
}

.empty-contacts {
  text-align: center;
  padding: 28px 20px;
  border: 1px dashed var(--border);
  border-radius: 14px;
  background: var(--bg-card);
  color: var(--text-secondary);
}

.empty-contacts-icon-wrap {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 72px;
  height: 72px;
  border-radius: 50%;
  background: rgba(108, 99, 255, 0.1);
  color: var(--primary);
  margin: 0 auto 16px;
}

.empty-contacts .empty-icon {
  opacity: 0.9;
}

.empty-contacts-text {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0 0 6px;
  font-family: 'Cairo', sans-serif;
}

.empty-contacts-hint {
  font-size: 13px;
  color: var(--text-muted);
  margin: 0 0 20px;
  line-height: 1.4;
  font-family: 'Cairo', sans-serif;
}

.btn-add-contact {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 14px 24px;
  background: var(--primary);
  border: none;
  border-radius: 12px;
  color: white;
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  box-shadow: 0 2px 8px rgba(108, 99, 255, 0.3);
}

.btn-add-contact:active {
  opacity: 0.92;
}

.contacts-block {
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.members-search-wrap {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
  padding: 0 10px;
  min-height: 36px;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--bg-card);
}

.members-search-icon {
  color: var(--text-tertiary);
  flex-shrink: 0;
}

.members-search-input {
  flex: 1;
  min-width: 0;
  border: none;
  background: transparent;
  color: var(--text-primary);
  font-size: 13px;
  font-family: 'Cairo', sans-serif;
  outline: none;
  padding: 8px 0;
}

.members-search-input::placeholder {
  color: var(--text-muted);
}

.contacts-list {
  flex: 1 1 auto;
  min-height: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--bg-card);
  overflow-x: hidden;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
}

.contacts-filter-empty {
  margin: 0;
  padding: 20px 14px;
  text-align: center;
  font-size: 13px;
  color: var(--text-muted);
  font-family: 'Cairo', sans-serif;
}

.contact-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.contact-row.selected {
  background: rgba(108, 99, 255, 0.08);
}

.item-avatar {
  width: 44px;
  height: 44px;
  min-width: 44px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 16px;
  color: white;
  overflow: hidden;
}

.avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.contact-name {
  flex: 1;
  font-size: 15px;
  font-weight: 500;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  text-align: start;
}

.check-wrap {
  width: 24px;
  height: 24px;
  border-radius: 50%;
  border: 2px solid var(--border);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.contact-row.selected .check-wrap {
  border-color: var(--primary);
  background: var(--primary);
}

.check-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: white;
}

.error-text {
  color: #f44336;
  font-size: 14px;
  margin: 0 0 16px;
  font-family: 'Cairo', sans-serif;
  flex-shrink: 0;
}

.actions {
  padding-top: 8px;
  flex-shrink: 0;
}

.btn-gradient {
  width: 100%;
  padding: 14px 24px;
  background: var(--primary);
  border: none;
  border-radius: 12px;
  color: white;
  font-weight: 600;
  font-size: 16px;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.btn-gradient:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

@media (max-width: 360px) {
  .input--group-name {
    padding: 8px 12px;
    font-size: 13px;
    min-height: 40px;
  }
  .members-search-wrap {
    min-height: 34px;
    padding: 0 8px;
  }
  .members-search-input {
    font-size: 12px;
    padding: 6px 0;
  }
  .group-photo-btn {
    width: 80px;
    height: 80px;
  }
  .empty-contacts {
    padding: 20px 16px;
  }
  .empty-contacts-icon-wrap {
    width: 60px;
    height: 60px;
    margin-bottom: 12px;
  }
  .empty-contacts-text { font-size: 14px; }
  .empty-contacts-hint { font-size: 12px; }
  .contact-row {
    padding: 10px 12px;
    gap: 10px;
  }
}
</style>
