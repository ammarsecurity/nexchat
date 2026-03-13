#!/usr/bin/env node
/**
 * Restores OneSignal Cordova plugin for iOS SPM after `npx cap sync ios`.
 * Cap sync overwrites capacitor-cordova-ios-plugins and puts this plugin in
 * sourcesstatic/; we need sources/OnesignalCordovaPlugin with Package.swift + bridge files.
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const rootDir = path.resolve(__dirname, '..');
const pluginSrc = path.join(rootDir, 'node_modules', 'onesignal-cordova-plugin', 'src', 'ios');
const cordovaPluginsDir = path.join(rootDir, 'ios', 'capacitor-cordova-ios-plugins');
const targetDir = path.join(cordovaPluginsDir, 'sources', 'OnesignalCordovaPlugin');
const packageTemplate = path.join(rootDir, 'scripts', 'ios-onesignal-package.swift');

if (!fs.existsSync(pluginSrc)) {
  console.warn('scripts/setup-ios-onesignal: onesignal-cordova-plugin not found, skipping.');
  process.exit(0);
}

if (!fs.existsSync(cordovaPluginsDir)) {
  console.warn('scripts/setup-ios-onesignal: ios/capacitor-cordova-ios-plugins not found. Run "npx cap sync ios" first.');
  process.exit(0);
}

fs.mkdirSync(targetDir, { recursive: true });

['OneSignalPush.h', 'OneSignalPush.m'].forEach((file) => {
  const src = path.join(pluginSrc, file);
  const dest = path.join(targetDir, file);
  if (fs.existsSync(src)) {
    fs.copyFileSync(src, dest);
    if (file === 'OneSignalPush.m') {
      let content = fs.readFileSync(dest, 'utf8');
      // SPM does not expose OneSignalLiveActivities; disable so plugin builds and Push works
      content = content.replace(
        /#import "OneSignalLiveActivities\/OneSignalLiveActivities-Swift.h"/,
        '// #import "OneSignalLiveActivities/OneSignalLiveActivities-Swift.h" // SPM'
      );
      // Wrap all Live Activities methods in #if 0 so they compile without that module
      const liveActivitiesStart = content.indexOf('\n/**\n * Live Activities\n */');
      const customEventsMarker = content.indexOf('\n/**\n * Custom Events\n */');
      if (liveActivitiesStart !== -1 && customEventsMarker > liveActivitiesStart) {
        const before = content.slice(0, liveActivitiesStart);
        const block = content.slice(liveActivitiesStart, customEventsMarker);
        const after = content.slice(customEventsMarker);
        content = before + '\n#if 0 // Live Activities not available in SPM build\n' + block + '\n#endif\n' + after;
      }
      fs.writeFileSync(dest, content);
    }
    console.log('Copied', file, '-> sources/OnesignalCordovaPlugin/');
  }
});

if (fs.existsSync(packageTemplate)) {
  fs.copyFileSync(packageTemplate, path.join(targetDir, 'Package.swift'));
  console.log('Restored Package.swift for OnesignalCordovaPlugin (OneSignal SPM).');
}

// Ensure config.xml is valid UTF-8 XML (avoids NSXMLParser abort in CDVConfigParser)
const configPath = path.join(rootDir, 'ios', 'App', 'App', 'config.xml');
if (fs.existsSync(configPath)) {
  const configContent = `<?xml version="1.0" encoding="UTF-8"?>
<widget version="1.0.0" xmlns="http://www.w3.org/ns/widgets" xmlns:cdv="http://cordova.apache.org/ns/1.0">
  <access origin="*" />
  <feature name="OneSignalPush">
    <param name="ios-package" value="OneSignalPush" />
  </feature>
</widget>
`;
  fs.writeFileSync(configPath, configContent, 'utf8');
  console.log('Updated config.xml (valid XML for iOS parser).');
}

console.log('iOS OneSignal plugin setup done.');
