// Regenerates assets/i18n/{ar,en}.json from the Vue app locale files so both apps share the same keys.
import fs from 'fs'
import path from 'path'
import { fileURLToPath, pathToFileURL } from 'url'

const here = path.dirname(fileURLToPath(import.meta.url))
const srcDir = path.resolve(here, '../../mobile-app/src/i18n/locales')
const outDir = path.resolve(here, '../assets/i18n')
fs.mkdirSync(outDir, { recursive: true })

for (const lang of ['ar', 'en']) {
  const mod = await import(pathToFileURL(path.join(srcDir, `${lang}.js`)).href)
  fs.writeFileSync(path.join(outDir, `${lang}.json`), JSON.stringify(mod.default, null, 2), 'utf8')
  console.log(`wrote ${lang}.json`)
}
