# 08 — چک‌لیست شروع همکاری تیم

## پیش از شروع
- [ ] دسترسی Read به GitHub و دسترسی کنترل‌شده به Supabase Staging.
- [ ] تأیید نام رسمی: NEXORA یا ANIX.
- [ ] تأیید `applicationId` و بررسی اینکه نسخه عمومی قبلی با آن منتشر شده یا نه.
- [ ] تعیین Product Owner، Tech Lead، Backend Lead، Mobile Lead، QA و UI/UX.
- [ ] مشخص‌کردن کشورهای انتشار و الزامات قانونی.
- [ ] تهیه Figma از HTML مرجع و تأیید صفحات.
- [ ] تعیین Development/Staging/Production.
- [ ] تعیین سیاست داده، حریم خصوصی، Moderation و حذف حساب.

## جلسه فنی
- [ ] مرور 261 فایل Dart و مرزبندی ماژول‌ها.
- [ ] مرور 16 بازی و وضعیت واقعی هرکدام.
- [ ] مرور 21 Core migration و 14 Games migration.
- [ ] مرور 3 Edge Function موجود.
- [ ] بررسی Auth و دو پروژه Supabase.
- [ ] اجرای CI و ثبت خط مبنا.
- [ ] ثبت ریسک‌ها با Owner و Deadline.
- [ ] تصویب ADR برای معماری Backend و اقتصاد.

## قبل از Beta
- [ ] هیچ داده ثابت Prototype در UI واقعی باقی نماند.
- [ ] همه CTAها و کارت‌ها به مسیر واقعی متصل باشند.
- [ ] RLS و Wallet تست شوند.
- [ ] بازی آنلاین و Reconnect تست شوند.
- [ ] Crash/ANR و Performance گزارش شود.
- [ ] Report/Block/Moderation وجود داشته باشد.
- [ ] Privacy Policy و Account deletion آماده باشد.
- [ ] Backup/Restore و Incident runbook آماده باشد.
- [ ] پرداخت در Sandbox تست شود.
- [ ] Release signing و Play Console آماده باشد.

## پرسش‌هایی که تیم باید با شواهد جواب دهد
1. کدام قابلیت‌ها واقعاً Production-ready هستند؟
2. آیا دو پروژه Supabase لازم‌اند؟ چرا؟
3. کدام بازی‌ها Online و Server-authoritative هستند؟
4. چه چیزی باعث کندی صفحات یا شروع نامطمئن اپ می‌شود؟
5. آیا نتیجه بازی، XP و موجودی از سمت سرور محاسبه می‌شوند؟
6. آیا نسخه جدید بدون حذف نسخه قبلی Update می‌شود؟
7. هزینه ماهانه Backend، Realtime، LiveKit، AI و Storage چقدر است؟
8. برای 1k، 10k و 100k کاربر هم‌زمان چه محدودیت‌هایی وجود دارد؟
9. سیاست گزارش محتوا، پشتیبانی و حذف حساب چیست؟
10. چه قابلیت‌هایی در Pro v1 می‌آیند و چه چیزهایی پشت Feature Flag می‌مانند؟
