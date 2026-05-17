import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '../services/api'
import { storyHub, ensureConnected } from '../services/signalr'

export const useStoriesStore = defineStore('stories', () => {
  const feed = ref([])
  const loading = ref(false)
  const loaded = ref(false)

  const unseenCount = computed(() => feed.value.filter(r => !r.isMine && r.hasUnseen).length)

  async function fetchFeed(force = false) {
    if (loading.value) return
    if (loaded.value && !force) return
    loading.value = true
    try {
      const { data } = await api.get('/stories/feed', { skipGlobalLoader: true })
      feed.value = (data ?? []).map(normalizeRing)
      loaded.value = true
    } catch {
      if (!loaded.value) feed.value = []
    } finally {
      loading.value = false
    }
  }

  function normalizeRing(r) {
    return {
      userId: r.userId ?? r.UserId,
      name: r.name ?? r.Name ?? '—',
      avatar: r.avatar ?? r.Avatar,
      hasUnseen: r.hasUnseen ?? r.HasUnseen ?? false,
      latestThumbUrl: r.latestThumbUrl ?? r.LatestThumbUrl,
      latestAt: r.latestAt ?? r.LatestAt,
      slideCount: r.slideCount ?? r.SlideCount ?? 0,
      isMine: r.isMine ?? r.IsMine ?? false
    }
  }

  function applyStoryPublished(payload) {
    const userId = payload?.userId ?? payload?.UserId
    if (!userId) return
    const idx = feed.value.findIndex(r => String(r.userId) === String(userId))
    const ring = {
      userId,
      name: payload.publisherName ?? payload.PublisherName ?? feed.value[idx]?.name ?? '—',
      avatar: feed.value[idx]?.avatar,
      hasUnseen: true,
      latestThumbUrl: payload.thumbUrl ?? payload.ThumbUrl ?? feed.value[idx]?.latestThumbUrl,
      latestAt: new Date().toISOString(),
      slideCount: (feed.value[idx]?.slideCount ?? 0) + 1,
      isMine: false
    }
    if (idx >= 0) {
      feed.value[idx] = { ...feed.value[idx], ...ring }
    } else {
      feed.value.unshift(ring)
    }
    feed.value.sort((a, b) => (b.isMine ? 1 : 0) - (a.isMine ? 1 : 0))
  }

  function applyStoryDeleted(payload) {
    const userId = payload?.userId ?? payload?.UserId
    const slideId = payload?.slideId ?? payload?.SlideId
    if (!userId) return
    const idx = feed.value.findIndex(r => String(r.userId) === String(userId))
    if (idx < 0) return
    const r = feed.value[idx]
    if ((r.slideCount ?? 1) <= 1) {
      feed.value.splice(idx, 1)
    } else {
      feed.value[idx] = { ...r, slideCount: r.slideCount - 1 }
    }
    void slideId
  }

  function markRingSeen(userId) {
    const idx = feed.value.findIndex(r => String(r.userId) === String(userId))
    if (idx >= 0) feed.value[idx] = { ...feed.value[idx], hasUnseen: false }
  }

  async function ensureHub() {
    try {
      await ensureConnected(storyHub)
    } catch {}
  }

  function invalidate() {
    loaded.value = false
  }

  return {
    feed,
    loading,
    loaded,
    unseenCount,
    fetchFeed,
    applyStoryPublished,
    applyStoryDeleted,
    markRingSeen,
    ensureHub,
    invalidate
  }
})
