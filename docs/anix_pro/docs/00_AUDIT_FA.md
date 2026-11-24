# 00 — گزارش ممیزی سورس و UI

## خلاصه مدیریتی
سورس فعلی پایه قابل‌توجهی برای نسخه Pro دارد: Flutter، Riverpod، GoRouter، 16 ورودی بازی، ماژول‌های اجتماعی، اتاق‌ها، فروشگاه/Exchange، ORACLE، تورنمنت، Supabase، LiveKit، Migrationها، تست‌ها و GitHub Actions. پیشنهاد: همین محصول را تکمیل و سخت‌سازی کنید، نه اینکه از صفر اپ جدا بسازید.

## موجودی واقعی مشاهده‌شده
| مورد | نتیجه بررسی ZIP |
|---|---|
| اپ | Flutter / Dart |
| فایل Dart زیر lib | 261 |
| فایل Dart در games | 123 |
| فایل Dart در worlds | 84 |
| فایل تست زیر test | 56 |
| ورودی بازی | 16 فایل `*_entry.dart` |
| Migration اصلی | 21 فایل در `supabase/migrations` |
| Migration بازی | 14 فایل در `supabase/games/migrations` |
| Edge Function | 3: `nx-login`، `nx-call-token`، `nx-oracle` |
| Backend | دو پروژه Supabase |
| تماس صوت/تصویر | LiveKit |
| CI | GitHub Actions |
| Git history | پوشه `.git` داخل ZIP نیست |

### بازی‌های فعلی
Finger Soccer، Carrom، Billiards، Backgammon، Ludo، Snakes & Ladders، UNO، Quiz، Mafia، Kart Racing، Obstacle Race، Bomb Arena، Pool8، Mini Golf، Basketball Battle، Spy Mafia.

Billiards و Pool8 از نظر دامنه هم‌پوشانی نام دارند؛ تیم باید تفاوت قوانین و تجربه آن‌ها را بررسی کند و تصمیم بگیرد دو بازی جدا بمانند یا یک بازی با مودهای مختلف باشند.

## جهان‌ها و ماژول‌های موجود
Registry جهان‌ها شامل NOVA GALLERY، ORBIT NETWORK، NEXORA ARCADE، ORACLE CORE، PERSONAL ORBIT، SOCIAL STATION و NEXORA EXCHANGE است. کدهای Rooms/Talk Room، Online Lobby/Match، Leaderboard، Tournament، Admin، Profile، Settings و Update نیز وجود دارند.

## ریسک‌های مهم
### P0 — قبل از توسعه فیچر جدید
1. **هویت برند ناهمسان:** HTML نام NEXORA دارد، اما Flutter MaterialApp، README و بخشی از workflow از ANIX استفاده می‌کنند. نام رسمی، label، package id، آیکون، Release و متن‌ها یکسان شوند. نام داخلی را بدون بررسی مهاجرت حذف نکنید.
2. **دو پروژه Supabase:** Core و Games دو URL مجزا دارند. مالکیت داده، اعتبارسنجی JWT بین دو پروژه، RLS، حذف حساب و هماهنگی Migrationها باید مستند و تست شود.
3. **تناقض مستندات بازی:** کامنت Registry از «۲۰ بازی جدید» می‌گوید، اما Registry اجرایی فعلی ۷ ورودی آرکید و در مجموع ۱۶ ورودی دارد. README نیز ۱۶ بازی اعلام می‌کند. فهرست انتشار باید از Registry اجرایی تولید شود، نه کامنت یا Asset.
4. **کلیدهای عمومی در Workflow:** anon/publishable key در Workflow دیده می‌شود. این کلیدها Secret سرور نیستند، ولی باید از GitHub Variables یا dart-define مدیریت شوند. Service Role و هر Secret سرور هرگز در APK/Git نباشد.
5. **نبود Git history:** تیم باید مخزن canonical GitHub را Clone کند؛ ZIP تاریخچه و شاخه‌ها ندارد.
6. **بیلد اثبات نشده:** وجود workflow و تست‌ها تضمین نمی‌کند سورس فعلی Build می‌شود. CI باید روی commit مبنا اجرا و گزارش شود.

### P1 — قبل از Beta
- Crash/ANR، Login، Reconnect، مصرف باتری/حافظه و حجم APK اندازه‌گیری شود.
- RLS برای کاربر عادی، مهمان، مسدودشده، مدیر و مهاجم تست شود.
- حذف/غیرفعال‌سازی حساب و پاک‌سازی داده‌ها تعریف شود.
- Rate limit و Moderation برای چت، پیام، دعوت، پاداش، مسابقه و ORACLE.
- تست بازی آنلاین با قطع اینترنت، دو دستگاه و شبکه‌های مختلف.

## ممیزی HTML Station Luxe
### اجزای طراحی
- مشکی عمیق و طلایی، Vazirmatn و Cormorant Garamond.
- Hub مرکزی با Carousel کارت‌های سه‌بعدی.
- هشت دسته: بازی‌ها، رویدادها، جایزه‌ها، AI، چت، فروشگاه، پروفایل و تورنمنت.
- Bottom navigation پنج‌قسمتی با دکمه مرکزی بزرگ Play و پنل More.
- پنل پروفایل و روم‌های فعال، کارت‌های دو ستونه، Tab، Sheet و ذرات پس‌زمینه.
- RTL، safe-area و reduced-motion در CSS دیده شده‌اند.

### Prototype است، نه UI آماده انتشار
- پروفایل، سطح، XP، سکه، جم و تعداد روم‌ها ثابت‌اند.
- خرید/هدیه/علاقه‌مندی فقط Toast «به‌زودی» می‌دهند.
- تابع `openSheet` تعریف شده، اما اتصال کلیک کارت‌های Grid باید تکمیل و تست شود؛ در فایل بررسی‌شده اتصال قابل اتکایی برای بازکردن Sheet از کارت پیدا نشد.
- داده‌ها در آرایه‌های ثابت JS هستند و Repository/API ندارند.
- صفحه‌های مقصد، Loading، Empty، Error و Offline واقعی وجود ندارند.
- بعضی asset pathهای معرفی‌شده برای بک‌گراندهای جهان در ZIP وجود ندارند و Prototype به fallback گرادیانی متکی است.
- ذرات و parallax با requestAnimationFrame باید در Flutter lifecycle-controlled و با محدودیت FPS/باتری پیاده شوند.

## تصمیم
HTML مرجع بصری باشد؛ رفتار و معماری از Flutter موجود بیاید. UI در Flutter Native بازسازی شود، نه اینکه کل Prototype به WebView تبدیل شود.

## کارهای روز اول تیم
1. Clone مخزن و ثبت commit مبنا.
2. ثبت نسخه Flutter/Dart/Java/Gradle/SDK.
3. اجرای `flutter pub get`, `flutter analyze`, `flutter test`.
4. ساخت Debug APK و اجرا روی دو دستگاه.
5. اجرای Migrationها در Staging خالی و مقایسه Schema.
6. تست End-to-End برای Login، Profile، Room، بازی آنلاین/آفلاین، چت و ORACLE.
7. ثبت خطا با Severity، فایل و خط.

## محدودیت ممیزی
این گزارش Static Audit از ZIPهاست. سلامت سرویس‌های زنده، اجرای همه مسیرها، صحت SQL در دیتابیس زنده، کیفیت روی دستگاه و وضعیت Production از روی ZIP قابل اثبات نیست.
