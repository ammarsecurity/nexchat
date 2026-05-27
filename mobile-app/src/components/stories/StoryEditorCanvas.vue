<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { exportStoryImage, StoryExportError } from '../../utils/storyExport'

const props = defineProps({
  imageSrc: { type: String, default: '' },
  videoSrc: { type: String, default: '' },
  textOnly: { type: Boolean, default: false },
  backgroundColor: { type: String, default: 'linear-gradient(135deg,#6c63ff 0%,#ff6584 100%)' },
  initialFilterId: { type: String, default: 'none' }
})

const emit = defineEmits(['update:backgroundColor'])

const { t } = useI18n()

const canvasRef = ref(null)
const containerRef = ref(null)
const filterId = ref(props.initialFilterId && props.initialFilterId !== 'none' ? props.initialFilterId : 'none')

watch(() => props.initialFilterId, (id) => {
  filterId.value = id && id !== 'none' ? id : 'none'
})
const textLayers = ref([])
const stickers = ref([])
const strokes = ref([])
const activeTool = ref('none')
const brushColor = ref('#ffffff')
const brushSize = ref(4)
const drawing = ref(false)
const currentStroke = ref(null)
const selectedTextId = ref(null)
const selectedStickerId = ref(null)

watch(selectedTextId, (id) => {
  if (!id) return
  const layer = textLayers.value.find(l => l.id === id)
  if (layer && layer.scale == null) layer.scale = 1
})

let dragSticker = null
let scaleSticker = null
let pinchSticker = null
let dragText = null
let scaleText = null
let pinchText = null

const TEXT_COLORS = ['#ffffff', '#000000', '#ff6584', '#6c63ff', '#22c55e', '#fbbf24']
const BG_PRESETS = [
  'linear-gradient(135deg,#6c63ff 0%,#ff6584 100%)',
  'linear-gradient(135deg,#0ea5e9 0%,#6c63ff 100%)',
  'linear-gradient(135deg,#f97316 0%,#ec4899 100%)',
  'linear-gradient(135deg,#22c55e 0%,#14b8a6 100%)',
  '#1a1a2e',
  '#ffffff'
]
const STICKERS = ['😀', '😂', '❤️', '🔥', '👍', '🎉', '✨', '💯', '😍', '🤩', '👋', '💬']
const FILTERS = [
  { id: 'none', labelKey: 'stories.filterNone' },
  { id: 'grayscale', labelKey: 'stories.filterGray' },
  { id: 'sepia', labelKey: 'stories.filterSepia' },
  { id: 'vintage', labelKey: 'stories.filterVintage' },
  { id: 'warm', labelKey: 'stories.filterWarm' },
  { id: 'vivid', labelKey: 'stories.filterVivid' }
]

const filterCss = computed(() => {
  const map = {
    none: 'none',
    grayscale: 'grayscale(100%)',
    sepia: 'sepia(80%)',
    vintage: 'sepia(40%) contrast(1.1)',
    warm: 'sepia(30%) hue-rotate(-10deg)',
    cool: 'hue-rotate(180deg) saturate(0.85)',
    vivid: 'saturate(1.4) contrast(1.05)'
  }
  return map[filterId.value] || 'none'
})

const bgStyle = computed(() => ({
  background: props.textOnly ? props.backgroundColor : 'transparent'
}))

function addText() {
  const id = crypto.randomUUID()
  textLayers.value.push({
    id,
    text: t('stories.defaultText'),
    x: 50,
    y: 45,
    color: '#ffffff',
    fontSize: 22,
    scale: 1
  })
  selectedTextId.value = id
  selectedStickerId.value = null
  activeTool.value = 'text'
}

const selectedText = computed(() =>
  textLayers.value.find(l => l.id === selectedTextId.value) ?? null
)

const selectedSticker = computed(() =>
  stickers.value.find(s => s.id === selectedStickerId.value) ?? null
)

const MIN_LAYER_SCALE = 0.35
const MAX_LAYER_SCALE = 4
const MIN_STICKER_SCALE = MIN_LAYER_SCALE
const MAX_STICKER_SCALE = MAX_LAYER_SCALE

function clampScale(scale) {
  return Math.max(MIN_STICKER_SCALE, Math.min(MAX_STICKER_SCALE, scale))
}

function addSticker(emoji) {
  const id = crypto.randomUUID()
  stickers.value.push({
    id,
    emoji,
    x: 30 + Math.random() * 40,
    y: 30 + Math.random() * 40,
    scale: 1
  })
  selectedStickerId.value = id
  activeTool.value = 'sticker'
}

function removeSticker(id) {
  stickers.value = stickers.value.filter(s => s.id !== id)
  if (selectedStickerId.value === id) selectedStickerId.value = null
}

function removeText(id) {
  textLayers.value = textLayers.value.filter(l => l.id !== id)
  if (selectedTextId.value === id) selectedTextId.value = null
}

function textFontSize(layer) {
  return layer.fontSize * (layer.scale ?? 1)
}

function onTextInputFocus(layer) {
  selectedTextId.value = layer.id
  selectedStickerId.value = null
  activeTool.value = 'text'
  if (layer.scale == null) layer.scale = 1
}

function onTextPointerDown(e, layer) {
  if (activeTool.value === 'draw') return
  if (e.target.closest('.text-input')) {
    onTextInputFocus(layer)
    return
  }
  e.stopPropagation()
  onTextInputFocus(layer)
  if (layer.scale == null) layer.scale = 1

  if (e.touches?.length >= 2) {
    pinchText = { layer, startDist: touchDistance(e.touches), startScale: layer.scale }
    return
  }

  dragText = { layer, pointerId: e.pointerId }
  e.currentTarget.setPointerCapture?.(e.pointerId)
}

function onTextPointerMove(e, layer) {
  if (scaleText?.layer.id === layer.id) {
    e.stopPropagation()
    const dy = e.clientY - scaleText.startY
    layer.scale = clampScale(scaleText.startScale + dy * -0.008)
    return
  }

  if (pinchText?.layer.id === layer.id && e.touches?.length >= 2) {
    e.stopPropagation()
    const ratio = touchDistance(e.touches) / pinchText.startDist
    layer.scale = clampScale(pinchText.startScale * ratio)
    return
  }

  if (!dragText || dragText.layer.id !== layer.id) return
  if (e.pointerId !== dragText.pointerId) return
  e.stopPropagation()
  const p = pointerPct(e)
  layer.x = p.x
  layer.y = p.y
}

function onTextPointerEnd(e, layer) {
  if (dragText?.layer.id === layer.id && e.pointerId === dragText.pointerId) dragText = null
  if (scaleText?.layer.id === layer.id && e.pointerId === scaleText.pointerId) scaleText = null
  if (pinchText?.layer.id === layer.id) pinchText = null
  e.currentTarget?.releasePointerCapture?.(e.pointerId)
}

function onTextTouchStart(e, layer) {
  if (activeTool.value === 'draw') return
  if (e.target.closest('.text-input')) return
  onTextInputFocus(layer)
  if (e.touches.length >= 2) {
    pinchText = { layer, startDist: touchDistance(e.touches), startScale: layer.scale ?? 1 }
  } else if (e.touches.length === 1) {
    dragText = { layer, pointerId: -1 }
  }
}

function onTextTouchMove(e, layer) {
  if (e.touches.length >= 2 && pinchText?.layer.id === layer.id) {
    const ratio = touchDistance(e.touches) / pinchText.startDist
    layer.scale = clampScale(pinchText.startScale * ratio)
    return
  }
  if (e.touches.length === 1 && dragText?.layer.id === layer.id) {
    const p = pointerPctFromTouch(e.touches[0])
    layer.x = p.x
    layer.y = p.y
  }
}

function onTextTouchEnd() {
  dragText = null
  pinchText = null
}

function onTextScaleHandleDown(e, layer) {
  e.stopPropagation()
  onTextInputFocus(layer)
  scaleText = { layer, startY: e.clientY, startScale: layer.scale ?? 1, pointerId: e.pointerId }
  e.currentTarget.setPointerCapture?.(e.pointerId)
}

function onTextScaleHandleMove(e, layer) {
  if (!scaleText || scaleText.layer.id !== layer.id) return
  if (e.pointerId !== scaleText.pointerId) return
  e.stopPropagation()
  const dy = e.clientY - scaleText.startY
  layer.scale = clampScale(scaleText.startScale + dy * -0.008)
}

function onTextScaleHandleEnd(e, layer) {
  if (scaleText?.layer.id === layer.id && e.pointerId === scaleText.pointerId) scaleText = null
  e.currentTarget?.releasePointerCapture?.(e.pointerId)
}

function touchDistance(touches) {
  const dx = touches[0].clientX - touches[1].clientX
  const dy = touches[0].clientY - touches[1].clientY
  return Math.hypot(dx, dy)
}

function onStickerPointerDown(e, sticker) {
  if (activeTool.value === 'draw') return
  e.stopPropagation()
  selectedStickerId.value = sticker.id

  if (e.touches?.length >= 2) {
    pinchSticker = { sticker, startDist: touchDistance(e.touches), startScale: sticker.scale }
    return
  }

  dragSticker = { sticker, pointerId: e.pointerId }
  e.currentTarget.setPointerCapture?.(e.pointerId)
}

function onStickerPointerMove(e, sticker) {
  if (scaleSticker?.sticker.id === sticker.id) {
    e.stopPropagation()
    const dy = e.clientY - scaleSticker.startY
    sticker.scale = clampScale(scaleSticker.startScale + dy * -0.008)
    return
  }

  if (pinchSticker?.sticker.id === sticker.id && e.touches?.length >= 2) {
    e.stopPropagation()
    const ratio = touchDistance(e.touches) / pinchSticker.startDist
    sticker.scale = clampScale(pinchSticker.startScale * ratio)
    return
  }

  if (!dragSticker || dragSticker.sticker.id !== sticker.id) return
  if (e.pointerId !== dragSticker.pointerId) return
  e.stopPropagation()
  const p = pointerPct(e)
  sticker.x = p.x
  sticker.y = p.y
}

function onStickerPointerEnd(e, sticker) {
  if (dragSticker?.sticker.id === sticker.id && e.pointerId === dragSticker.pointerId) {
    dragSticker = null
  }
  if (scaleSticker?.sticker.id === sticker.id && e.pointerId === scaleSticker.pointerId) {
    scaleSticker = null
  }
  if (pinchSticker?.sticker.id === sticker.id) {
    pinchSticker = null
  }
  e.currentTarget?.releasePointerCapture?.(e.pointerId)
}

function pointerPctFromTouch(touch) {
  const el = containerRef.value
  if (!el) return { x: 50, y: 50 }
  const rect = el.getBoundingClientRect()
  return {
    x: Math.max(0, Math.min(100, ((touch.clientX - rect.left) / rect.width) * 100)),
    y: Math.max(0, Math.min(100, ((touch.clientY - rect.top) / rect.height) * 100))
  }
}

function onStickerTouchStart(e, sticker) {
  if (activeTool.value === 'draw') return
  selectedStickerId.value = sticker.id
  if (e.touches.length >= 2) {
    pinchSticker = { sticker, startDist: touchDistance(e.touches), startScale: sticker.scale }
  } else if (e.touches.length === 1) {
    dragSticker = { sticker, pointerId: -1 }
  }
}

function onStickerTouchMove(e, sticker) {
  if (e.touches.length >= 2 && pinchSticker?.sticker.id === sticker.id) {
    const ratio = touchDistance(e.touches) / pinchSticker.startDist
    sticker.scale = clampScale(pinchSticker.startScale * ratio)
    return
  }
  if (e.touches.length === 1 && dragSticker?.sticker.id === sticker.id) {
    const p = pointerPctFromTouch(e.touches[0])
    sticker.x = p.x
    sticker.y = p.y
  }
}

function onStickerTouchEnd() {
  dragSticker = null
  pinchSticker = null
}

function onScaleHandleDown(e, sticker) {
  e.stopPropagation()
  selectedStickerId.value = sticker.id
  scaleSticker = { sticker, startY: e.clientY, startScale: sticker.scale, pointerId: e.pointerId }
  e.currentTarget.setPointerCapture?.(e.pointerId)
}

function onScaleHandleMove(e, sticker) {
  if (!scaleSticker || scaleSticker.sticker.id !== sticker.id) return
  if (e.pointerId !== scaleSticker.pointerId) return
  e.stopPropagation()
  const dy = e.clientY - scaleSticker.startY
  sticker.scale = clampScale(scaleSticker.startScale + dy * -0.008)
}

function onScaleHandleEnd(e, sticker) {
  if (scaleSticker?.sticker.id === sticker.id && e.pointerId === scaleSticker.pointerId) {
    scaleSticker = null
  }
  e.currentTarget?.releasePointerCapture?.(e.pointerId)
}

function onStagePointerDown(e) {
  if (e.target.closest('.sticker-layer') || e.target.closest('.text-layer')) return
  selectedStickerId.value = null
  selectedTextId.value = null
  startDraw(e)
}

function startDraw(e) {
  if (activeTool.value !== 'draw') return
  drawing.value = true
  const p = pointerPct(e)
  currentStroke.value = { color: brushColor.value, size: brushSize.value, points: [p] }
}

function moveDraw(e) {
  if (!drawing.value || !currentStroke.value) return
  currentStroke.value.points.push(pointerPct(e))
}

function endDraw() {
  if (currentStroke.value) {
    strokes.value.push({ ...currentStroke.value, points: [...currentStroke.value.points] })
    currentStroke.value = null
  }
  drawing.value = false
}

function pointerPct(e) {
  const el = containerRef.value
  if (!el) return { x: 50, y: 50 }
  const rect = el.getBoundingClientRect()
  const clientX = e.touches?.[0]?.clientX ?? e.clientX
  const clientY = e.touches?.[0]?.clientY ?? e.clientY
  return {
    x: Math.max(0, Math.min(100, ((clientX - rect.left) / rect.width) * 100)),
    y: Math.max(0, Math.min(100, ((clientY - rect.top) / rect.height) * 100))
  }
}

async function exportImage() {
  const canvas = canvasRef.value
  if (!canvas) return null

  try {
    return await exportStoryImage(canvas, {
      textOnly: props.textOnly,
      imageSrc: props.imageSrc,
      videoSrc: props.videoSrc,
      backgroundColor: props.backgroundColor,
      filterCss: filterCss.value,
      strokes: strokes.value,
      textLayers: textLayers.value,
      stickers: stickers.value,
      textFontSize,
      videoPreviewLabel: t('stories.videoPreviewNote')
    })
  } catch (err) {
    if (err instanceof StoryExportError) throw err
    throw new StoryExportError(err?.message || 'Story export failed')
  }
}

function hasEditorChanges() {
  if (filterId.value !== 'none') return true
  if (textLayers.value.length || stickers.value.length || strokes.value.length) return true
  return false
}

defineExpose({
  exportImage,
  hasEditorChanges,
  getFilterId: () => filterId.value,
  getOverlayJson: () => JSON.stringify({ textLayers: textLayers.value, stickers: stickers.value, strokes: strokes.value })
})

watch(filterId, () => {})
</script>

<template>
  <div class="editor-root">
    <div
      ref="containerRef"
      class="editor-stage"
      :style="bgStyle"
      @pointerdown="onStagePointerDown"
      @pointermove="moveDraw"
      @pointerup="endDraw"
      @pointerleave="endDraw"
    >
      <img
        v-if="imageSrc && !textOnly"
        :src="imageSrc"
        class="stage-media"
        :style="{ filter: filterCss }"
        alt=""
      />
      <video
        v-else-if="videoSrc && !textOnly"
        :src="videoSrc"
        class="stage-media"
        :style="{ filter: filterCss }"
        playsinline
        muted
        loop
        autoplay
      />

      <svg class="draw-layer" viewBox="0 0 100 100" preserveAspectRatio="none">
        <polyline
          v-for="(stroke, si) in strokes"
          :key="si"
          :points="stroke.points.map(p => `${p.x},${p.y}`).join(' ')"
          fill="none"
          :stroke="stroke.color"
          :stroke-width="stroke.size * 0.15"
          stroke-linecap="round"
        />
        <polyline
          v-if="currentStroke"
          :points="currentStroke.points.map(p => `${p.x},${p.y}`).join(' ')"
          fill="none"
          :stroke="currentStroke.color"
          :stroke-width="currentStroke.size * 0.15"
          stroke-linecap="round"
        />
      </svg>

      <div
        v-for="layer in textLayers"
        :key="layer.id"
        class="text-layer"
        :class="{ selected: selectedTextId === layer.id }"
        :style="{ left: `${layer.x}%`, top: `${layer.y}%`, color: layer.color, fontSize: `${textFontSize(layer)}px` }"
        @pointerdown="onTextPointerDown($event, layer)"
        @pointermove="onTextPointerMove($event, layer)"
        @pointerup="onTextPointerEnd($event, layer)"
        @pointercancel="onTextPointerEnd($event, layer)"
        @touchstart.stop="onTextTouchStart($event, layer)"
        @touchmove.stop.prevent="onTextTouchMove($event, layer)"
        @touchend.stop="onTextTouchEnd"
        @touchcancel.stop="onTextTouchEnd"
      >
        <input
          v-model="layer.text"
          class="text-input"
          @pointerdown.stop
          @focus="onTextInputFocus(layer)"
          @click.stop
        />
        <button
          v-if="selectedTextId === layer.id"
          type="button"
          class="layer-delete"
          aria-label="حذف"
          @pointerdown.stop
          @click.stop="removeText(layer.id)"
        >×</button>
        <span
          v-if="selectedTextId === layer.id"
          class="layer-scale-handle"
          @pointerdown.stop="onTextScaleHandleDown($event, layer)"
          @pointermove.stop="onTextScaleHandleMove($event, layer)"
          @pointerup.stop="onTextScaleHandleEnd($event, layer)"
          @pointercancel.stop="onTextScaleHandleEnd($event, layer)"
        />
      </div>

      <div
        v-for="s in stickers"
        :key="s.id"
        class="sticker-layer"
        :class="{ selected: selectedStickerId === s.id }"
        :style="{ left: `${s.x}%`, top: `${s.y}%`, fontSize: `${48 * s.scale}px` }"
        @pointerdown="onStickerPointerDown($event, s)"
        @pointermove="onStickerPointerMove($event, s)"
        @pointerup="onStickerPointerEnd($event, s)"
        @pointercancel="onStickerPointerEnd($event, s)"
        @touchstart.stop="onStickerTouchStart($event, s)"
        @touchmove.stop.prevent="onStickerTouchMove($event, s)"
        @touchend.stop="onStickerTouchEnd"
        @touchcancel.stop="onStickerTouchEnd"
      >
        <span class="sticker-emoji">{{ s.emoji }}</span>
        <button
          v-if="selectedStickerId === s.id"
          type="button"
          class="layer-delete"
          aria-label="حذف"
          @pointerdown.stop
          @click.stop="removeSticker(s.id)"
        >×</button>
        <span
          v-if="selectedStickerId === s.id"
          class="layer-scale-handle"
          @pointerdown.stop="onScaleHandleDown($event, s)"
          @pointermove.stop="onScaleHandleMove($event, s)"
          @pointerup.stop="onScaleHandleEnd($event, s)"
          @pointercancel.stop="onScaleHandleEnd($event, s)"
        />
      </div>
    </div>

    <canvas ref="canvasRef" class="export-canvas" aria-hidden="true" />

    <div class="tools-panel">
      <div class="tool-tabs" role="tablist">
        <button type="button" class="tool-tab" :class="{ active: activeTool === 'text' }" @click="addText">{{ t('stories.toolText') }}</button>
        <button type="button" class="tool-tab" :class="{ active: activeTool === 'draw' }" @click="activeTool = 'draw'">{{ t('stories.toolDraw') }}</button>
        <button type="button" class="tool-tab" :class="{ active: activeTool === 'sticker' }" @click="activeTool = 'sticker'">{{ t('stories.toolSticker') }}</button>
        <button type="button" class="tool-tab" :class="{ active: activeTool === 'filter' }" @click="activeTool = 'filter'">{{ t('stories.toolFilter') }}</button>
      </div>

      <div v-if="activeTool === 'text' && selectedTextId" class="options-card">
        <p class="options-label">{{ t('stories.textEdit') }}</p>
        <input
          :value="textLayers.find(l => l.id === selectedTextId)?.text"
          class="options-input"
          :placeholder="t('stories.defaultText')"
          @input="(e) => { const l = textLayers.find(x => x.id === selectedTextId); if (l) l.text = e.target.value }"
        />
        <p class="options-sublabel">{{ t('stories.textColor') }}</p>
        <div class="swatch-row">
          <button
            v-for="c in TEXT_COLORS"
            :key="c"
            type="button"
            class="swatch"
            :class="{ selected: textLayers.find(x => x.id === selectedTextId)?.color === c }"
            :style="{ background: c }"
            @click="() => { const l = textLayers.find(x => x.id === selectedTextId); if (l) l.color = c }"
          />
        </div>
        <p v-if="selectedText" class="text-hint">{{ t('stories.textMoveHint') }}</p>
        <div v-if="selectedText" class="range-row">
          <span class="range-label">{{ t('stories.textSize') }}</span>
          <input
            v-model.number="selectedText.scale"
            class="options-range"
            type="range"
            :min="MIN_LAYER_SCALE"
            :max="MAX_LAYER_SCALE"
            step="0.05"
          />
        </div>
      </div>

      <div v-else-if="activeTool === 'draw'" class="options-card">
        <p class="options-sublabel">{{ t('stories.brushColor') }}</p>
        <div class="swatch-row">
          <button
            v-for="c in TEXT_COLORS"
            :key="c"
            type="button"
            class="swatch"
            :class="{ selected: brushColor === c }"
            :style="{ background: c }"
            @click="brushColor = c"
          />
        </div>
        <div class="range-row">
          <span class="range-label">{{ t('stories.brushSize') }}</span>
          <input v-model.number="brushSize" class="options-range" type="range" min="2" max="12" />
          <span class="range-value">{{ brushSize }}</span>
        </div>
      </div>

      <div v-else-if="activeTool === 'sticker'" class="options-card">
        <p class="options-label">{{ t('stories.pickSticker') }}</p>
        <div class="stickers-grid">
          <button v-for="em in STICKERS" :key="em" type="button" class="sticker-btn" @click="addSticker(em)">{{ em }}</button>
        </div>
        <div v-if="selectedSticker" class="sticker-adjust">
          <p class="sticker-hint">{{ t('stories.stickerMoveHint') }}</p>
          <div class="range-row">
            <span class="range-label">{{ t('stories.stickerSize') }}</span>
            <input
              v-model.number="selectedSticker.scale"
              class="options-range"
              type="range"
              :min="MIN_STICKER_SCALE"
              :max="MAX_STICKER_SCALE"
              step="0.05"
            />
          </div>
        </div>
      </div>

      <div v-else-if="activeTool === 'filter'" class="options-card">
        <p class="options-label">{{ t('stories.filtersLabel') }}</p>
        <div class="chip-scroll">
          <button
            v-for="f in FILTERS"
            :key="f.id"
            type="button"
            class="filter-chip"
            :class="{ active: filterId === f.id }"
            @click="filterId = f.id"
          >{{ t(f.labelKey) }}</button>
        </div>
      </div>

      <div v-if="textOnly" class="options-card options-card--bg">
        <p class="options-label">{{ t('stories.bgLabel') }}</p>
        <div class="bg-row">
          <button
            v-for="(bg, i) in BG_PRESETS"
            :key="i"
            type="button"
            class="bg-chip"
            :class="{ active: backgroundColor === bg }"
            :style="{ background: bg }"
            @click="emit('update:backgroundColor', bg)"
          />
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.editor-root {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}

.editor-stage {
  position: relative;
  flex: 1;
  min-height: 280px;
  max-height: 55vh;
  margin: 0 auto;
  width: 100%;
  max-width: 320px;
  aspect-ratio: 9/16;
  border-radius: 16px;
  overflow: hidden;
  background: #111;
  touch-action: none;
}

.stage-media {
  width: 100%;
  height: 100%;
  object-fit: contain;
  object-position: center;
}

.draw-layer {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  pointer-events: none;
}

.text-layer {
  position: absolute;
  transform: translate(-50%, -50%);
  max-width: 90%;
  z-index: 5;
  touch-action: none;
  cursor: grab;
}

.text-layer.selected {
  z-index: 11;
  cursor: grabbing;
}

.text-layer.selected::before {
  content: '';
  position: absolute;
  inset: -10px;
  border: 2px dashed rgba(255, 255, 255, 0.9);
  border-radius: 8px;
  pointer-events: none;
}

.text-input {
  background: transparent;
  border: none;
  color: inherit;
  font-size: inherit;
  font-weight: 700;
  font-family: 'Cairo', sans-serif;
  text-align: center;
  width: min(240px, 88vw);
  min-width: 80px;
  text-shadow: 0 2px 8px rgba(0, 0, 0, 0.6);
  cursor: text;
  touch-action: manipulation;
}

.layer-delete {
  position: absolute;
  top: -14px;
  inset-inline-start: -14px;
  width: 26px;
  height: 26px;
  border-radius: 50%;
  border: none;
  background: rgba(0, 0, 0, 0.65);
  color: #fff;
  font-size: 18px;
  line-height: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  z-index: 2;
  padding: 0;
}

.layer-scale-handle {
  position: absolute;
  bottom: -12px;
  inset-inline-end: -12px;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: #fff;
  border: 2px solid var(--primary);
  box-shadow: 0 1px 6px rgba(0, 0, 0, 0.35);
  touch-action: none;
  cursor: nwse-resize;
  z-index: 2;
}

.text-hint {
  margin: 10px 0 0;
  font-size: 10px;
  color: var(--text-muted);
  line-height: 1.45;
}

.sticker-layer {
  position: absolute;
  transform: translate(-50%, -50%);
  z-index: 4;
  user-select: none;
  touch-action: none;
  cursor: grab;
  display: flex;
  align-items: center;
  justify-content: center;
  line-height: 1;
}

.sticker-layer.selected {
  z-index: 12;
  cursor: grabbing;
}

.sticker-layer.selected::before {
  content: '';
  position: absolute;
  inset: -10px;
  border: 2px dashed rgba(255, 255, 255, 0.9);
  border-radius: 8px;
  pointer-events: none;
}

.sticker-emoji {
  pointer-events: none;
}

.export-canvas {
  position: fixed;
  left: -10000px;
  top: 0;
  width: 1px;
  height: 1px;
  opacity: 0;
  pointer-events: none;
}

.tools-panel {
  flex-shrink: 0;
  padding: 10px 12px calc(10px + var(--safe-bottom));
  background: var(--bg-card);
  border-top: 1px solid var(--border);
}

.tool-tabs {
  display: flex;
  gap: 4px;
  padding: 4px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
  border-radius: 14px;
}

.tool-tab {
  flex: 1;
  min-width: 0;
  padding: 10px 4px;
  font-size: 12px;
  font-weight: 600;
  border: none;
  border-radius: 10px;
  background: transparent;
  color: var(--text-muted);
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  transition: background 0.2s, color 0.2s, box-shadow 0.2s;
}

.tool-tab.active {
  background: var(--bg-card);
  color: var(--primary);
  box-shadow: 0 1px 6px rgba(0, 0, 0, 0.12);
}

.options-card {
  margin-top: 10px;
  padding: 12px;
  border-radius: 14px;
  background: var(--bg-elevated);
  border: 1px solid var(--border);
}

.options-card--bg {
  margin-top: 8px;
}

.options-label {
  margin: 0 0 10px;
  font-size: 12px;
  font-weight: 700;
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
}

.options-sublabel {
  margin: 0 0 8px;
  font-size: 11px;
  font-weight: 600;
  color: var(--text-muted);
  font-family: 'Cairo', sans-serif;
}

.options-input {
  width: 100%;
  padding: 10px 12px;
  margin-bottom: 12px;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--bg-card);
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  font-size: 14px;
}

.options-input:focus {
  outline: none;
  border-color: var(--primary);
}

.swatch-row {
  display: flex;
  gap: 10px;
  overflow-x: auto;
  padding-bottom: 2px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.swatch-row::-webkit-scrollbar {
  display: none;
}

.swatch {
  flex-shrink: 0;
  width: 34px;
  height: 34px;
  border-radius: 50%;
  border: 2px solid transparent;
  box-shadow: 0 0 0 1px var(--border);
  cursor: pointer;
  transition: transform 0.15s, box-shadow 0.15s;
}

.swatch.selected {
  box-shadow: 0 0 0 2px var(--primary);
  transform: scale(1.06);
}

.range-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-top: 12px;
}

.range-label {
  flex-shrink: 0;
  font-size: 11px;
  font-weight: 600;
  color: var(--text-secondary);
  font-family: 'Cairo', sans-serif;
  min-width: 52px;
}

.range-value {
  flex-shrink: 0;
  width: 22px;
  font-size: 12px;
  font-weight: 700;
  color: var(--primary);
  text-align: center;
  font-family: 'Cairo', sans-serif;
}

.options-range {
  flex: 1;
  min-width: 0;
  height: 4px;
  accent-color: var(--primary);
}

.stickers-grid {
  display: grid;
  grid-template-columns: repeat(6, 1fr);
  gap: 6px;
}

.sticker-btn {
  aspect-ratio: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 24px;
  line-height: 1;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 10px;
  cursor: pointer;
  transition: transform 0.12s, background 0.12s, border-color 0.12s;
}

.sticker-btn:active {
  transform: scale(0.94);
  background: rgba(108, 99, 255, 0.12);
  border-color: rgba(108, 99, 255, 0.45);
}

.sticker-adjust {
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid var(--border);
}

.sticker-hint {
  font-size: 10px;
  color: var(--text-muted);
  margin: 0 0 8px;
  line-height: 1.45;
}

.chip-scroll {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding-bottom: 2px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.chip-scroll::-webkit-scrollbar {
  display: none;
}

.filter-chip {
  flex-shrink: 0;
  padding: 8px 14px;
  font-size: 12px;
  font-weight: 600;
  border-radius: 999px;
  border: 1px solid var(--border);
  background: var(--bg-card);
  color: var(--text-secondary);
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
  transition: background 0.15s, border-color 0.15s, color 0.15s;
}

.filter-chip.active {
  background: rgba(108, 99, 255, 0.18);
  border-color: var(--primary);
  color: var(--primary);
}

.bg-row {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding-bottom: 2px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.bg-row::-webkit-scrollbar {
  display: none;
}

.bg-chip {
  flex-shrink: 0;
  width: 40px;
  height: 40px;
  padding: 0;
  border-radius: 10px;
  border: 2px solid transparent;
  cursor: pointer;
  transition: transform 0.15s, border-color 0.15s;
}

.bg-chip.active {
  border-color: var(--primary);
  transform: scale(1.05);
}
</style>

