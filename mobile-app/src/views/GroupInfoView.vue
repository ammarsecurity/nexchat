<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { UserPlus, LogOut, UserMinus, Users, Pencil, Image } from 'lucide-vue-next'
import ModernPageShell from '../components/ui/ModernPageShell.vue'
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
  <ModernPageShell :title="t('groups.infoTitle')" :back-to="`/conversation/${conversationId}`">
    <div v-if="loading" class="modern-empty">{{ t('common.loading') }}</div>

    <template v-else>
      <div class="group-hero">
        <div class="group-avatar-wrap">
          <button
            v-if="isAdmin"
            type="button"
            class="group-avatar-btn"
            :disabled="uploadingPhoto"
            @click="groupImageInput?.click()"
            :aria-label="t('groups.editGroupPhoto')"
          >
            <div class="modern-avatar-xl group-avatar">
              <CachedAvatar v-if="groupImageUrl && isImageUrl(groupImageUrl)" :url="groupImageUrl" img-class="avatar-img" />
              <template v-else-if="uploadingPhoto">...</template>
              <span v-else>{{ groupName?.[0]?.toUpperCase() || '?' }}</span>
            </div>
            <span class="group-avatar-edit-badge">
              <Image :size="14" />
            </span>
          </button>
          <div v-else class="modern-avatar-xl group-avatar">
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
        <div v-else class="group-name-row">
          <h2 class="modern-profile-name">{{ groupName }}</h2>
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
      </div>

      <section class="modern-section">
        <div class="section-header">
          <h3 class="modern-section-title">{{ t('groups.members') }} ({{ members.length }})</h3>
          <button type="button" class="add-member-btn" @click="openAddModal">
            <UserPlus :size="18" />
            <span>{{ t('groups.addMember') }}</span>
          </button>
        </div>
        <div class="modern-list">
          <div v-for="m in members" :key="m.userId ?? m.UserId" class="modern-list-row member-row">
            <div class="modern-list-row__avatar">
              <CachedAvatar v-if="(m.avatar ?? m.Avatar) && isImageUrl(m.avatar ?? m.Avatar)" :url="m.avatar ?? m.Avatar" img-class="avatar-img" />
              <span v-else>{{ (m.name ?? m.Name)?.[0]?.toUpperCase() || '?' }}</span>
            </div>
            <div class="modern-list-row__body">
              <span class="modern-list-row__title">{{ m.name ?? m.Name ?? '—' }}</span>
              <span class="modern-list-row__sub" :class="{ 'member-role--admin': (m.role ?? m.Role) === 'Admin' }">
                {{ (m.role ?? m.Role) === 'Admin' ? t('groups.admin') : t('groups.member') }}
              </span>
            </div>
            <button
              v-if="isAdmin && currentUserId && String(m.userId ?? m.UserId) !== currentUserId"
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
      </section>

      <div class="modern-option-list leave-section">
        <button type="button" class="modern-option-btn modern-option-btn--danger" :disabled="leaving" @click="showLeaveConfirm = true">
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
  </ModernPageShell>
</template>

<style scoped>
.group-hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 16px;
  margin-bottom: 8px;
  border-radius: var(--radius-lg);
  background: var(--bg-card);
  border: 1px solid var(--border);
  box-shadow: var(--shadow-sm);
}

.group-avatar-wrap {
  position: relative;
}

.group-avatar-btn {
  position: relative;
  padding: 0;
  border: none;
  background: none;
  cursor: pointer;
}

.group-avatar-edit-badge {
  position: absolute;
  bottom: 4px;
  inset-inline-end: 4px;
  width: 28px;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--primary);
  color: #fff;
  border-radius: 50%;
  box-shadow: var(--shadow-sm);
}

.hidden-input {
  display: none;
}

.group-name-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 8px;
}

.group-name-edit {
  width: 100%;
  max-width: 320px;
  margin-top: 12px;
}

.group-name-input {
  width: 100%;
  padding: 12px 14px;
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  background: var(--bg-card);
  font-family: 'Cairo', sans-serif;
  font-size: 15px;
  color: var(--text-primary);
}

.group-name-edit-actions {
  display: flex;
  gap: 8px;
  margin-top: 10px;
}

.btn-edit-cancel,
.btn-edit-save {
  flex: 1;
  min-height: 40px;
  border-radius: var(--radius-lg);
  font-family: 'Cairo', sans-serif;
  font-weight: 600;
  cursor: pointer;
  border: none;
}

.btn-edit-cancel {
  background: var(--bg-elevated);
  color: var(--text-secondary);
}

.btn-edit-save {
  background: var(--primary);
  color: #fff;
}

.edit-error {
  margin-top: 8px;
  font-size: 13px;
  color: var(--danger);
  text-align: center;
}

.section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 10px;
}

.section-header .modern-section-title {
  margin: 0;
}

.add-member-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  border: none;
  border-radius: var(--radius-full);
  background: var(--primary-soft);
  color: var(--primary);
  font-family: 'Cairo', sans-serif;
  font-size: 13px;
  font-weight: 700;
  cursor: pointer;
}

.member-row .member-role--admin {
  color: var(--primary);
  font-weight: 600;
}

.icon-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  border: none;
  border-radius: 12px;
  background: var(--bg-elevated);
  color: var(--text-secondary);
  cursor: pointer;
  flex-shrink: 0;
}

.icon-btn.danger {
  background: rgba(244, 67, 54, 0.1);
  color: var(--danger);
}

.leave-section {
  margin-top: 20px;
  padding-bottom: 8px;
}

/* Modal */
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.52);
  backdrop-filter: blur(4px);
  -webkit-backdrop-filter: blur(4px);
  display: flex;
  align-items: flex-end;
  justify-content: center;
  z-index: 1000;
}

.modal-sheet {
  width: 100%;
  max-height: 70vh;
  background: var(--bg-card);
  border-radius: var(--radius-lg) var(--radius-lg) 0 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  box-shadow: 0 -8px 32px rgba(0, 0, 0, 0.15);
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
  border-radius: var(--radius-lg);
  margin: auto;
  box-shadow: var(--shadow-md);
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
  border-radius: 999px;
  color: var(--text-primary);
  font-weight: 600;
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}

.btn-danger {
  padding: 12px 20px;
  background: var(--danger);
  border: none;
  border-radius: 999px;
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
