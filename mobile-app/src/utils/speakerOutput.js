/**
 * محاولة توجيه صوت عنصر &lt;video&gt;/&lt;audio&gt; إلى مكبّر الصوت أو السماعة الافتراضية (أذن).
 * يعتمد على HTMLMediaElement.setSinkId حيث يُدعم (Chrome/Android WebView غالباً).
 * عند الفشل يعيد ok: false ليستخدم المتصل وسيلة احتياطية (مثل muted).
 */
export async function applyRemoteSpeakerRouting(mediaEl, speakerOn) {
  if (!mediaEl) return { ok: false, reason: 'no-element' }

  if (typeof mediaEl.setSinkId !== 'function') {
    return { ok: false, reason: 'no-setSinkId' }
  }

  try {
    if (!navigator.mediaDevices?.enumerateDevices) {
      return { ok: false, reason: 'no-enumerateDevices' }
    }

    const outs = (await navigator.mediaDevices.enumerateDevices()).filter(
      (d) => d.kind === 'audiooutput'
    )
    if (!outs.length) return { ok: false, reason: 'no-outputs' }

    const label = (s) => (s || '').toLowerCase()

    if (speakerOn) {
      const speakerLike =
        outs.find((o) => {
          const l = label(o.label)
          return (
            l.includes('speaker') ||
            l.includes('loud') ||
            l.includes('built-in speaker') ||
            l.includes('phone speaker')
          )
        }) ||
        outs.find((o) => o.deviceId && o.deviceId !== 'default') ||
        outs[0]
      await mediaEl.setSinkId(speakerLike.deviceId)
    } else {
      const earLike =
        outs.find((o) => {
          const l = label(o.label)
          return (
            l.includes('earpiece') ||
            l.includes('receiver') ||
            l.includes('communication') ||
            l.includes('telephony') ||
            l.includes('ear')
          )
        }) || outs.find((o) => o.deviceId === 'default') || outs[0]
      await mediaEl.setSinkId(earLike.deviceId)
    }
    return { ok: true }
  } catch (e) {
    return { ok: false, reason: e?.message || 'setSinkId-error' }
  }
}
