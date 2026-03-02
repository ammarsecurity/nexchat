/**
 * نغمة طلب اتصال - تُكرّر حتى يتم إيقافها
 * يستخدم Web Audio API - يعمل على الويب و Android و iOS
 */
let incomingCallInterval = null

function playOneRing() {
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext
    if (!Ctx) return

    const ctx = new Ctx()

    const playTone = (freq, startTime, duration) => {
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      osc.connect(gain)
      gain.connect(ctx.destination)
      osc.frequency.value = freq
      osc.type = 'sine'
      gain.gain.setValueAtTime(0.25, startTime)
      gain.gain.exponentialRampToValueAtTime(0.01, startTime + duration)
      osc.start(startTime)
      osc.stop(startTime + duration)
    }

    // نغمة مزدوجة تشبه تنبيه الاتصال (C5 - E5)
    playTone(523.25, 0, 0.2)      // C5
    playTone(659.25, 0.25, 0.2)   // E5
    playTone(523.25, 0.55, 0.2)   // C5
    playTone(659.25, 0.8, 0.25)   // E5
  } catch (e) {
    console.warn('[sounds] Could not play incoming call sound:', e)
  }
}

function startIncomingCallSound() {
  stopIncomingCallSound()
  playOneRing()
  incomingCallInterval = setInterval(playOneRing, 2200) // تكرار كل ~2.2 ثانية
}

function stopIncomingCallSound() {
  if (incomingCallInterval) {
    clearInterval(incomingCallInterval)
    incomingCallInterval = null
  }
}

export { startIncomingCallSound, stopIncomingCallSound }
