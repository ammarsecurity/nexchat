/**
 * Local cache service using IndexedDB (Dexie)
 * - Conversations list: cached per user
 * - Messages: last 50 per conversation
 * - Background sync: load from cache first, then update from API
 */

import Dexie from 'dexie'

const DB_NAME = 'NexChatCache'
const MESSAGES_PER_CONVERSATION = 50

let db = null

function getDb() {
  if (!db) {
    db = new Dexie(DB_NAME)
    db.version(3).stores({
      conversations: '++id, userId, updatedAt',
      messages: '++id, [conversationId+userId], conversationId, userId, sentAt',
      avatarBlobs: 'url, cachedAt'
    })
  }
  return db
}

/**
 * Get cache key for current user (from localStorage)
 */
function getUserId() {
  try {
    const u = JSON.parse(localStorage.getItem('nexchat_user') || 'null')
    return u?.id ? String(u.id) : null
  } catch {
    return null
  }
}

/**
 * Save conversations list to cache
 */
export async function saveConversationsList(items) {
  const userId = getUserId()
  if (!userId || !Array.isArray(items)) return
  try {
    const db = getDb()
    const records = items.map((c, idx) => ({
      userId,
      conversationId: String(c.id ?? c.Id),
      data: c,
      updatedAt: Date.now(),
      sortOrder: idx
    }))

    await db.transaction('rw', db.conversations, async () => {
      await db.conversations.where('userId').equals(userId).delete()
      if (records.length > 0) {
        await db.conversations.bulkAdd(records)
      }
    })
  } catch {
    // IndexedDB may be disabled (private mode, etc.)
  }
}

/**
 * Load conversations list from cache (instant)
 */
export async function loadConversationsListFromCache() {
  const userId = getUserId()
  if (!userId) return []
  try {
    const db = getDb()
    const rows = await db.conversations.where('userId').equals(userId).toArray()
    rows.sort((a, b) => (a.sortOrder ?? 999) - (b.sortOrder ?? 999))
    return rows.map((r) => {
      const d = r.data
      if (!d) return d
      const unread = d.unreadCount ?? d.UnreadCount ?? 0
      return { ...d, unreadCount: unread, UnreadCount: unread }
    })
  } catch {
    return []
  }
}

/**
 * Save messages for a conversation (keep last 50)
 */
export async function saveMessagesForConversation(conversationId, messages) {
  const userId = getUserId()
  if (!userId || !conversationId) return
  try {
  const normalized = messages
    .filter((m) => m && !m.tempId && (m.id || m.Id))
    .map((m) => ({
      messageId: m.id ?? m.Id,
      senderId: m.senderId ?? m.SenderId,
      content: m.content ?? m.Content,
      type: m.type ?? m.Type ?? 'text',
      sentAt: m.sentAt ?? m.SentAt,
      deletedForEveryone: m.deletedForEveryone ?? m.DeletedForEveryone,
      isRead: m.isRead ?? m.IsRead
    }))

  const sorted = [...normalized].sort((a, b) => {
    const ta = new Date(a.sentAt).getTime()
    const tb = new Date(b.sentAt).getTime()
    return ta - tb
  })

  const toKeep = sorted.slice(-MESSAGES_PER_CONVERSATION)

  const db = getDb()
  await db.transaction('rw', db.messages, async () => {
    await db.messages
      .where('[conversationId+userId]')
      .equals([String(conversationId), userId])
      .delete()

    if (toKeep.length > 0) {
      await db.messages.bulkAdd(
        toKeep.map((m) => ({
          conversationId: String(conversationId),
          userId,
          ...m
        }))
      )
    }
  })
  } catch {
    // IndexedDB may be disabled
  }
}

/**
 * Load messages for a conversation from cache
 */
export async function loadMessagesFromCache(conversationId) {
  const userId = getUserId()
  if (!userId || !conversationId) return []
  try {
    const db = getDb()
    const rows = await db.messages
      .where('[conversationId+userId]')
      .equals([String(conversationId), userId])
      .toArray()

    rows.sort((a, b) => new Date(a.sentAt || 0).getTime() - new Date(b.sentAt || 0).getTime())

    return rows.map((r) => ({
    id: r.messageId ?? r.id,
    senderId: r.senderId,
    content: r.content,
    type: r.type,
    sentAt: r.sentAt,
    deletedForEveryone: r.deletedForEveryone,
    isRead: r.isRead,
    status: 'sent'
  }))
  } catch {
    return []
  }
}

/**
 * Remove messages for a conversation (e.g. when conversation is deleted)
 */
export async function clearMessagesForConversation(conversationId) {
  const userId = getUserId()
  if (!userId || !conversationId) return
  try {
    const db = getDb()
    await db.messages
    .where('[conversationId+userId]')
    .equals([String(conversationId), userId])
    .delete()
  } catch {
    // IndexedDB may be disabled
  }
}

/**
 * Clear all cache for current user (on logout)
 */
export async function clearUserCache() {
  const userId = getUserId()
  if (!userId) return
  try {
    const db = getDb()
    await db.transaction('rw', [db.conversations, db.messages, db.avatarBlobs], async () => {
      await db.conversations.where('userId').equals(userId).delete()
      await db.messages.where('userId').equals(userId).delete()
      await db.avatarBlobs.clear()
    })
  } catch {
    // IndexedDB may be disabled
  }
}

const AVATAR_CACHE_DAYS = 7

/**
 * Get avatar URL - uses cache if available, otherwise returns URL directly.
 */
export async function getCachedAvatarUrl(absoluteUrl) {
  if (!absoluteUrl || typeof absoluteUrl !== 'string') return absoluteUrl
  if (absoluteUrl.startsWith('blob:')) return absoluteUrl
  if (!absoluteUrl.startsWith('http://') && !absoluteUrl.startsWith('https://')) return absoluteUrl

  try {
    const db = getDb()
    const cached = await db.avatarBlobs.get(absoluteUrl)
    if (cached?.blob) {
      const age = Date.now() - (cached.cachedAt || 0)
      if (age < AVATAR_CACHE_DAYS * 24 * 60 * 60 * 1000) {
        return URL.createObjectURL(cached.blob)
      }
      await db.avatarBlobs.delete(absoluteUrl)
    }
  } catch {}
  return absoluteUrl
}

/**
 * Save avatar blob to cache for offline use and faster loads.
 * Called when image loads successfully (fetch or img onload).
 */
export async function saveAvatarToCache(absoluteUrl, blob) {
  if (!absoluteUrl || !blob || !(blob instanceof Blob)) return
  if (!absoluteUrl.startsWith('http://') && !absoluteUrl.startsWith('https://')) return
  try {
    await getDb().avatarBlobs.put({
      url: absoluteUrl,
      blob,
      cachedAt: Date.now()
    })
  } catch {
    // IndexedDB full or disabled
  }
}

/**
 * Invalidate avatar cache for a URL (e.g. when partner changes avatar).
 * Call when conversation data is updated with new partnerAvatar.
 */
export async function invalidateAvatarCache(url) {
  if (!url || !url.startsWith('http')) return
  try {
    await getDb().avatarBlobs.delete(url)
  } catch {}
}

export { MESSAGES_PER_CONVERSATION }
