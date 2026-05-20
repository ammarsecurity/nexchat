<script setup>
import { computed } from 'vue'
import { Play, Film } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'
import { ensureAbsoluteUrl } from '../utils/imageUrl'

const props = defineProps({
  payload: { type: Object, required: true }
})

const emit = defineEmits(['open'])

const { t } = useI18n()

const thumbUrl = computed(() =>
  props.payload.thumbnailUrl ? ensureAbsoluteUrl(props.payload.thumbnailUrl) : null
)

function onOpen() {
  emit('open', props.payload)
}
</script>

<template>
  <button type="button" class="short-film-card" @click="onOpen">
    <div class="short-film-card__media">
      <img v-if="thumbUrl" :src="thumbUrl" alt="" class="short-film-card__img" />
      <div v-else class="short-film-card__placeholder">
        <Film :size="28" stroke-width="1.5" />
      </div>
      <span class="short-film-card__gradient" aria-hidden="true" />
      <span class="short-film-card__play" aria-hidden="true">
        <Play :size="22" fill="currentColor" />
      </span>
    </div>
    <div class="short-film-card__body">
      <span class="short-film-card__tag">{{ t('shortFilms.title') }}</span>
      <span class="short-film-card__title">{{ payload.title || t('shortFilms.title') }}</span>
    </div>
  </button>
</template>

<style scoped>
.short-film-card {
  display: block;
  width: min(100%, 260px);
  padding: 0;
  border: none;
  border-radius: 12px;
  overflow: hidden;
  background: var(--bg-elevated);
  text-align: start;
  cursor: pointer;
  -webkit-tap-highlight-color: transparent;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.12);
}

.short-film-card:active {
  transform: scale(0.99);
  opacity: 0.96;
}

.short-film-card__media {
  position: relative;
  aspect-ratio: 16 / 9;
  background: #111;
  overflow: hidden;
}

.short-film-card__img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.short-film-card__placeholder {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--primary);
  background: linear-gradient(135deg, rgba(108, 99, 255, 0.2), rgba(255, 101, 132, 0.12));
}

.short-film-card__gradient {
  position: absolute;
  inset: 0;
  background: linear-gradient(to top, rgba(0, 0, 0, 0.55) 0%, transparent 50%);
  pointer-events: none;
}

.short-film-card__play {
  position: absolute;
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%);
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: rgba(108, 99, 255, 0.9);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.35);
}

.short-film-card__body {
  padding: 10px 12px 11px;
  background: var(--bg-card);
}

.short-film-card__tag {
  display: block;
  font-size: 10px;
  font-weight: 700;
  color: var(--primary);
  margin-bottom: 4px;
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

.short-film-card__title {
  display: block;
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  line-height: 1.35;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.message-wrap.mine .short-film-card__body {
  background: rgba(255, 255, 255, 0.08);
}

.message-wrap.mine .short-film-card__title {
  color: #fff;
}

.message-wrap.mine .short-film-card__tag {
  color: #c8c4ff;
}
</style>
