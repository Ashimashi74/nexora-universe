# 06 — برنامه اجرایی تیم و فازبندی

## فاز 0 — Discovery و Baseline
خروجی: گزارش معماری، نقشه صفحات، ماتریس قابلیت، تست مبنا و ADRها.
- Clone GitHub؛ اجرای Build/Analyze/Test.
- تست دستی روی دستگاه.
- استخراج Schema و Migration status.
- تطبیق دو پروژه Supabase.
- تفکیک قابلیت کامل، نیمه‌کاره، نمایشی و خراب.
- قفل‌کردن نام برند، package id و نسخه‌بندی.
**معیار خروج:** تصمیم‌های حیاتی Auth، دیتابیس، نام محصول و بازی‌ها مبهم نماند.

## فاز 1 — Stabilization
خروجی: نسخه پایدار از محصول فعلی بدون فیچر جدید.
- رفع Crash، Login loop، Splash گیرکرده و Navigation.
- رفع کندی Hub و تعویض صفحات.
- رفع Realtime subscription leak.
- اصلاح reconnect/session و بازی‌های موجود.
- تست مسیرهای حیاتی و Deep Link.

## فاز 2 — Pro UI Shell
خروجی: پوسته Station Luxe در Flutter.
- Theme و Design tokens.
- Hub Carousel، World cards، Bottom nav و More.
- Header/Wallet/Profile با داده زنده.
- صفحات Home، Play، Social، Compete، Profile، Exchange و ORACLE.
- RTL، انگلیسی، accessibility و performance.
- Feature Flag برای مهاجرت تدریجی.

## فاز 3 — Backend Hardening
خروجی: بک‌اند امن و قابل مشاهده.
- Schema inventory و Migration plan.
- RLS audit و security tests.
- Auth cross-project.
- Wallet ledger و idempotency.
- Room/Match authority.
- Notification pipeline.
- LiveKit token security.
- Logs، metrics، alerts و backups.

## فاز 4 — Social & Community Pro
Friends/follow/block/report، DM/group/channel، voice rooms/calls، Feed/stories/media، invites و moderation/admin console.

## فاز 5 — Competition & Progression
Daily/weekly challenges، XP/levels/achievements، ELO/MMR per game، tournaments/leagues، seasons/leaderboards و anti-cheat/dispute flow.

## فاز 6 — Games Expansion
ابتدا Game Contract و test harness؛ سپس Wave A پنج بازی؛ تست local/bot/online/reconnect؛ انتشار تدریجی با Remote Config؛ Wave B/C پس از KPI و پایداری.

## فاز 7 — Economy & Monetization
Catalog/inventory، Coin/Gem ledger، Google Play Billing و server verification، Gift code/gifting، subscription/season pass، refund/chargeback و reconciliation.

## فاز 8 — ORACLE & Personalization
Context محدود و مجاز، AI quotas، help center/game coach، recommendations با Opt-in، usage analytics و abuse controls.

## فاز 9 — Beta / Release
Closed testing، تست بار/امنیت/privacy/پرداخت، تست دستگاه ضعیف و میان‌رده، release notes، privacy policy، terms، support، Play Console، staged rollout و rollback.

## اولویت
- P0: پایداری، امنیت، هویت برند، بک‌اند و بازی‌های موجود.
- P1: Station UI، Social/Rooms، Competition و Wallet ledger.
- P2: موج اول بازی‌ها، Season/Pass و ORACLE بهتر.
- P3: موج‌های بعدی، Creator features و Personal Space پیشرفته.

زمان تقویمی معتبر بدون دانستن تیم و Build baseline ممکن نیست. پس از Discovery هر فاز به Story Point و Sprint تقسیم شود؛ قول انتشار قطعی پیش از Baseline داده نشود.
