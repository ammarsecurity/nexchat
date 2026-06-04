import { notify } from './notify'
import {
  buildInviteUrl,
  buildInviteWebUrl,
  buildShortFilmShareUrl,
  buildStoryShareUrl,
  normalizeInviteCode
} from './shareLinks'

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    return false
  }
}

export async function shareTextPayload({ title, text, url }) {
  const body = [text, url].filter(Boolean).join('\n').trim()
  if (!body) return { ok: false, copied: false }

  if (typeof navigator.share === 'function') {
    try {
      await navigator.share({
        title: title || undefined,
        text: text || undefined,
        url: url || undefined
      })
      return { ok: true, copied: false, shared: true }
    } catch (err) {
      if (err?.name === 'AbortError') return { ok: true, copied: false, shared: false }
    }
  }

  const copied = await copyText(body)
  return { ok: copied, copied, shared: false }
}

export async function shareInviteCode(code, options = {}) {
  const normalized = normalizeInviteCode(code)
  if (!normalized) return { ok: false }

  const { t, inviterName } = options
  const link = buildInviteWebUrl(normalized)
  const appLink = buildInviteUrl(normalized)
  const text =
    typeof t === 'function'
      ? t('share.inviteMessage', { code: normalized, name: inviterName || 'NexChat', link })
      : `انضم إلي على NexChat\nكودي: ${normalized}\n${link}`

  const result = await shareTextPayload({
    title: typeof t === 'function' ? t('share.inviteTitle') : 'NexChat',
    text,
    url: link
  })

  if (result.copied && typeof t === 'function') {
    notify.success(t('share.linkCopied'))
  } else if (result.shared && typeof t === 'function') {
    notify.success(t('share.shareOpened'))
  }

  return { ...result, link, appLink }
}

export async function shareShortFilmPublic(film, options = {}) {
  if (!film?.id) return { ok: false }
  const { t } = options
  const link = buildShortFilmShareUrl(film.id)
  const title = film.title || (typeof t === 'function' ? t('shortFilms.title') : 'Short film')
  const text =
    typeof t === 'function'
      ? t('shortFilms.shareMessage', { title, link })
      : `🎬 ${title}\n${link}`

  const result = await shareTextPayload({
    title,
    text,
    url: link
  })

  if (result.copied && typeof t === 'function') notify.success(t('share.linkCopied'))
  else if (result.shared && typeof t === 'function') notify.success(t('share.shareOpened'))

  return { ...result, link }
}

export async function shareStoryPublic(userId, options = {}) {
  if (!userId) return { ok: false }
  const { t, publisherName } = options
  const link = buildStoryShareUrl(userId)
  const name = publisherName || (typeof t === 'function' ? t('stories.allStory') : 'Story')
  const text =
    typeof t === 'function'
      ? t('share.storyMessage', { name, link })
      : `شاهد ستوري ${name} على NexChat\n${link}`

  const result = await shareTextPayload({
    title: typeof t === 'function' ? t('share.storyTitle', { name }) : name,
    text,
    url: link
  })

  if (result.copied && typeof t === 'function') notify.success(t('share.linkCopied'))
  else if (result.shared && typeof t === 'function') notify.success(t('share.shareOpened'))

  return { ...result, link }
}
