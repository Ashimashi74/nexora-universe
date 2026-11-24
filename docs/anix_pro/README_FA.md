# بسته تحویل توسعه NEXORA PRO
نسخه 1.0 — 20 نوامبر 2026

این بسته نقشه اجرایی محصول، معماری، بک‌اند، بازی‌ها، UI، امنیت، تست و انتشار برای تیم توسعه است. جایگزین سورس اصلی نیست.

## ورودی‌هایی که همراه بسته به تیم داده شوند
1. `nexora-universe-work-fs-v7.zip` — سورس Flutter/Dart.
2. `NEXORA_Station_Luxe.zip` — مرجع HTML/CSS/JS و تصاویر.
3. این بسته — شرح محصول و برنامه اجرایی.

نسخه HTML و تصاویر آن نیز در پوشه `reference/NEXORA_Station_Luxe/` قرار دارد.

## ترتیب مطالعه
- `docs/00_AUDIT_FA.md` — یافته‌های واقعی از سورس و UI.
- `docs/01_PRODUCT_VISION_FA.md` — تعریف محصول.
- `docs/02_GAME_ROADMAP_FA.md` — بازی‌های فعلی و ۱۵ بازی پیشنهادی.
- `docs/03_TECH_ARCHITECTURE_FA.md` — معماری.
- `docs/04_BACKEND_DATA_SECURITY_FA.md` — داده، API و امنیت.
- `docs/05_UI_UX_IMPLEMENTATION_FA.md` — UI.
- `docs/06_DELIVERY_ROADMAP_FA.md` — فازبندی.
- `docs/07_QA_ACCEPTANCE_RELEASE_FA.md` — تست و انتشار.
- `docs/08_TEAM_KICKOFF_CHECKLIST_FA.md` — شروع تیم.

## دستورهای قطعی
- سورس فعلی را ممیزی و تکمیل کنید؛ بازنویسی از صفر بدون RFC و تأیید ممنوع.
- هیچ دکمه، خرید، پیام، روم، امتیاز یا بازی نباید Mock باقی بماند.
- تمام عملیات حساس بازی، کیف پول، رتبه‌بندی و پاداش سمت سرور معتبرسازی شوند.
- Service Role، LiveKit Secret، رمز DB و کلید امضای APK هرگز داخل APK یا Git قرار نگیرند.
- UI مرجع در Flutter بازسازی شود؛ WebView راه‌حل پیش‌فرض نیست.
- انتشار فقط پس از عبور از معیارهای پذیرش مجاز است.

## محدودیت بررسی
این بررسی Static Audit از ZIPهاست. اجرای واقعی Flutter، تست روی دستگاه، تست بار، بررسی دیتابیس زنده و Build Release انجام نشده و باید در فاز صفر توسط تیم ثبت شود.
