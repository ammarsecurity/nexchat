import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useMatchingStore = defineStore('matching', () => {
  const status = ref('idle') // idle | searching | matched
  const genderFilter = ref('all') // all | male | female
  const incomingConnectionRequest = ref(null)
  /** بعد «التالي» من الدردشة: MatchingView يستأنف StartSearching هنا بدل كود داخل ChatView */
  const resumeSearchAfterNav = ref(false)
  /** إيقاف CancelSearching عند مغادرة /matching بسبب MatchFound → /chat */
  const skipNextMatchingUnmountCancel = ref(false)
  /** مطابقة عشوائية بانتظار قبول/تخطي الطرفين */
  const pendingRandomMatch = ref(null) // { sessionId, partner }
  /** عند الضغط «الخروج من الدردشة العشوائية» يُعاد الرفض دون StartSearching تلقائياً */
  const skipRestartAfterNextRandomDecline = ref(false)

  function setSearching() { status.value = 'searching' }
  function setMatched() { status.value = 'matched' }
  function setIdle() { status.value = 'idle' }
  function setIncomingConnectionRequest(data) { incomingConnectionRequest.value = data }
  function clearIncomingConnectionRequest() { incomingConnectionRequest.value = null }

  function setResumeSearchAfterNav(v) { resumeSearchAfterNav.value = !!v }
  function consumeResumeSearchAfterNav() {
    const v = resumeSearchAfterNav.value
    resumeSearchAfterNav.value = false
    return v
  }

  function armSkipNextMatchingUnmountCancel() { skipNextMatchingUnmountCancel.value = true }
  function consumeSkipNextMatchingUnmountCancel() {
    const v = skipNextMatchingUnmountCancel.value
    skipNextMatchingUnmountCancel.value = false
    return v
  }

  function setPendingRandomMatch(payload) { pendingRandomMatch.value = payload }
  function clearPendingRandomMatch() { pendingRandomMatch.value = null }

  function armSkipRestartAfterRandomDecline() {
    skipRestartAfterNextRandomDecline.value = true
  }
  function consumeSkipRestartAfterRandomDecline() {
    const v = skipRestartAfterNextRandomDecline.value
    skipRestartAfterNextRandomDecline.value = false
    return v
  }

  function patchIncomingRequesterAvatar(userId, avatar) {
    const req = incomingConnectionRequest.value
    if (!req) return
    const rid = String(req.requesterId ?? req.RequesterId ?? '')
    if (rid === String(userId)) {
      incomingConnectionRequest.value = {
        ...req,
        requesterAvatar: avatar,
        RequesterAvatar: avatar
      }
    }
  }

  function patchPendingRandomPartnerAvatar(userId, avatar, uniqueCode) {
    const pm = pendingRandomMatch.value
    if (!pm?.partner) return
    const p = pm.partner
    if (String(userId) === String(p.id ?? p.userId ?? '')) {
      pendingRandomMatch.value = { ...pm, partner: { ...p, avatar } }
      return
    }
    const uc = uniqueCode != null ? String(uniqueCode) : ''
    if (uc && String(p.uniqueCode ?? p.UniqueCode ?? '') === uc) {
      pendingRandomMatch.value = { ...pm, partner: { ...p, avatar } }
    }
  }

  return {
    status,
    genderFilter,
    incomingConnectionRequest,
    resumeSearchAfterNav,
    skipNextMatchingUnmountCancel,
    pendingRandomMatch,
    setSearching,
    setMatched,
    setIdle,
    setIncomingConnectionRequest,
    clearIncomingConnectionRequest,
    setResumeSearchAfterNav,
    consumeResumeSearchAfterNav,
    armSkipNextMatchingUnmountCancel,
    consumeSkipNextMatchingUnmountCancel,
    setPendingRandomMatch,
    clearPendingRandomMatch,
    armSkipRestartAfterRandomDecline,
    consumeSkipRestartAfterRandomDecline,
    patchIncomingRequesterAvatar,
    patchPendingRandomPartnerAvatar
  }
})
