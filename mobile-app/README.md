# Vue 3 + Vite

This template should help get you started developing with Vue 3 in Vite.

## iOS و OneSignal

لتشغيل الإشعارات (Push) على iOS:
1. استخدم `npm run sync:ios` أو `npm run ios` (ينفّذ إعداد OneSignal تلقائياً بعد المزامنة).
2. بعد أي `npx cap sync ios` يدوي، شغّل: `node scripts/setup-ios-onesignal.js` لاستعادة حزمة OneSignal.
3. إذا ظهر "Cordova Plugin mapping not found": نفّذ **Product → Clean Build Folder** في Xcode ثم أعد البناء (Build) وتشغيل التطبيق. The template uses Vue 3 `<script setup>` SFCs, check out the [script setup docs](https://v3.vuejs.org/api/sfc-script-setup.html#sfc-script-setup) to learn more.

Learn more about IDE Support for Vue in the [Vue Docs Scaling up Guide](https://vuejs.org/guide/scaling-up/tooling.html#ide-support).
