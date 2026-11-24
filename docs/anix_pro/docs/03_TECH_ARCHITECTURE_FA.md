# 03 — معماری فنی پیشنهادی

## اصل معماری
**Modular Monolith در کلاینت + Backend domain services.** از Microserviceهای متعدد زودهنگام پرهیز شود. Flutter فعلی حفظ و مرزهای Domain، Repository و Service روشن‌تر شوند.

## معماری کلاینت Flutter
1. Presentation: صفحات، Widgetها، Design System و Navigation.
2. Application: Controller/Notifier و Use Case.
3. Domain: Entity، Value Object، Contract و Rules.
4. Data: Repository implementation، DTO و datasource.
5. Platform: Notifications، Camera، Audio، File، Deep Link و Secure Storage.

قواعد:
- Widget مستقیماً SQL/HTTP اجرا نکند.
- Repository interface از implementation جدا باشد.
- DTOهای Supabase از Domain Entity جدا باشند.
- Loading/Empty/Error/Offline/Success صریح باشند.
- Route و Permission از Policy مرکزی کنترل شود.
- Feature Flag برای فعال‌سازی مرحله‌ای.
- Logging ساختاریافته و dependency injection.
- Offline queue فقط برای عملیات idempotent و قابل همگام‌سازی.

## ماژول‌های محصول
identity_auth، profile_presence، social_graph، messaging، voice_video، rooms، arcade_catalog، game_runtime، matchmaking، tournaments_leagues، progression_rewards، wallet_economy، exchange_store، subscriptions، nova_gallery، oracle_ai، notifications، moderation_safety، admin_analytics و remote_config_updates.

## Backend هدف
### Core Supabase
مالک داده‌های هویت و تجربه عمومی:
- Auth و Profile
- Social graph
- پیام و محتوای اجتماعی
- ORACLE preferences و metadata
- Wallet ledger و Catalog/Store
- Notifications
- Moderation و Reports
- Admin audit

### Games Supabase
مالک دامنه بازی:
- Game catalog/config نسخه‌دار
- Matchmaking queues
- Rooms و seats
- Match state/events/snapshots
- Results و rating
- Tournament brackets و slots
- Anti-cheat signals و audit

دو پروژه فعلی باید یا با دلیل فنی حفظ شوند یا با Migration plan ادغام شوند. اگر جدا ماندند، ارتباط بین پروژه‌ها باید با JWT معتبر و Edge Function/سرویس مورد اعتماد انجام شود؛ user_id ارسالی کلاینت هویت معتبر نیست.

## مرزهای سرویس
- Supabase Auth: هویت و session.
- Postgres: تراکنش و داده ساخت‌یافته.
- Realtime: تحویل event/presence، نه مرجع اعتماد.
- Edge Functions: عملیات حساس و اتصال سرویس‌ها.
- LiveKit: رسانه با Token کوتاه‌عمر.
- Object Storage: تصویر/ویدئو با مسیر و Policy.
- Push provider: اعلان از سرور.
- Analytics/Crash: رخدادهای بدون اطلاعات حساس.

## بازی آنلاین
### نوبتی
- Server-authoritative turn/action.
- RPC تراکنشی برای ثبت Action.
- Realtime برای پخش Event.
- Snapshot برای reconnect.
- Idempotency key برای جلوگیری از ثبت تکراری.

### Real-time
- تعیین tick rate و مدل authority.
- ارزیابی WebSocket/LiveKit DataChannel یا سرور بازی اختصاصی.
- Client prediction فقط برای UX؛ سرور مرجع نتیجه.
- سنجش latency و reconciliation.
- انتخاب نهایی پس از Prototype بار و تست تقلب.

## عملکرد و مقیاس
- Pagination cursor-based برای Feed و پیام.
- Index مطابق query واقعی و EXPLAIN.
- Realtime subscription محدود و cleanup قطعی.
- Batch fetch و جلوگیری از N+1.
- Image resize/thumbnail و cache.
- Lazy loading و prefetch کنترل‌شده.
- Assetهای بازی در صورت امکان lazy load.
- انیمیشن Hub با تعداد ذره و FPS محدود؛ احترام به Reduce Motion.
- هدف اولیه Hub p95 زیر 2.5 ثانیه در دستگاه میان‌رده و شبکه معمولی پس از warm cache؛ سپس با داده واقعی تنظیم شود.

## محیط و Secrets
- Development، Staging و Production جدا.
- URL و anon key از Environment config و GitHub Variables.
- Service Role، DB password، LiveKit secret و signing keystore فقط در Secret Manager/GitHub Secrets.
- هیچ Secret در Dart، Asset، HTML، APK، README یا Log قرار نگیرد.
- Migration ابتدا Staging، سپس Production با Backup و Rollback plan.
- APIهای Breaking نسخه‌گذاری شوند.

## Observability
Correlation ID برای درخواست/room/match، Crash/ANR، Flutter frame jank، API latency/error، Realtime reconnect، Match queue wait، Payment reconciliation، Moderation SLA و گزارش‌های بدون PII.
