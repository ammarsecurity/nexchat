<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ChevronRight, UserPlus, LogOut, UserMinus, Users, Pencil, Image } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import api from '../services/api'
import { ensureAbsoluteUrl } from '../utils/imageUrl'
import CachedAvatar from '../components/CachedAvatar.vue'
import { useAuthStore } from '../stores/auth'

const route = useRoute()
const router = useRouter()
const { t } = useI18n()
const auth = useAuthStore()

const conversationId = route.params.conversationId
const groupName = ref('')
const groupImageUrl = ref(null)
const members = ref([])
const loading = ref(true)
const showLeaveConfirm = ref(false)
const leaving = ref(false)
const showAddModal = ref(false)
const contacts = ref([])
const addingUserId = ref(null)
const removingUserId = ref(null)
const showEditName = ref(false)
const editNameValue = ref('')
const savingGroup = ref(false)
const groupImageInput = ref(null)
const uploadingPhoto = ref(false)
const editError = ref('')

const currentUserId = computed(() => auth.user?.id ? String(auth.user.id) : null)
const myMember = computed(() => members.value.find((m) => String(m.userId ?? m.UserId) === currentUserId.value))
const isAdmin = computed(() => (myMember.value?.role ?? myMember.value?.Role) === 'Admin')

const isImageUrl = (v) => v && (v.startsWith('http') || v.startsWith('/'))
const memberIds = computed(() => new Set(members.value.map((m) => String(m.userId ?? m.UserId))))
const contactsNotInGroup = computed(() =>
  contacts.value.filter((c) => !memberIds.value.has(String(c.contactUserId)))
)

async function fetchGroup() {
  loading.value = true
  try {
    const { data } = await api.get(`/conversations/${conversationId}`, { skipGlobalLoader: true })
    if (data?.type !== 'group') {
      router.replace('/conversations')
      return
    }
    groupName.value = data.groupName ?? 'مجموعة'
    groupImageUrl.value = data.groupImageUrl ?? null
  } catch (_) {
    router.replace('/conversations')
    return
  } finally {
    loading.value = false
  }
}

async function fetchMembers() {
  try {
    const { data } = await api.get(`/conversations/${conversationId}/members`, { skipGlobalLoader: true })
    members.value = data ?? []
  } catch (_) {
    members.value = []
  }
}

async function fetchContacts() {
  try {
    const { data } = await api.get('/contacts', { skipGlobalLoader: true })
    contacts.value = data ?? []
  } catch (_) {
    contacts.value = []
  }
}

async function leaveGroup() {
  showLeaveConfirm.value = false
  leaving.value = true
  try {
    await api.post(`/conversations/${conversationId}/leave`)
    router.replace('/conversations')
  } catch (_) {}
  finally {
    leaving.value = false
  }
}

async function addMember(userId) {
  addingUserId.value = userId
  try {
    await api.post(`/conversations/${conversationId}/members`, JSON.stringify(userId), {
      headers: { 'Content-Type': 'application/json' }
    })
    await fetchMembers()
    showAddModal.value = false
  } catch (_) {}
  finally {
    addingUserId.value = null
  }
}

async function removeMember(userId) {
  removingUserId.value = userId
  try {
    await api.delete(`/conversations/${conversationId}/members/${userId}`)
    await fetchMembers()
  } catch (_) {}
  finally {
    removingUserId.value = null
  }
}

function goBack() {
  router.replace(`/conversation/${conversationId}`)
}

function openAddModal() {
  showAddModal.value = true
  fetchContacts()
}

function startEditName() {
  editNameValue.value = groupName.value
  editError.value = ''
  showEditName.value = true
}

function cancelEditName() {
  showEditName.value = false
  editNameValue.value = ''
  editError.value = ''
}

async function saveGroupName() {
  const name = editNameValue.value?.trim()
  if (!name || name.length > 100) {
    editError.value = name ? t('groups.groupNameRequired') : ''
    return
  }
  savingGroup.value = true
  editError.value = ''
  try {
    const { data } = await api.put(`/conversations/${conversationId}/group`, { name })
    if (data?.groupName != null) groupName.value = data.groupName
    showEditName.value = false
    editNameValue.value = ''
  } catch (e) {
    editError.value = e?.response?.data?.message ?? e?.userMessage ?? t('common.error')
  } finally {
    savingGroup.value = false
  }
}

async function onGroupPhotoChange(e) {
  const file = e.target?.files?.[0]
  if (!file || !file.type.startsWith('image/')) return
  uploadingPhoto.value = true
  editError.value = ''
  try {
    const formData = new FormData()
    formData.append('file', file)
    const { data: uploadData } = await api.post('/media/upload', formData, { timeout: 60000 })
    const url = uploadData?.url
    if (!url) throw new Error('Invalid upload')
    await api.put(`/conversations/${conversationId}/group`, { imageUrl: url })
    groupImageUrl.value = url
  } catch (err) {
    editError.value = err?.response?.data?.message ?? err?.userMessage ?? t('common.error')
  } finally {
    uploadingPhoto.value = false
    if (groupImageInput.value) groupImageInput.value.value = ''
  }
}

onMounted(async () => {
  await fetchGroup()
  if (route.path.includes('group-info')) await fetchMembers()
})
</script>

<template>
  <div class="group-info page auth-pattern">
    <header class="top-bar">
      <button class="back-btn" @click="goBack" :aria-label="t('common.cancel')">
        <ChevronRight :size="22" />
      </button>
      <span class="top-title">{{ t('groups.infoTitle') }}</span>
      <span class="top-bar-spacer" aria-hidden="true"></span>
    </header>

    <template v-if="!loading">
      <div class="group-header">
        <div class="group-avatar-wrap">
          <button
            v-if="isAdmin"
            type="button"
            class="group-avatar-btn"
            :disabled="uploadingPhoto"
            @click="groupImageInput?.click()"
            :aria-label="t('groups.editGroupPhoto')"
          >
            <div
              class="group-avatar"
              :style="{
                background: groupImageUrl && !isImageUrl(groupImageUrl) ? 'var(--primary)' : 'var(--bg-elevated)'
              }"
            >
              <CachedAvatar v-if="groupImageUrl && isImageUrl(groupImageUrl)" :url="groupImageUrl" img-class="avatar-img" />
              <template v-else-if="uploadingPhoto">...</template>
              <span v-else>{{ groupName?.[0]?.toUpperCase() || '?' }}</span>
            </div>
            <span class="group-avatar-edit-badge">
              <Image :size="14" />
            </span>
          </button>
          <div
            v-else
            class="group-avatar"
            :style="{
              background: groupImageUrl && !isImageUrl(groupImageUrl) ? 'var(--primary)' : 'var(--bg-elevated)'
            }"
          >
            <CachedAvatar v-if="groupImageUrl && isImageUrl(groupImageUrl)" :url="groupImageUrl" img-class="avatar-img" />
            <span v-else>{{ groupName?.[0]?.toUpperCase() || '?' }}</span>
          </div>
          <input
            ref="groupImageInput"
            type="file"
            accept="image/jpeg,image/png,image/gif,image/webp"
            class="hidden-input"
            @change="onGroupPhotoChange"
          />
        </div>
        <div v-if="showEditName" class="group-name-edit">
          <input
            v-model="editNameValue"
            type="text"
            class="group-name-input"
            :placeholder="t('groups.groupNamePlaceholder')"
            maxlength="100"
            @keydown.enter="saveGroupName"
          />
          <div class="group-name-edit-actions">
            <button type="button" class="btn-edit-cancel" @click="cancelEditName">{{ t('common.cancel') }}</button>
            <button type="button" class="btn-edit-save" :disabled="savingGroup" @click="saveGroupName">{{ t('groups.save') }}</button>
          </div>
          <p v-if="editError" class="edit-error">{{ editError }}</p>
        </div>
        <template v-else>
          <div class="group-name-row">
            <h1 class="group-name">{{ groupName }}</h1>
            <button
              v-if="isAdmin"
              type="button"
              class="icon-btn edit-name-btn"
              :aria-label="t('groups.editGroupName')"
              @click="startEditName"
            >
              <Pencil :size="18" />
            </button>
          </div>
        </template>
      </div>

      <div class="section">
        <div class="section-header">
          <span class="section-title">{{ t('groups.members') }} ({{ members.length }})</span>
          <button
            type="button"
            class="add-member-btn"
            @click="openAddModal"
          >
            <UserPlus :size="20" />
            <span>{{ t('groups.addMember') }}</span>
          </button>
        </div>
        <div class="members-list">
          <div
            v-for="m in members"
            :key="m.userId ?? m.UserId"
            class="member-row"
          >
            <div
              class="member-avatar"
              :style="{
                background: (m.avatar ?? m.Avatar) && !isImageUrl(m.avatar ?? m.Avatar) ? 'var(--primary)' : 'var(--bg-elevated)'
              }"
            >
              <CachedAvatar v-if="(m.avatar ?? m.Avatar) && isImageUrl(m.avatar ?? m.Avatar)" :url="m.avatar ?? m.Avatar" img-class="avatar-img" />
              <span v-else>{{ (m.name ?? m.Name)?.[0]?.toUpperCase() || '?' }}</span>
            </div>
            <div class="member-meta">
              <span class="member-name">{{ m.name ?? m.Name ?? '—' }}</span>
              <span
                class="member-role"
                :class="{ 'member-role--admin': (m.role ?? m.Role) === 'Admin' }"
              >{{ (m.role ?? m.Role) === 'Admin' ? t('groups.admin') : t('groups.member') }}</span>
            </div>
            <div v-if="currentUserId && String(m.userId ?? m.UserId) !== currentUserId" class="member-actions">
              <button
                v-if="isAdmin"
                type="button"
                class="icon-btn danger"
                :disabled="removingUserId !== null"
                :aria-label="t('groups.removeMember')"
                @click="removeMember(m.userId ?? m.UserId)"
              >
                <UserMinus :size="18" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <div class="section leave-section">
        <button
          type="button"
          class="leave-btn"
          :disabled="leaving"
          @click="showLeaveConfirm = true"
        >
          <LogOut :size="20" />
          <span>{{ t('groups.leaveGroup') }}</span>
        </button>
      </div>
    </template>

    <!-- Add member modal -->
    <Teleport to="body">
      <div v-if="showAddModal" class="modal-backdrop" @click.self="showAddModal = false">
        <div class="modal-sheet">
          <div class="modal-header">
            <h3>{{ t('groups.addMember') }}</h3>
            <button type="button" class="modal-close" @click="showAddModal = false">×</button>
          </div>
          <div class="modal-body">
            <div v-if="!contactsNotInGroup.length" class="empty-hint">
              <Users :size="32" class="empty-icon" />
              <p>{{ t('contacts.empty') }}</p>
            </div>
            <div v-else class="contact-pick-list">
              <div
                v-for="c in contactsNotInGroup"
                :key="c.contactUserId"
                class="contact-pick-row"
                @click="addMember(c.contactUserId)"
              >
                <div
                  class="member-avatar"
                  :style="{ background: c.avatar && !isImageUrl(c.avatar) ? 'var(--primary)' : 'var(--bg-elevated)' }"
                >
                  <CachedAvatar v-if="c.avatar && isImageUrl(c.avatar)" :url="c.avatar" img-class="avatar-img" />
                  <span v-else>{{ (c.name ?? '')?.[0]?.toUpperCase() || '?' }}</span>
                </div>
                <span class="member-name">{{ c.name ?? '—' }}</span>
                <span v-if="addingUserId === c.contactUserId" class="adding-dot">...</span>
                <UserPlus v-else :size="18" class="add-icon" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Leave confirm -->
    <Teleport to="body">
      <div v-if="showLeaveConfirm" class="modal-backdrop" @click.self="showLeaveConfirm = false">
        <div class="modal-dialog">
          <p class="confirm-text">{{ t('groups.leaveConfirm') }}</p>
          <div class="confirm-actions">
            <button type="button" class="btn-secondary" @click="showLeaveConfirm = false">{{ t('common.cancel') }}</button>
            <button type="button" class="btn-danger" :disabled="leaving" @click="leaveGroup">{{ t('groups.leaveGroup') }}</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.group-info {
  background: var(--bg-primary);
  min-height: 100%;
  padding-bottom: var(--safe-bottom);
  font-family: 'Cairo', sans-serif;
  display: flex;
  flex-direction: column;
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
}

.group-info.page.auth-pattern::before {
  opacity: 0.05;
}

.top-bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: calc(var(--safe-top) + 10px) var(--spacing) 10px;
  position: relative;
  flex-shrink: 0;
  background: var(--bg-secondary);
  border-bottom: 1px solid var(--border);
}

.back-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: var(--touch-min);
  height: var(--touch-min);
  min-width: var(--touch-min);
  min-height: var(--touch-min);
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  color: var(--text-secondary);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  flex-shrink: 0;
}

.top-title {
  position: absolute;
  left: 0;
  right: 0;
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
  text-align: center;
  pointer-events: none;
}

.top-bar-spacer {
  width: var(--touch-min);
  min-width: var(--touch-min);
  flex-shrink: 0;
}

.group-header {
  display: flex;
  flex-direction: column;
  align-items: center;
  margin: 12px var(--spacing) 16px;
  padding: 22px var(--spacing);
  gap: 14px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
  flex-shrink: 0;
}
html.light .group-header,
[data-theme="light"] .group-header {
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
}

.group-avatar-wrap {
  position: relative;
}

.group-avatar-btn {
  padding: 0;
  border: none;
  background: none;
  cursor: pointer;
  position: relative;
  -webkit-tap-highlight-color: transparent;
}

.group-avatar-btn:disabled {
  opacity: 0.8;
  cursor: wait;
}

.group-avatar {
  width: 88px;
  height: 88px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  color: white;
  font-size: 30px;
  font-weight: 600;
  box-shadow: 0 0 0 1px var(--border), 0 4px 16px rgba(0, 0, 0, 0.1);
}
html.light .group-avatar,
[data-theme="light"] .group-avatar {
  box-shadow: 0 0 0 1px var(--border), 0 2px 10px rgba(0, 0, 0, 0.06);
}

.group-avatar .avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.group-avatar-edit-badge {
  position: absolute;
  bottom: 0;
  inset-inline-end: 0;
  width: 30px;
  height: 30px;
  border-radius: 50%;
  background: var(--primary);
  color: white;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--bg-card);
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.15);
}

.hidden-input {
  position: absolute;
  width: 0;
  height: 0;
  opacity: 0;
  pointer-events: none;
}

.group-name-row {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
  max-width: 100%;
}

.group-name {
  font-size: 21px;
  font-weight: 700;
  color: var(--text-primary);
  margin: 0;
  text-align: center;
  max-width: min(100%, calc(100vw - 120px));
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  line-height: 1.25;
}

.edit-name-btn {
  color: var(--text-muted);
  padding: 6px;
}

.edit-name-btn:active {
  color: var(--primary);
}

.group-name-edit {
  width: 100%;
  max-width: 280px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.group-name-input {
  width: 100%;
  padding: 12px 16px;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--bg-card);
  color: var(--text-primary);
  font-size: 16px;
  font-family: 'Cairo', sans-serif;
  outline: none;
  box-sizing: border-box;
}

.group-name-edit-actions {
  display: flex;
  gap: 8px;
  justify-content: center;
}

.btn-edit-cancel {
  padding: 6px 14px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
  color: var(--text-secondary);
  font-size: 13px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.btn-edit-save {
  padding: 6px 14px;
  border: none;
  border-radius: 8px;
  background: var(--primary);
  color: white;
  font-size: 13px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.btn-edit-save:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.edit-error {
  margin: 0;
  font-size: 13px;
  color: #f44336;
  text-align: center;
}

.section {
  padding: 0 var(--spacing) 16px;
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
}

.section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  flex-wrap: wrap;
  margin-bottom: 10px;
  padding-bottom: 10px;
  border-bottom: 1px solid var(--border);
}

.section-title {
  font-size: 13px;
  font-weight: 700;
  color: var(--text-muted);
  letter-spacing: 0.02em;
  min-width: 0;
}

.add-member-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  padding: 8px 14px;
  background: rgba(108, 99, 255, 0.12);
  border: 1px solid rgba(108, 99, 255, 0.35);
  border-radius: 999px;
  color: var(--primary);
  font-size: 13px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.15s, border-color 0.15s;
  flex-shrink: 0;
}
.add-member-btn:active {
  background: rgba(108, 99, 255, 0.2);
  border-color: var(--primary);
}
html.light .add-member-btn,
[data-theme="light"] .add-member-btn {
  background: rgba(108, 99, 255, 0.08);
  border-color: rgba(108, 99, 255, 0.28);
}

.members-list {
  display: flex;
  flex-direction: column;
  gap: 0;
  border: 1px solid var(--border);
  border-radius: var(--radius);
  background: var(--bg-card);
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  max-height: min(52vh, 420px);
}

.member-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 14px;
  border-bottom: 1px solid var(--border);
  -webkit-tap-highlight-color: transparent;
  transition: background 0.12s;
}
.member-row:last-child {
  border-bottom: none;
}
.member-row:active {
  background: var(--bg-card-hover);
}

.member-avatar {
  width: 48px;
  height: 48px;
  min-width: 48px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 17px;
  color: white;
  overflow: hidden;
  box-shadow: 0 0 0 1px var(--border);
}

.member-avatar .avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.member-meta {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.member-name {
  font-size: 15px;
  font-weight: 600;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
}

.member-role {
  font-size: 12px;
  color: var(--text-muted);
  font-family: 'Cairo', sans-serif;
}
.member-role--admin {
  display: inline-flex;
  align-items: center;
  width: max-content;
  margin-top: 2px;
  padding: 2px 8px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 700;
  color: var(--primary);
  background: rgba(108, 99, 255, 0.14);
}
html.light .member-role--admin,
[data-theme="light"] .member-role--admin {
  background: rgba(108, 99, 255, 0.1);
}

.member-actions {
  flex-shrink: 0;
}

.icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: var(--touch-min);
  min-height: var(--touch-min);
  padding: 8px;
  background: none;
  border: none;
  color: var(--text-tertiary);
  cursor: pointer;
  border-radius: var(--radius-sm);
  -webkit-tap-highlight-color: transparent;
}

.icon-btn.danger {
  color: #f44336;
}

.leave-section {
  padding: 12px var(--spacing) calc(16px + var(--safe-bottom));
  margin-top: auto;
  flex-shrink: 0;
}

.leave-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
  min-height: var(--touch-min);
  padding: 12px 18px;
  border: 1px solid rgba(244, 67, 54, 0.45);
  border-radius: var(--radius);
  background: rgba(244, 67, 54, 0.07);
  color: var(--danger, #f44336);
  font-size: 15px;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  transition: background 0.15s;
}
.leave-btn:active:not(:disabled) {
  opacity: 0.9;
}

.leave-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

/* Modal */
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: flex-end;
  justify-content: center;
  z-index: 1000;
}

.modal-sheet {
  width: 100%;
  max-height: 70vh;
  background: var(--bg-primary);
  border-radius: 16px 16px 0 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px var(--spacing);
  border-bottom: 1px solid var(--border);
}

.modal-header h3 {
  margin: 0;
  font-size: 18px;
  font-weight: 700;
  color: var(--text-primary);
}

.modal-close {
  width: 36px;
  height: 36px;
  border: none;
  background: none;
  font-size: 24px;
  color: var(--text-secondary);
  cursor: pointer;
  line-height: 1;
}

.modal-body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 12px;
}

.empty-hint {
  text-align: center;
  padding: 24px;
  color: var(--text-muted);
  font-size: 14px;
}

.empty-hint .empty-icon {
  opacity: 0.5;
  margin-bottom: 8px;
}

.contact-pick-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.contact-pick-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  border-radius: 12px;
  background: var(--bg-card);
  border: 1px solid var(--border);
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
}

.contact-pick-row:active {
  background: var(--bg-card-hover);
}

.add-icon {
  color: var(--primary);
  flex-shrink: 0;
}

.adding-dot {
  font-size: 14px;
  color: var(--text-muted);
}

.modal-dialog {
  width: calc(100% - 32px);
  max-width: 340px;
  padding: 24px;
  background: var(--bg-card);
  border-radius: 16px;
  margin: auto;
}

.confirm-text {
  margin: 0 0 20px;
  font-size: 16px;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  text-align: center;
}

.confirm-actions {
  display: flex;
  gap: 12px;
  justify-content: center;
}

.btn-secondary {
  padding: 12px 20px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: 12px;
  color: var(--text-primary);
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}

.btn-danger {
  padding: 12px 20px;
  background: #f44336;
  border: none;
  border-radius: 12px;
  color: white;
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}

.btn-danger:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

@media (max-width: 360px) {
  .group-header {
    margin: 8px 12px 12px;
    padding: 18px 14px;
  }
  .group-avatar {
    width: 76px;
    height: 76px;
    font-size: 26px;
  }
  .group-name {
    font-size: 18px;
  }
  .section-header {
    padding-bottom: 8px;
  }
  .add-member-btn span {
    display: none;
  }
  .add-member-btn {
    width: 40px;
    height: 40px;
    min-width: 40px;
    padding: 0;
    border-radius: 12px;
  }
  .member-row {
    padding: 10px 12px;
    gap: 10px;
  }
  .member-avatar {
    width: 44px;
    height: 44px;
    min-width: 44px;
    font-size: 15px;
  }
}
</style>
