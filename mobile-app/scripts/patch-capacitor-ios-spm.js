#!/usr/bin/env node
/**
 * Capacitor puts static Cordova plugins (e.g. OneSignal) in sourcesstatic/ but
 * writes Package.swift under sources/<name>/ without creating the directory.
 * Patch @capacitor/cli once so sync does not log a fatal ENOENT.
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const updateJs = path.resolve(
  __dirname,
  '..',
  'node_modules',
  '@capacitor',
  'cli',
  'dist',
  'ios',
  'update.js'
);

if (!fs.existsSync(updateJs)) {
  process.exit(0);
}

const marker = '/* nexchat: ensure cordova spm Package.swift dir */';
let content = fs.readFileSync(updateJs, 'utf8');

if (content.includes(marker)) {
  process.exit(0);
}

const original =
  "    await (0, fs_extra_1.writeFile)((0, path_1.join)(config.ios.cordovaPluginsDirAbs, 'sources', p.name, 'Package.swift'), content);";
const patched = `    const packageSwiftPath = (0, path_1.join)(config.ios.cordovaPluginsDirAbs, 'sources', p.name, 'Package.swift');
    ${marker}
    await (0, fs_extra_1.ensureDir)((0, path_1.dirname)(packageSwiftPath));
    await (0, fs_extra_1.writeFile)(packageSwiftPath, content);`;

if (!content.includes(original)) {
  console.warn('scripts/patch-capacitor-ios-spm: Capacitor update.js changed; patch skipped.');
  process.exit(0);
}

content = content.replace(original, patched);
fs.writeFileSync(updateJs, content);
console.log('Patched @capacitor/cli iOS SPM Cordova Package.swift mkdir.');
