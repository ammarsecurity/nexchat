# أصول Capacitor - أيقونة التطبيق

لتعديل أيقونة التطبيق:

1. **ضع الأيقونة** في `src/assets/icon.png` (أو استبدل `assets/icon.png`)
   - الحجم الموصى به: **1024×1024 بكسل** (PNG بخلفية شفافة أو ملونة)
   - عند استخدام `src/assets/icon.png` سيتم نسخها تلقائياً عند تشغيل `npm run assets`

2. **شغّل توليد الأصول:**
   ```bash
   npm run assets
   ```

3. سيتم إنشاء الأيقونات لـ:
   - **PWA** (التطبيق على الويب)
   - **iOS** (عند إضافة المنصة: `npx cap add ios`)
   - **Android** (عند إضافة المنصة: `npx cap add android`)

### ألوان الخلفية (في package.json)
- `--iconBackgroundColor` و `--splashBackgroundColor`: للوضع الفاتح
- `--iconBackgroundColorDark` و `--splashBackgroundColorDark`: للوضع الداكن
