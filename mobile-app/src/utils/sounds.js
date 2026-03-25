/**
 * نغمة طلب اتصال - تُكرّر حتى يتم إيقافها
 * يستخدم Web Audio API - يعمل على الويب و Android و iOS
 */
let incomingCallInterval = null
/** سياق واحد لكل جلسة رنين؛ عند الإيقاف يُغلق فيصمت الصوت فوراً */
let ringAudioContext = null

function getOrCreateRingContext() {
  const Ctx = window.AudioContext || window.webkitAudioContext
  if (!Ctx) return null
  if (!ringAudioContext || ringAudioContext.state === 'closed') {
    ringAudioContext = new Ctx()
  }
  return ringAudioContext
}

function playOneRing() {
  try {
    const ctx = getOrCreateRingContext()
    if (!ctx) return
    if (ctx.state === 'suspended') {
      ctx.resume().catch(() => {})
    }

    const tBase = ctx.currentTime

    const playTone = (freq, startOffset, duration) => {
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      osc.connect(gain)
      gain.connect(ctx.destination)
      osc.frequency.value = freq
      osc.type = 'sine'
      const start = tBase + startOffset
      gain.gain.setValueAtTime(0.25, start)
      gain.gain.exponentialRampToValueAtTime(0.01, start + duration)
      osc.start(start)
      osc.stop(start + duration)
    }

    playTone(523.25, 0, 0.2)
    playTone(659.25, 0.25, 0.2)
    playTone(523.25, 0.55, 0.2)
    playTone(659.25, 0.8, 0.25)
  } catch (e) {
    console.warn('[sounds] Could not play incoming call sound:', e)
  }
}

function startIncomingCallSound() {
  stopIncomingCallSound()
  playOneRing()
  incomingCallInterval = setInterval(playOneRing, 2200)
}

function stopIncomingCallSound() {
  if (incomingCallInterval) {
    clearInterval(incomingCallInterval)
    incomingCallInterval = null
  }
  if (ringAudioContext && ringAudioContext.state !== 'closed') {
    try {
      ringAudioContext.close()
    } catch {
      /* ignore */
    }
    ringAudioContext = null
  }
}

export { startIncomingCallSound, stopIncomingCallSound }
