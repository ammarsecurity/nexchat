/**
 * بعد `cap sync ios` يُعاد توليد packageClassList من بلجنات npm فقط.
 * نُضيف تسجيل SpeakerAudioPlugin المحلي (CapApp-SPM) حتى يحمّله CapacitorBridge.
 * يُستدعى من `capacitor:sync:after` عند مزامنة iOS فقط.
 */
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const capJson = path.join(__dirname, '../ios/App/App/capacitor.config.json')
/** اسم الفئة كما يتوقعه NSClassFromString لوحدة Swift SPM (CapApp-SPM → CapApp_SPM) */
const CLASS_ID = 'CapApp_SPM.SpeakerAudioPlugin'

const plat = process.env.CAPACITOR_PLATFORM_NAME
if (plat && plat !== 'ios') {
  process.exit(0)
}

try {
  if (!fs.existsSync(capJson)) {
    process.exit(0)
  }
  const raw = fs.readFileSync(capJson, 'utf8')
  const j = JSON.parse(raw)
  if (!Array.isArray(j.packageClassList)) {
    j.packageClassList = []
  }
  j.packageClassList = j.packageClassList.filter((x) => x !== 'SpeakerAudioPlugin')
  if (!j.packageClassList.includes(CLASS_ID)) {
    j.packageClassList.push(CLASS_ID)
  }
  fs.writeFileSync(capJson, JSON.stringify(j, null, '\t') + '\n', 'utf8')
} catch (e) {
  console.warn('[ios-speaker-plugin-classlist]', e.message)
  process.exitCode = 0
}
