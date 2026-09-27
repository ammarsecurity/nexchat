# TikTok App Events SDK — التحقق

## المعرفات

| الحقل | القيمة |
|--------|--------|
| Android App ID | `site.nexchat.app` |
| iOS App ID | `com.nexchat.userapp` |
| TikTok App ID | `7690289134248394760` |
| App Secret | مضبوط افتراضياً في `Env.tikTokAppSecret` (يدخل مع كل تصدير) |

## البناء

السر مضمّن في التطبيق؛ أي `flutter run` / `flutter build apk` / `appbundle` يكفي بدون `--dart-define`.

لتجاوز السر عند الحاجة:

```bash
flutter build apk --dart-define=TIKTOK_APP_SECRET=OTHER_SECRET
```

## اختبار الأحداث (Debug)

1. ثبّت على **جهاز حقيقي** (ليس iOS Simulator — الـ SDK لا يرسل منه).
2. شغّل بوضع Debug (`isDebugMode: true` تلقائياً).
3. في TikTok Ads Manager → **Tools → Events** → تطبيقك → تبويب **Test event**.
4. افتح التطبيق → يفترض ظهور LaunchApp / Install.
5. سجّل حساباً جديداً → `Registration`.
6. سجّل دخولاً → `Login`.
7. سجّل خروجاً → يُمسح تعريف المستخدم من الـ SDK.

أحداث Debug تظهر في **Test event** وليس في **Event Activity**. بعد التحقق، ابنِ Release (`isDebugMode: false`) وراقب Event Activity بعد اكتمال تحقق التطبيق في Events Manager.

## استكشاف الأخطاء

- تأكد أن App ID / TikTok App ID يطابقان Events Manager بدون مسافات.
- ابحث في Logcat عن `TikTokBusinessSdk` أو في Xcode عن `TikTok`.
- لا تحجب `*.tiktokv.com` / `*.tiktokw.us`.
