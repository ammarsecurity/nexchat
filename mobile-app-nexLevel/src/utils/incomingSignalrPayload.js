/**
 * تطبيع حمولات SignalR لمكالمات المحادثة (اختلاف التسلسل/النوع بين إصدارات السيرفر أو التسلسل JSON).
 */

export function parseIncomingConversationCallPayload(cid, voiceOnly, callerName, callerAvatar) {
  if (typeof cid === 'boolean') return null

  let conversationId = null
  let vo = voiceOnly === true
  let name = typeof callerName === 'string' ? callerName : ''
  let avatar = callerAvatar ?? null

  if (typeof cid === 'string' && cid.trim()) {
    conversationId = cid.trim()
  } else if (cid != null && typeof cid === 'object' && !Array.isArray(cid)) {
    const o = cid
    const id = o.conversationId ?? o.ConversationId ?? o.id ?? o.Id
    if (id != null && String(id).trim()) {
      conversationId = String(id).trim()
      if (o.voiceOnly === true || o.VoiceOnly === true) vo = true
      const cn = o.callerName ?? o.CallerName
      if (typeof cn === 'string') name = cn
      const ca = o.callerAvatar ?? o.CallerAvatar
      if (ca != null) avatar = ca
    }
  } else if (cid != null && cid !== '') {
    const s = String(cid).trim()
    if (s && s !== 'undefined' && s !== 'null') conversationId = s
  }

  if (!conversationId) return null
  return { conversationId, voiceOnly: vo, callerName: name, callerAvatar: avatar }
}

export function parseVideoCallAcceptedPayload(cidStr, voiceOnly) {
  if (cidStr == null) return null

  if (typeof cidStr === 'object' && cidStr !== null && !Array.isArray(cidStr)) {
    const o = cidStr
    const id = o.conversationId ?? o.ConversationId ?? o.id ?? o.Id ?? o.sessionId ?? o.SessionId
    if (id == null) return null
    return {
      conversationId: String(id).trim(),
      voiceOnly: (o.voiceOnly ?? o.VoiceOnly) === true
    }
  }

  const cid = String(cidStr).trim()
  if (!cid || cid === 'undefined' || cid === 'null') return null
  return { conversationId: cid, voiceOnly: voiceOnly === true }
}
