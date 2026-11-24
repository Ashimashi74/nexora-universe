# 07 — تست، معیار پذیرش و انتشار

## Quality Gates
هر Pull Request باید Format و Static analysis، Unit/Widget tests مرتبط، بررسی Secret، Migration/RLS review، Screenshot/Video تغییر UI، Performance regression check و ترجمه فارسی/انگلیسی را پاس کند.

## تست‌های ضروری
### Auth
ثبت‌نام، ورود، خروج، refresh، فراموشی رمز، تغییر username، session پس از kill/relaunch، مهمان و ارتقا، Deep link، خطای شبکه و JWT verification بین دو Supabase.

### Social
Follow/unfollow/request، private profile، block، پیام create/edit/delete، read receipt، pagination، Room roles/moderation و report.

### Games
قوانین مرزی و property tests، Bot difficulty، دو Action هم‌زمان، retry/duplicate، disconnect در هر مرحله، reconnect/snapshot، ثبت یک‌باره نتیجه، matchmaking race، 1v1/2v2/3v3 فقط برای بازی پشتیبان، tournament no-show/dispute.

### Economy
درخواست خرید هم‌زمان، retry با idempotency key، Gift Code منقضی/مصرف‌شده، refund/chargeback، دستکاری قیمت در Client و RLS برای جلوگیری از تغییر موجودی.

### Android
نسخه‌های پشتیبانی‌شده، نصب تمیز و Update، permission denied/revoked، background/foreground، Back button، deep links، دوربین/میکروفون، notification permission، low memory و network switching.

## Performance budgets اولیه
- Crash-free sessions حداقل 99.5% در Beta و هدف 99.8%+ پس از تثبیت.
- بدون ANR بحرانی.
- Hub p95 زیر 2.5 ثانیه در دستگاه مرجع میان‌رده و شبکه معمولی پس از warm cache؛ با اندازه‌گیری واقعی نهایی شود.
- تعویض صفحه بدون jank محسوس؛ فریم‌های طولانی ثبت و اصلاح شوند.
- حافظه و باتری برای نشست 30 دقیقه‌ای ثبت شود.
- حجم APK/AAB و Assetها در هر Release گزارش شود.
- reconnect بازی نوبتی بدون از دست‌رفتن نتیجه.

## Security release gate
RLS همه جدول‌های exposed، عدم وجود Service Role/LiveKit secret/keystore در Client، Storage policies، privilege escalation، Rate limit، Secure Deep Links، حذف حساب، Privacy policy، Terms، Community Guidelines و بررسی وابستگی‌ها.

## GitHub workflow پیشنهادی
- PR: format → analyze → unit/widget tests → security scan → debug build.
- Main: full tests → AAB و APK artifacts → staging deployment.
- Release tag: signed production artifact → smoke tests → GitHub Release → Play Console rollout.
- Build provenance و changelog.
- Signing key دائمی و Backup امن؛ از debug keystore برای Production استفاده نشود.
- GitHub Secrets برای keystore/password و server secrets؛ Variables برای URL و publishable keys.
- Branch protection و required reviews.
- Migration با approval مجزا برای Production.

## انتشار
- تعیین `applicationId` نهایی پیش از انتشار عمومی؛ تغییر آن بعد از انتشار اپ جداگانه می‌سازد.
- Production signing key و Backup آفلاین.
- `versionName` و `versionCode` افزایشی.
- Android App Bundle برای Play و APK برای توزیع مستقیم در صورت نیاز.
- Data Safety، Content Rating، Privacy policy و Account deletion.
- پشتیبانی و راه گزارش مشکل.
- staged rollout، monitoring و rollback.

## معیار Done برای هر Feature
1. UI نهایی و فارسی/انگلیسی.
2. API و RLS مستند و تست‌شده.
3. Loading/Empty/Error/Offline/Success.
4. Unit/Widget/Integration tests.
5. Analytics و error logging مناسب.
6. Accessibility و performance بررسی‌شده.
7. Admin/moderation و privacy مشخص.
8. مستندات به‌روز.
9. تأیید روی Staging و دستگاه واقعی.

## تحویل نهایی تیم
سورس GitHub با PR و تاریخچه، Schema diagram و Data dictionary، Migrationها و Edge Functions، API contract، Figma/Design tokens و Asset manifest، تست و CI report، APK/AAB امضاشده، Runbook عملیات و Backup/Restore، Privacy/Terms/Moderation policies، Known issues و برنامه رفع.
