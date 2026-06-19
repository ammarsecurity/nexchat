#!/usr/bin/env node
/**
 * iOS bundle id differs from Android (capacitor.config appId).
 * Re-apply after `npx cap sync ios` so Xcode stays on com.nexchat.userapp.
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const IOS_BUNDLE_ID = 'com.nexchat.userapp';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const plat = process.env.CAPACITOR_PLATFORM_NAME;
if (plat && plat !== 'ios') {
  process.exit(0);
}

const pbxproj = path.join(__dirname, '..', 'ios', 'App', 'App.xcodeproj', 'project.pbxproj');
if (!fs.existsSync(pbxproj)) {
  process.exit(0);
}

const content = fs.readFileSync(pbxproj, 'utf8');
const updated = content.replace(
  /PRODUCT_BUNDLE_IDENTIFIER = [^;]+;/g,
  `PRODUCT_BUNDLE_IDENTIFIER = ${IOS_BUNDLE_ID};`
);

if (updated !== content) {
  fs.writeFileSync(pbxproj, updated, 'utf8');
  console.log(`scripts/ios-bundle-id: PRODUCT_BUNDLE_IDENTIFIER -> ${IOS_BUNDLE_ID}`);
}
