import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');
const src = path.join(root, 'icons');
const dest = path.join(root, 'public', 'icons');

// Copy icons to public for Vite
if (fs.existsSync(src)) {
  if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
  fs.readdirSync(src).forEach((f) => {
    fs.copyFileSync(path.join(src, f), path.join(dest, f));
  });
}

// Fix manifest paths (capacitor-assets uses ../icons/, we need /icons/ for web)
const manifestPath = path.join(root, 'public', 'manifest.webmanifest');
if (fs.existsSync(manifestPath)) {
  let m = fs.readFileSync(manifestPath, 'utf8');
  m = m.replace(/\.\.\/icons\//g, '/icons/');
  fs.writeFileSync(manifestPath, m);
}
