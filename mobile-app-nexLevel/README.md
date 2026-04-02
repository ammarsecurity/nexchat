# NexChat – نيكس شات

## تغيير أيقونة التطبيق

1. **ضع الأيقونة الجديدة** في المشروع بدلاً من الملف الحالي:
   - المسار: **`src/assets/icon.png`**
   - الحجم الموصى به: **1024×1024 بكسل**، بصيغة PNG (يمكن أن تكون الخلفية شفافة).

2. **ولّد كل أحجام الأيقونة لـ iOS و Android و PWA:**
   ```bash
   npm run assets
   ```

3. **مزامنة المنصات** (حتى تظهر الأيقونة في التطبيق):
   ```bash
   npm run sync:ios
   npm run sync:android
   ```
   ثم أعد البناء من Xcode أو Android Studio.

ألوان خلفية الأيقونة (في سكربت `assets` داخل package.json): الوضع الفاتح `#6C63FF`، الوضع الداكن `#0D0D1A`. يمكنك تعديلها في السطر الخاص بـ `npm run assets`.

---

## iOS و OneSignal

لتشغيل الإشعارات (Push) على iOS:
1. استخدم `npm run sync:ios` أو `npm run ios` (ينفّذ إعداد OneSignal تلقائياً بعد المزامنة).
2. بعد أي `npx cap sync ios` يدوي، شغّل: `node scripts/setup-ios-onesignal.js` لاستعادة حزمة OneSignal.
3. إذا ظهر "Cordova Plugin mapping not found": نفّذ **Product → Clean Build Folder** في Xcode ثم أعد البناء وتشغيل التطبيق.
