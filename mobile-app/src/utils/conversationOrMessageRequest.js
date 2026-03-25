import api from '../services/api'

/** 409 متوقع في تدفق طلب المراسلة فقط — انظر sendMessageRequestOnly في UserProfileView */
export const validate409AsSuccess = {
  validateStatus: (s) => (s >= 200 && s < 300) || s === 409
}

/**
 * يفتح محادثة خاصة عند التبادل أو يُنشئ/يُعيد طلب مراسلة عبر مسار واحد (HTTP 200 دون 409 لتقليل ضوضاء الـ console).
 * المحادثات القديمة (قبل اشتراط التبادل) لا تُعدّل هنا؛ الإرسال عبر SignalR قد يستمر لها حتى تُعالج منفصلاً.
 * @returns {{ kind: 'conversation', conversationId: string } | { kind: 'messageRequest' }}
 */
export async function createPrivateConversationOrRequest(contactUserId) {
  const res = await api.post(
    '/conversations/open-private-or-request',
    { contactUserId },
    { skipGlobalLoader: true }
  )

  const data = res.data
  const result = data?.result ?? data?.Result

  if (result === 'opened') {
    return { kind: 'conversation', conversationId: data?.id ?? data?.Id }
  }
  if (result === 'messageRequestPending' || result === 'messageRequestCreated') {
    return { kind: 'messageRequest' }
  }

  const msg = data?.message ?? 'حدث خطأ، حاول مجدداً'
  throw Object.assign(new Error(msg), { response: res })
}

/**
 * التوجيه لصفحة طلبات المراسلة مع عرض شريط تنبيه للطلب الصادر.
 * @param {'default'|'share'} variant — share: نص يوضح أن المشاركة تنتظر القبول
 */
export function goToMessageRequestsOutgoingNotice(router, variant = 'default') {
  const notice = variant === 'share' ? 'outgoing-share-wait' : 'outgoing-wait'
  router.push({ path: '/message-requests', query: { notice } })
}
