<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'

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
    fontSize: 22
  })
  selectedTextId.value = id
  activeTool.value = 'text'
}

function addSticker(emoji) {
  stickers.value.push({
    id: crypto.randomUUID(),
    emoji,
    x: 30 + Math.random() * 40,
    y: 30 + Math.random() * 40,
    scale: 1
  })
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

function onDragText(e, layer) {
  const p = pointerPct(e)
  layer.x = p.x
  layer.y = p.y
}

async function exportImage() {
  const canvas = canvasRef.value
  const container = containerRef.value
  if (!canvas || !container) return null

  const w = 360
  const h = 640
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')

  if (props.textOnly) {
    const grd = ctx.createLinearGradient(0, 0, w, h)
    grd.addColorStop(0, '#6c63ff')
    grd.addColorStop(1, '#ff6584')
    ctx.fillStyle = grd
    ctx.fillRect(0, 0, w, h)
  } else if (props.imageSrc) {
    const img = await loadImage(props.imageSrc)
    ctx.filter = filterCss.value
    drawCover(ctx, img, w, h)
    ctx.filter = 'none'
  } else if (props.videoSrc) {
    ctx.fillStyle = '#111'
    ctx.fillRect(0, 0, w, h)
    ctx.fillStyle = '#fff'
    ctx.font = '16px Cairo'
    ctx.textAlign = 'center'
    ctx.fillText(t('stories.videoPreviewNote'), w / 2, h / 2)
  }

  for (const stroke of strokes.value) {
    ctx.strokeStyle = stroke.color
    ctx.lineWidth = stroke.size
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.beginPath()
    stroke.points.forEach((p, i) => {
      const x = (p.x / 100) * w
      const y = (p.y / 100) * h
      if (i === 0) ctx.moveTo(x, y)
      else ctx.lineTo(x, y)
    })
    ctx.stroke()
  }

  for (const layer of textLayers.value) {
    ctx.fillStyle = layer.color
    ctx.font = `bold ${layer.fontSize}px Cairo, sans-serif`
    ctx.textAlign = 'center'
    ctx.fillText(layer.text, (layer.x / 100) * w, (layer.y / 100) * h)
  }

  for (const s of stickers.value) {
    ctx.font = `${48 * s.scale}px serif`
    ctx.textAlign = 'center'
    ctx.fillText(s.emoji, (s.x / 100) * w, (s.y / 100) * h)
  }

  return new Promise((resolve) => {
    canvas.toBlob((blob) => resolve(blob), 'image/jpeg', 0.92)
  })
}

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => resolve(img)
    img.onerror = reject
    img.src = src
  })
}

function drawCover(ctx, img, w, h) {
  const ir = img.width / img.height
  const cr = w / h
  let sw, sh, sx, sy
  if (ir > cr) {
    sh = img.height
    sw = sh * cr
    sx = (img.width - sw) / 2
    sy = 0
  } else {
    sw = img.width
    sh = sw / cr
    sx = 0
    sy = (img.height - sh) / 2
  }
  ctx.drawImage(img, sx, sy, sw, sh, 0, 0, w, h)
}

defineExpose({
  exportImage,
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
      @pointerdown="startDraw"
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
        :style="{ left: `${layer.x}%`, top: `${layer.y}%`, color: layer.color, fontSize: `${layer.fontSize}px` }"
        @pointerdown.stop="selectedTextId = layer.id"
        @pointermove.stop="(e) => onDragText(e, layer)"
      >
        <input v-model="layer.text" class="text-input" @click.stop />
      </div>

      <span
        v-for="s in stickers"
        :key="s.id"
        class="sticker-layer"
        :style="{ left: `${s.x}%`, top: `${s.y}%`, fontSize: `${48 * s.scale}px` }"
      >{{ s.emoji }}</span>
    </div>

    <canvas ref="canvasRef" class="export-canvas" aria-hidden="true" />

    <div class="tools-panel">
      <div class="tool-row">
        <button type="button" :class="{ active: activeTool === 'text' }" @click="addText">{{ t('stories.toolText') }}</button>
        <button type="button" :class="{ active: activeTool === 'draw' }" @click="activeTool = 'draw'">{{ t('stories.toolDraw') }}</button>
        <button type="button" :class="{ active: activeTool === 'sticker' }" @click="activeTool = 'sticker'">{{ t('stories.toolSticker') }}</button>
        <button type="button" :class="{ active: activeTool === 'filter' }" @click="activeTool = 'filter'">{{ t('stories.toolFilter') }}</button>
      </div>

      <div v-if="activeTool === 'text' && selectedTextId" class="sub-panel">
        <input
          :value="textLayers.find(l => l.id === selectedTextId)?.text"
          class="sub-input"
          @input="(e) => { const l = textLayers.find(x => x.id === selectedTextId); if (l) l.text = e.target.value }"
        />
        <div class="color-row">
          <button
            v-for="c in TEXT_COLORS"
            :key="c"
            type="button"
            class="color-dot"
            :style="{ background: c }"
            @click="() => { const l = textLayers.find(x => x.id === selectedTextId); if (l) l.color = c }"
          />
        </div>
      </div>

      <div v-if="activeTool === 'draw'" class="sub-panel">
        <div class="color-row">
          <button
            v-for="c in TEXT_COLORS"
            :key="c"
            type="button"
            class="color-dot"
            :style="{ background: c }"
            @click="brushColor = c"
          />
        </div>
        <input v-model.number="brushSize" type="range" min="2" max="12" />
      </div>

      <div v-if="activeTool === 'sticker'" class="sub-panel stickers-grid">
        <button v-for="em in STICKERS" :key="em" type="button" class="sticker-btn" @click="addSticker(em)">{{ em }}</button>
      </div>

      <div v-if="activeTool === 'filter'" class="sub-panel filter-row">
        <button
          v-for="f in FILTERS"
          :key="f.id"
          type="button"
          class="filter-chip"
          :class="{ active: filterId === f.id }"
          @click="filterId = f.id"
        >{{ t(f.labelKey) }}</button>
      </div>

      <div v-if="textOnly" class="sub-panel bg-row">
        <button
          v-for="(bg, i) in BG_PRESETS"
          :key="i"
          type="button"
          class="bg-chip"
          :style="{ background: bg }"
          @click="emit('update:backgroundColor', bg)"
        />
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
  object-fit: cover;
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
}
.text-layer.selected {
  outline: 2px dashed rgba(255, 255, 255, 0.8);
}

.text-input {
  background: transparent;
  border: none;
  color: inherit;
  font-size: inherit;
  font-weight: 700;
  font-family: 'Cairo', sans-serif;
  text-align: center;
  width: 200px;
  text-shadow: 0 2px 8px rgba(0, 0, 0, 0.6);
}

.sticker-layer {
  position: absolute;
  transform: translate(-50%, -50%);
  z-index: 4;
  user-select: none;
}

.export-canvas {
  display: none;
}

.tools-panel {
  flex-shrink: 0;
  padding: 12px;
  background: var(--bg-card);
  border-top: 1px solid var(--border);
}

.tool-row {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
  margin-bottom: 8px;
}

.tool-row button {
  flex: 1;
  min-width: 0;
  padding: 8px 6px;
  font-size: 11px;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--bg-elevated);
  color: var(--text-primary);
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}
.tool-row button.active {
  background: rgba(108, 99, 255, 0.2);
  border-color: var(--primary);
  color: var(--primary);
}

.sub-panel {
  margin-top: 8px;
}

.sub-input {
  width: 100%;
  padding: 8px;
  border-radius: 8px;
  border: 1px solid var(--border);
  font-family: 'Cairo', sans-serif;
  margin-bottom: 8px;
}

.color-row {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.color-dot {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  border: 2px solid var(--border);
  cursor: pointer;
}

.stickers-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.sticker-btn {
  font-size: 28px;
  background: var(--bg-elevated);
  border: none;
  border-radius: 8px;
  padding: 4px 8px;
  cursor: pointer;
}

.filter-row,
.bg-row {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.filter-chip,
.bg-chip {
  padding: 6px 10px;
  font-size: 11px;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--bg-elevated);
  font-family: 'Cairo', sans-serif;
  cursor: pointer;
}
.filter-chip.active {
  border-color: var(--primary);
  color: var(--primary);
}

.bg-chip {
  width: 36px;
  height: 36px;
  padding: 0;
}
</style>

